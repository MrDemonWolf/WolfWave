//
//  WebSocketServerService.swift
//  WolfWave
//
//  Created by Nathanial Henniges on 2026-02-20.
//  Copyright © 2026 MrDemonWolf, Inc. All rights reserved.
//

import Foundation
import Network

// MARK: - WebSocket Server Service

/// Broadcasts now-playing data to stream overlay clients over a local WebSocket connection.
///
/// Built on `NWListener` (Network.framework). Overlay clients such as OBS browser sources
/// connect and receive JSON messages for track changes, progress ticks, and playback state.
/// State is actor-confined; a small snapshot is exposed for synchronous `nonisolated` reads
/// from SwiftUI views, and a `stateChanges` `AsyncStream` replaces the legacy callback.
///
/// ## Security model
///
/// - The listener binds to all interfaces so LAN peers (a second-PC OBS, a phone
///   browser) can reach the widget. Two-PC setups would otherwise be impossible.
/// - Overlay clients authenticate with a read-only `wolfwave.overlay.<hex>`
///   subprotocol. They receive state broadcasts but cannot execute commands.
/// - Stream Deck authenticates with a separate `wolfwave.control.<hex>`
///   subprotocol. Control-role connections are accepted only from a literal
///   loopback IP, and only that role can execute commands.
/// - Local widgets get the overlay token for free: `WidgetHTTPService` injects it into
///   the served `widget.html` only for a loopback TCP peer with a literal-local
///   Host header, so same-Mac OBS Browser Sources "just work" without exposing
///   the credential to DNS-rebinding requests. Remote browsers use `?token=…`
///   as bootstrap for the WebSocket subprotocol.
/// - Connections without a valid role-specific subprotocol are rejected before
///   they can receive playback frames.
/// - Rotating either credential restarts the listener so authorized clients are dropped.
/// - The initializer that omits credentials exists for lifecycle tests and
///   grants only the read-only overlay role.
actor WebSocketServerService {

    /// Hard receive bound applied by Network.framework before a complete
    /// WebSocket message is materialized. Current control frames are tiny;
    /// 16 KiB leaves generous protocol headroom without permitting an
    /// authenticated peer to force an unbounded fragmented-message allocation.
    nonisolated static let maximumInboundMessageSize = 16 * 1024
    nonisolated static let maximumPendingConnectionCount = 16
    nonisolated static let maximumConnectionCount = 64
    private static let handshakeTimeout: Duration = .seconds(10)

    // MARK: - Types

    enum ServerState: String, Sendable {
        case stopped, starting, listening, error
    }

    /// Lightweight snapshot of one queued request for the overlay's queue
    /// ticker. Deliberately decoupled from `SongRequestItem` (which carries a
    /// MusicKit `Song` this actor should never import) — mirrors the existing
    /// `count`/`pending` decoupling in `broadcastQueueState`.
    struct QueueUpcomingItem: Sendable, Equatable {
        let title: String
        let requesterUsername: String
    }

    // MARK: - Nonisolated Snapshot

    /// Protects the snapshot variables read from outside the actor.
    private nonisolated let snapshotLock = NSLock()
    nonisolated(unsafe) private var _stateSnapshot: ServerState = .stopped
    nonisolated(unsafe) private var _connectionCountSnapshot: Int = 0
    nonisolated(unsafe) private var _overlayVisibleSnapshot = true

    /// Latest server state, safe to read synchronously from any thread.
    nonisolated var state: ServerState {
        snapshotLock.withLock { _stateSnapshot }
    }

    /// Latest connected-client count, safe to read synchronously from any thread.
    nonisolated var connectionCount: Int {
        snapshotLock.withLock { _connectionCountSnapshot }
    }

    /// Whether playback cards are currently allowed to render. Stream Deck uses
    /// this visibility switch instead of stopping the shared command transport.
    nonisolated var overlayVisible: Bool {
        snapshotLock.withLock { _overlayVisibleSnapshot }
    }

    private func writeStateSnapshot(_ newState: ServerState) {
        snapshotLock.withLock { _stateSnapshot = newState }
    }

    private func writeConnectionCountSnapshot(_ count: Int) {
        snapshotLock.withLock { _connectionCountSnapshot = count }
    }

    private func writeOverlayVisibleSnapshot(_ visible: Bool) {
        snapshotLock.withLock { _overlayVisibleSnapshot = visible }
    }

    // MARK: - State Change Stream

    /// Replaces the legacy `onStateChange` callback. Consumers iterate
    /// `for await (state, clientCount) in service.stateChanges`.
    nonisolated let stateChanges: AsyncStream<(ServerState, Int)>
    private nonisolated let stateContinuation: AsyncStream<(ServerState, Int)>.Continuation

    /// Number of currently-connected overlay clients. Safe to call from any
    /// thread. Used by the tray menu's "Stream Widgets" status subtitle.
    nonisolated var connectedClientCount: Int { connectionCount }

    /// The port the listener actually bound, or `nil` before it binds. Differs
    /// from the configured port only when that was `0`, which asks the kernel
    /// for a free ephemeral port. Tests bind `0` and read this back so they can
    /// never collide with an unrelated process holding a hardcoded port.
    var boundPort: UInt16? {
        listener?.port?.rawValue
    }

    // MARK: - Properties

    private var port: UInt16
    /// Read-only credential used by OBS widgets and other state consumers.
    /// `nil` only in lifecycle tests that construct the legacy initializer.
    private var overlayToken: String?
    /// Privileged credential used by same-Mac Stream Deck clients.
    /// `nil` only in lifecycle tests that construct the legacy initializer.
    private var controlToken: String?
    private var listener: NWListener?
    private var connections: [NWConnection] = []
    /// The authenticated role of each entry in ``connections``.
    ///
    /// Overlay and control clients want different things from the same server:
    /// hiding the overlay cards must stop the browser source rendering, but a
    /// Stream Deck still needs to know what is playing. Keeping the role lets
    /// the playback fan-out address one audience without the other.
    private var connectionRoles: [ObjectIdentifier: WebSocketAuthToken.Role] = [:]
    /// Accepted TCP peers that have not completed the authenticated WebSocket
    /// handshake. They are capped, timed out, and owned across listener stop.
    private var pendingConnections: [NWConnection] = []
    private var handshakeTimeoutTasks: [ObjectIdentifier: Task<Void, Never>] = [:]
    private var listenerGeneration: UInt64 = 0
    /// Dispatch queue used only for Network.framework callbacks. All state is actor-confined.
    private nonisolated let networkQueue = DispatchQueue(
        label: AppConstants.DispatchQueues.websocketServer,
        qos: .utility
    )
    private var isEnabled = false
    private var widgetHTTP: WidgetHTTPService?
    private var widgetHTTPPort: UInt16?
    private var retryTask: Task<Void, Never>?

    /// Handler invoked for each inbound Stream Deck command, returning the ack to
    /// send back on the originating connection. Set by AppDelegate via
    /// ``setCommandHandler(_:)``; the service itself knows nothing about the
    /// app's services, keeping this layer decoupled and testable.
    private var onCommand: (@Sendable (StreamDeckCommand) async -> CommandAck)?

    // MARK: - Playback State

    private var currentTrack: String?
    private var currentArtist: String?
    private var currentAlbum: String?
    private var currentDuration: TimeInterval = 0
    private var currentElapsed: TimeInterval = 0
    private var isPlaying = false
    private var isOverlayVisible = true
    private var currentArtworkURL: String?
    private var lastElapsedUpdate: Date?
    private var progressTask: Task<Void, Never>?
    private var currentProgressInterval: TimeInterval = AppConstants.WebSocketServer.progressBroadcastInterval

    /// Last-broadcast upcoming-queue snapshot, replayed to freshly-connected
    /// clients the same way `currentTrack` is. Unlike `broadcastQueueState`
    /// (counts only, never replayed), the ticker needs replay-on-connect so an
    /// OBS Browser Source reload doesn't show an empty/stale ticker until the
    /// next queue mutation.
    private var currentQueueUpcoming: [QueueUpcomingItem] = []

    // MARK: - Init

    init(port: UInt16 = AppConstants.WebSocketServer.defaultPort) {
        self.port = port
        self.overlayToken = nil
        self.controlToken = nil
        let (stream, continuation) = AsyncStream<(ServerState, Int)>.makeStream(
            bufferingPolicy: .bufferingNewest(64)
        )
        self.stateChanges = stream
        self.stateContinuation = continuation
    }

    /// Production initializer. Enforces role-specific credentials on every handshake.
    init(port: UInt16, overlayToken: String, controlToken: String) {
        self.port = port
        self.overlayToken = overlayToken
        self.controlToken = controlToken
        let (stream, continuation) = AsyncStream<(ServerState, Int)>.makeStream(
            bufferingPolicy: .bufferingNewest(64)
        )
        self.stateChanges = stream
        self.stateContinuation = continuation
    }

    deinit {
        // Cancel the NWListener and all open NWConnections before the actor is
        // deallocated. Not calling these would leave the OS-level socket open
        // until the next GC pass, and active NWConnections would retain their
        // send/receive closures (keeping the object graph alive longer than
        // expected). `stateContinuation.finish()` must come last so any
        // consumer still iterating `stateChanges` sees the stream end.
        retryTask?.cancel()
        progressTask?.cancel()
        listener?.cancel()
        for conn in connections {
            conn.stateUpdateHandler = nil
            conn.cancel()
        }
        for conn in pendingConnections {
            conn.stateUpdateHandler = nil
            conn.cancel()
        }
        for task in handshakeTimeoutTasks.values { task.cancel() }
        widgetHTTP?.stop()
        stateContinuation.finish()
    }

    // MARK: - Public API

    /// Starts or stops the server based on the given flag.
    func setEnabled(_ enabled: Bool) {
        isEnabled = enabled
        if enabled {
            startServer()
            reconcileProgressTimer()
        } else {
            stopServer()
        }
    }

    /// Installs the inbound-command handler. Called once at setup by AppDelegate.
    func setCommandHandler(_ handler: @escaping @Sendable (StreamDeckCommand) async -> CommandAck) {
        onCommand = handler
    }

    /// Starts or stops the widget HTTP server independently.
    func setWidgetHTTPEnabled(_ enabled: Bool) {
        if enabled {
            // Only start if WebSocket server is listening and HTTP isn't already running
            guard state == .listening, widgetHTTP == nil else { return }
            let resolvedPort = Preferences.resolvedWidgetPort
            widgetHTTPPort = resolvedPort
            widgetHTTP = WidgetHTTPService(port: resolvedPort, overlayToken: overlayToken)
            widgetHTTP?.start()
            Log.info("WebSocketServerService: Widget HTTP server started", category: .websocket)
        } else {
            widgetHTTP?.stop()
            widgetHTTP = nil
            widgetHTTPPort = nil
            Log.info("WebSocketServerService: Widget HTTP server stopped", category: .websocket)
        }
    }

    /// Restarts only the widget HTTP listener when its configured port changes.
    /// The WebSocket listener and connected OBS/Stream Deck clients stay intact.
    func updateWidgetPort(_ newPort: UInt16) {
        guard newPort >= AppConstants.WebSocketServer.minPort,
              newPort <= AppConstants.WebSocketServer.maxPort else { return }
        guard widgetHTTPPort != newPort else { return }

        let wasRunning = widgetHTTP != nil
        widgetHTTP?.stop()
        widgetHTTP = nil
        widgetHTTPPort = nil

        guard wasRunning, state == .listening else { return }
        widgetHTTPPort = newPort
        widgetHTTP = WidgetHTTPService(port: newPort, overlayToken: overlayToken)
        widgetHTTP?.start()
        Log.info(
            "WebSocketServerService: Widget HTTP port changed to \(newPort), listener restarted",
            category: .websocket
        )
    }

    /// Swaps the overlay credential and restarts an active listener so every
    /// client must re-authenticate. The caller persists it first.
    func updateOverlayToken(_ newToken: String) {
        guard overlayToken != newToken else { return }
        overlayToken = newToken
        restartIfListening()
    }

    /// Swaps the control credential and restarts an active listener so every
    /// client must re-authenticate. The caller persists it first.
    func updateControlToken(_ newToken: String) {
        guard controlToken != newToken else { return }
        controlToken = newToken
        restartIfListening()
    }

    private func restartIfListening() {
        guard listener != nil else { return }
        stopServer()
        startServer()
    }

    /// Changes the listening port. Restarts the server if it was already running
    /// or still starting (a port change during `.starting` would otherwise bind
    /// the old port and silently ignore the new value).
    func updatePort(_ newPort: UInt16) {
        guard newPort >= AppConstants.WebSocketServer.minPort,
              newPort <= AppConstants.WebSocketServer.maxPort else { return }
        guard port != newPort else { return }

        let needsRestart = listener != nil
        port = newPort

        if needsRestart {
            Log.info(
                "WebSocketServerService: Port changed to \(newPort) while listener active, restarting",
                category: .websocket
            )
            stopServer()
            startServer()
        }
    }

    /// Stores new track metadata and broadcasts a `now_playing` message to all clients.
    ///
    /// - Parameter isPaused: `true` when the underlying source reports the
    ///   loaded track as paused. The broadcast still goes out so overlay
    ///   clients can render a paused affordance; the progress ticker is
    ///   suspended while paused and resumed on the next non-paused update.
    func updateNowPlaying(
        track: String,
        artist: String,
        album: String,
        duration: TimeInterval,
        elapsed: TimeInterval,
        artworkURL: String? = nil,
        isPaused: Bool = false
    ) {
        let identityChanged = currentTrack != track || currentArtist != artist

        // Steady-state dedup: the source re-emits the same track every ~5s. When
        // only elapsed advanced (no track/pause/artwork change), refresh the
        // progress baseline and skip the full rebroadcast + progress-timer
        // restart. The timer is already in the correct state because isPaused is
        // unchanged; overlay clients keep ticking locally from the last frame.
        let unchanged = currentTrack == track
            && currentArtist == artist
            && currentAlbum == album
            && currentDuration == duration
            && isPlaying == !isPaused
            && (artworkURL == nil || artworkURL == currentArtworkURL)
        if unchanged {
            currentElapsed = elapsed
            lastElapsedUpdate = Date()
            reconcileProgressTimer()
            return
        }

        currentTrack = track
        currentArtist = artist
        currentAlbum = album
        currentDuration = duration
        currentElapsed = elapsed
        isPlaying = !isPaused
        lastElapsedUpdate = Date()
        if identityChanged {
            // Never let a new track inherit the previous track's artwork while
            // its own asynchronous lookup is still in flight.
            currentArtworkURL = artworkURL
        } else if let artworkURL {
            currentArtworkURL = artworkURL
        }

        broadcastNowPlaying()
        reconcileProgressTimer()
    }

    /// Applies an asynchronous artwork result only if its track is still current.
    /// Returns `false` when a late or duplicate result was ignored.
    @discardableResult
    func updateArtworkURL(_ url: String, track: String, artist: String) -> Bool {
        guard currentTrack == track, currentArtist == artist else {
            Log.debug(
                "WebSocketServerService: Ignoring stale artwork result for \(track) — \(artist)",
                category: .websocket
            )
            return false
        }
        guard currentArtworkURL != url else { return false }
        currentArtworkURL = url
        broadcastNowPlaying()
        return true
    }

    /// Toggles only playback-card visibility while leaving the authenticated
    /// WebSocket transport alive for Stream Deck commands and acknowledgements.
    @discardableResult
    func toggleOverlayVisibility() -> Bool {
        setOverlayVisibility(!isOverlayVisible)
        return isOverlayVisible
    }

    func setOverlayVisibility(_ visible: Bool) {
        guard visible != isOverlayVisible else { return }
        isOverlayVisible = visible
        writeOverlayVisibleSnapshot(visible)
        broadcastOverlayVisibility()
        if visible {
            if currentTrack == nil {
                broadcastPlaybackState()
            } else {
                broadcastNowPlaying()
            }
        }
        reconcileProgressTimer()
    }

    /// Builds the `widget_config` message from the persisted widget-appearance
    /// prefs. Shared by the broadcast-to-all and send-to-one paths so the two
    /// snapshots can never drift.
    private func widgetConfigPayload() -> [String: Any] {
        let defaults = DefaultsStore.store
        return [
            "type": "widget_config",
            "data": [
                "theme": defaults.string(forKey: AppConstants.UserDefaults.widgetTheme) ?? AppConstants.Widget.Defaults.theme,
                "layout": defaults.string(forKey: AppConstants.UserDefaults.widgetLayout) ?? AppConstants.Widget.Defaults.layout,
                "textColor": defaults.string(forKey: AppConstants.UserDefaults.widgetTextColor) ?? AppConstants.Widget.Defaults.textColor,
                "backgroundColor": defaults.string(forKey: AppConstants.UserDefaults.widgetBackgroundColor) ?? AppConstants.Widget.Defaults.backgroundColor,
                "fontFamily": defaults.string(forKey: AppConstants.UserDefaults.widgetFontFamily) ?? AppConstants.Widget.Defaults.fontFamily,
            ],
        ]
    }

    /// Broadcasts widget theme/customization config to all connected clients.
    func broadcastWidgetConfig() {
        broadcastJSON(widgetConfigPayload())
    }

    /// Broadcasts request-queue counts and hold state so a Stream Deck counter
    /// or hold key renders without polling. Values are supplied by the caller
    /// (AppDelegate) to keep this actor decoupled from the song-request services.
    ///
    /// `held` exists so the hold key can show real state instead of guessing:
    /// without it a plugin has to track its own optimistic toggle, which drifts
    /// the moment hold is changed from the tray, chat (`!hold`), or Settings.
    ///
    /// `audience` is the raw `RequestAudience` value. Same reasoning as `held`:
    /// the audience is changeable from Settings and from a key, so the key has
    /// to render what the app says rather than what it last sent.
    func broadcastQueueState(count: Int, pending: Int, held: Bool, audience: String) {
        broadcastJSON([
            "type": "queue_state",
            "data": [
                "count": count, "pending": pending, "held": held, "audience": audience,
            ],
        ])
    }

    /// Builds the `queue_upcoming` message from the cached snapshot. Shared by
    /// the broadcast-to-all and send-to-one paths, same reasoning as
    /// `widgetConfigPayload()`.
    private func queueUpcomingPayload() -> [String: Any] {
        [
            "type": "queue_upcoming",
            "data": ["items": currentQueueUpcoming.map {
                ["title": $0.title, "requesterUsername": $0.requesterUsername]
            }],
        ]
    }

    /// Caches and broadcasts the next few queued requests so the overlay's
    /// queue ticker renders without polling. Caller (AppDelegate) is
    /// responsible for capping to `AppConstants.WebSocketServer.queueTickerMaxItems`.
    /// An empty array is a valid, meaningful state: "the queue is open."
    func broadcastQueueUpcoming(items: [QueueUpcomingItem]) {
        currentQueueUpcoming = items
        broadcastJSON(queueUpcomingPayload())
    }

    private func sendQueueUpcoming(to connection: NWConnection) {
        Self.sendJSON(queueUpcomingPayload(), to: connection)
    }

    /// Broadcasts aggregate connection health for a Stream Deck status key.
    func broadcastHealth(music: Bool, twitch: Bool, discord: Bool, overlay: Bool) {
        broadcastJSON([
            "type": "health",
            "data": ["music": music, "twitch": twitch, "discord": discord, "overlay": overlay],
        ])
    }

    /// Updates the progress broadcast interval and restarts the timer if currently broadcasting.
    ///
    /// - Parameter interval: New broadcast interval in seconds.
    func updateProgressInterval(_ interval: TimeInterval) {
        currentProgressInterval = interval
        if progressTask != nil {
            startProgressTimer()
        }
    }

    /// Marks playback as fully stopped and broadcasts the state change.
    ///
    /// Called when Music.app quits, permission is revoked, or the source
    /// errors, never on a plain pause (that path keeps the track and goes
    /// through `updateNowPlaying`). Clears the cached track so a stale song
    /// can't leak into a later `now_playing` re-broadcast, and so overlay
    /// clients hide the card instead of lingering on the last track.
    func clearNowPlaying() {
        isPlaying = false
        lastElapsedUpdate = nil
        currentTrack = nil
        currentArtist = nil
        currentAlbum = nil
        currentArtworkURL = nil
        currentDuration = 0
        currentElapsed = 0

        stopProgressTimer()
        broadcastPlaybackState()
    }

    // MARK: - Server Lifecycle

    /// Brings up the `NWListener` on the configured port and wires state and
    /// connection callbacks. Network.framework callbacks fire on `networkQueue`
    /// and hop back into the actor.
    private func startServer() {
        guard listener == nil else { return }

        listenerGeneration &+= 1
        let generation = listenerGeneration

        transition(to: .starting)

        let parameters = NWParameters.tcp
        let wsOptions = NWProtocolWebSocket.Options()
        wsOptions.autoReplyPing = true
        wsOptions.maximumMessageSize = Self.maximumInboundMessageSize

        // Resolve an explicit role during the handshake. The selected
        // subprotocol is validated again when the connection becomes ready.
        let expectedOverlayToken = overlayToken
        let expectedControlToken = controlToken
        wsOptions.setClientRequestHandler(networkQueue) { subprotocols, _ in
            let role = WebSocketAuthToken.authenticationRole(
                overlayToken: expectedOverlayToken,
                controlToken: expectedControlToken,
                offeredSubprotocols: subprotocols
            )
            if let role {
                let token = role == .overlay ? expectedOverlayToken : expectedControlToken
                let selected = token.map {
                    WebSocketAuthToken.expectedSubprotocol(for: $0, role: role)
                } ?? subprotocols.first
                return NWProtocolWebSocket.Response(
                    status: .accept,
                    subprotocol: selected,
                    additionalHeaders: nil
                )
            }
            Log.info(
                "WebSocketServerService: Rejecting unauthenticated client (offered \(subprotocols.count) subprotocol(s))",
                category: .websocket
            )
            return NWProtocolWebSocket.Response(
                status: .reject,
                subprotocol: nil,
                additionalHeaders: nil
            )
        }

        parameters.defaultProtocolStack.applicationProtocols.insert(wsOptions, at: 0)

        do {
            guard let nwPort = NWEndpoint.Port(rawValue: port) else {
                Log.error("WebSocketServerService: Invalid port \(port)", category: .websocket)
                transition(to: .error)
                return
            }
            listener = try NWListener(using: parameters, on: nwPort)
        } catch {
            Log.error("WebSocketServerService: Failed to create listener: \(error)", category: .websocket)
            transition(to: .error)
            scheduleRetry()
            return
        }

        listener?.stateUpdateHandler = { [weak self] newState in
            guard let self else { return }
            Task {
                await self.handleListenerState(
                    newState,
                    generation: generation)
            }
        }

        listener?.newConnectionHandler = { [weak self] connection in
            guard let self else { return }
            Task {
                await self.handleNewConnection(
                    connection,
                    listenerGeneration: generation)
            }
        }

        listener?.start(queue: networkQueue)

        if FeatureFlags.widgetHTTPEnabled {
            let resolvedPort = Preferences.resolvedWidgetPort
            widgetHTTPPort = resolvedPort
            widgetHTTP = WidgetHTTPService(port: resolvedPort, overlayToken: overlayToken)
            widgetHTTP?.start()
        }
    }

    /// Handles `NWListener.stateUpdateHandler` transitions inside the actor.
    private func handleListenerState(
        _ newState: NWListener.State,
        generation: UInt64
    ) {
        guard generation == listenerGeneration else { return }
        switch newState {
        case .ready:
            Log.info("WebSocketServerService: Listening on port \(port)", category: .websocket)
            transition(to: .listening)
        case .failed(let error):
            Log.error("WebSocketServerService: Listener failed: \(error)", category: .websocket)
            listenerGeneration &+= 1
            listener?.stateUpdateHandler = nil
            listener?.newConnectionHandler = nil
            listener?.cancel()
            listener = nil
            widgetHTTP?.stop()
            widgetHTTP = nil
            widgetHTTPPort = nil
            stopProgressTimer()
            cancelOwnedConnections()
            transition(to: .error)
            scheduleRetry()
        case .cancelled:
            transition(to: .stopped)
        default:
            break
        }
    }

    /// Tears down the listener, cancels all open connections, and transitions
    /// the service to `.stopped`. Safe to call when no server is running.
    private func stopServer() {
        listenerGeneration &+= 1
        retryTask?.cancel()
        retryTask = nil

        widgetHTTP?.stop()
        widgetHTTP = nil
        widgetHTTPPort = nil

        stopProgressTimer()

        // Detach the old listener's handlers BEFORE cancelling. Otherwise its
        // asynchronous `.cancelled` event hops into handleListenerState and runs
        // `transition(to: .stopped)` — which, when updateOverlayToken/updateControlToken/updatePort do
        // stopServer(); startServer() back to back, can land after the new
        // listener is already `.listening` and clobber the state to `.stopped`,
        // making handleConnectionState cancel every subsequent overlay client.
        listener?.stateUpdateHandler = nil
        listener?.newConnectionHandler = nil
        listener?.cancel()
        listener = nil

        cancelOwnedConnections()

        transition(to: .stopped)
        Log.info("WebSocketServerService: Server stopped", category: .websocket)
    }

    /// Retries starting the server after a delay if still enabled.
    private func scheduleRetry() {
        guard isEnabled else { return }

        Log.info(
            "WebSocketServerService: Retrying in \(AppConstants.WebSocketServer.retryDelay)s",
            category: .websocket)
        retryTask?.cancel()
        retryTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(AppConstants.WebSocketServer.retryDelay))
            guard !Task.isCancelled else { return }
            await self?.attemptRetry()
        }
    }

    private func attemptRetry() {
        guard isEnabled, listener == nil else { return }
        startServer()
    }

    // MARK: - Connection Handling

    /// Wires the per-connection state callback. On `.ready`, records the
    /// connection and sends a welcome + current state + widget config snapshot.
    /// On failure or cancellation, removes the connection from the active set.
    private func handleNewConnection(
        _ connection: NWConnection,
        listenerGeneration generation: UInt64
    ) {
        guard generation == listenerGeneration,
              isEnabled,
              listener != nil,
              Self.shouldAcceptNewConnection(
                  activeCount: connections.count,
                  pendingCount: pendingConnections.count
              ) else {
            connection.cancel()
            return
        }

        pendingConnections.append(connection)
        let connectionID = ObjectIdentifier(connection)
        handshakeTimeoutTasks[connectionID] = Task { [weak self] in
            do {
                try await Task.sleep(for: Self.handshakeTimeout)
            } catch {
                return
            }
            await self?.expirePendingConnection(
                connection,
                listenerGeneration: generation
            )
        }
        connection.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            Task {
                await self.handleConnectionState(
                    connection,
                    state: state,
                    listenerGeneration: generation
                )
            }
        }
        connection.start(queue: networkQueue)
    }

    private func handleConnectionState(
        _ connection: NWConnection,
        state: NWConnection.State,
        listenerGeneration generation: UInt64
    ) {
        guard generation == listenerGeneration else {
            connection.cancel()
            return
        }
        switch state {
        case .ready:
            guard !connections.contains(where: { $0 === connection }) else { return }
            guard promotePendingConnection(connection) else {
                removeConnection(connection)
                connection.cancel()
                return
            }
            let metadata = connection.metadata(definition: NWProtocolWebSocket.definition)
                as? NWProtocolWebSocket.Metadata
            guard let role = WebSocketAuthToken.role(
                forSelectedSubprotocol: metadata?.selectedSubprotocol,
                overlayToken: overlayToken,
                controlToken: controlToken
            ) else {
                Log.warn(
                    "WebSocketServerService: Cancelling client with unvalidated selected subprotocol",
                    category: .websocket
                )
                removeConnection(connection)
                connection.cancel()
                return
            }
            let isLoopback = WebSocketAuthToken.isLoopbackEndpoint(connection.endpoint)
            guard Self.allowsConnection(role: role, isLoopback: isLoopback) else {
                Log.warn(
                    "WebSocketServerService: Refusing non-loopback control connection",
                    category: .websocket
                )
                removeConnection(connection)
                connection.cancel()
                return
            }
            // Ignore a late .ready that lands after stopServer(); re-adding would
            // inflate the count. `state` the param is NWConnection.State; qualify
            // with self to read the server's lifecycle state.
            guard self.state == .listening else {
                removeConnection(connection)
                connection.cancel()
                return
            }
            connections.append(connection)
            connectionRoles[ObjectIdentifier(connection)] = role
            let count = connections.count
            writeConnectionCountSnapshot(count)
            Log.info("WebSocketServerService: Client connected (\(count) total)", category: .websocket)
            notifyStateChange()
            sendWelcome(to: connection)
            sendWidgetConfig(to: connection)
            sendOverlayVisibility(to: connection)
            sendQueueUpcoming(to: connection)
            sendCurrentState(to: connection, role: role)
            Self.receiveMessage(
                from: connection,
                role: role,
                isLoopback: isLoopback,
                onCommand: onCommand
            )
            reconcileProgressTimer()
        case .failed(let error):
            Log.debug("WebSocketServerService: Client failed: \(error)", category: .websocket)
            // Clear actor ownership and the callback before cancelling so an
            // abruptly-dropped peer cannot leave a connection/handler cycle.
            removeConnection(connection)
            connection.cancel()
        case .cancelled:
            removeConnection(connection)
        default:
            break
        }
    }

    /// Drops `connection` from the active set and broadcasts the new count.
    private func removeConnection(_ connection: NWConnection) {
        let previousActiveCount = connections.count
        handshakeTimeoutTasks.removeValue(forKey: ObjectIdentifier(connection))?.cancel()
        pendingConnections.removeAll { $0 === connection }
        connections.removeAll { $0 === connection }
        connectionRoles.removeValue(forKey: ObjectIdentifier(connection))
        connection.stateUpdateHandler = nil
        let count = connections.count
        guard count != previousActiveCount else { return }
        writeConnectionCountSnapshot(count)

        Log.debug("WebSocketServerService: Client disconnected (\(count) remaining)", category: .websocket)
        notifyStateChange()
        reconcileProgressTimer()
    }

    private func cancelOwnedConnections() {
        let ownedConnections = connections + pendingConnections
        let timeoutTasks = Array(handshakeTimeoutTasks.values)
        connections.removeAll()
        connectionRoles.removeAll()
        pendingConnections.removeAll()
        handshakeTimeoutTasks.removeAll()
        writeConnectionCountSnapshot(0)

        for task in timeoutTasks { task.cancel() }
        for connection in ownedConnections {
            connection.stateUpdateHandler = nil
            connection.cancel()
        }
    }

    private func promotePendingConnection(_ connection: NWConnection) -> Bool {
        guard let index = pendingConnections.firstIndex(where: { $0 === connection }) else {
            return false
        }
        pendingConnections.remove(at: index)
        handshakeTimeoutTasks.removeValue(forKey: ObjectIdentifier(connection))?.cancel()
        return true
    }

    private func expirePendingConnection(
        _ connection: NWConnection,
        listenerGeneration generation: UInt64
    ) {
        guard generation == listenerGeneration,
              pendingConnections.contains(where: { $0 === connection }) else { return }
        removeConnection(connection)
        connection.cancel()
    }

    nonisolated static func shouldAcceptNewConnection(
        activeCount: Int,
        pendingCount: Int
    ) -> Bool {
        activeCount >= 0
            && pendingCount >= 0
            && pendingCount < maximumPendingConnectionCount
            && activeCount < maximumConnectionCount - pendingCount
    }

    /// Pure authorization seams shared by the ready-state gate and tests.
    nonisolated static func allowsConnection(
        role: WebSocketAuthToken.Role,
        isLoopback: Bool
    ) -> Bool {
        role == .overlay || isLoopback
    }

    nonisolated static func allowsCommands(role: WebSocketAuthToken.Role, isLoopback: Bool) -> Bool {
        role == .control && isLoopback
    }

    /// Keeps the connection alive by continuously consuming inbound messages.
    /// Nonisolated. Does not touch actor state.
    ///
    /// Stops re-arming (and cancels the connection) on a WebSocket close frame
    /// or a transport error. A graceful close arrives as a `.close` opcode with
    /// `error == nil`, so keying only on `error` would re-arm `receiveMessage`
    /// forever and keep the dead `NWConnection` retained by the loop.
    ///
    /// Inbound text frames are parsed as Stream Deck control commands
    /// (``StreamDeckControl/parse(_:)``). A valid command runs through
    /// `onCommand` and the ack goes back on the same connection; a rejected
    /// command still acks; anything else is ignored. Overlay credentials never
    /// authorize commands, and control credentials remain loopback-only.
    private static func receiveMessage(
        from connection: NWConnection,
        role: WebSocketAuthToken.Role,
        isLoopback: Bool,
        onCommand: (@Sendable (StreamDeckCommand) async -> CommandAck)?
    ) {
        connection.receiveMessage { data, context, _, error in
            if error != nil { return }

            if let metadata = context?.protocolMetadata(definition: NWProtocolWebSocket.definition)
                as? NWProtocolWebSocket.Metadata, metadata.opcode == .close {
                connection.cancel()
                return
            }

            if let data, !data.isEmpty, let text = String(data: data, encoding: .utf8) {
                switch StreamDeckControl.parse(text) {
                case .command(let command):
                    if !allowsCommands(role: role, isLoopback: isLoopback) {
                        sendJSON(
                            CommandAck.failure(command.action.rawValue, "unauthorized").jsonObject,
                            to: connection
                        )
                    } else if let onCommand {
                        Task {
                            let ack = await onCommand(command)
                            sendJSON(ack.jsonObject, to: connection)
                        }
                    }
                case .reject(let ack):
                    sendJSON(ack.jsonObject, to: connection)
                case .ignore:
                    break
                }
            }

            receiveMessage(
                from: connection,
                role: role,
                isLoopback: isLoopback,
                onCommand: onCommand
            )
        }
    }

    // MARK: - Message Broadcasting

    /// Sends the initial `welcome` envelope (server identity + version) to a
    /// freshly-accepted connection.
    private func sendWelcome(to connection: NWConnection) {
        Self.sendJSON(
            ["type": "welcome", "server": "WolfWave", "version": AppConstants.AppInfo.shortVersion],
            to: connection
        )
    }

    /// Sends the current widget theme/layout config to a newly connected client.
    private func sendWidgetConfig(to connection: NWConnection) {
        Self.sendJSON(widgetConfigPayload(), to: connection)
    }

    private func overlayVisibilityPayload() -> [String: Any] {
        ["type": "overlay_visibility", "data": ["visible": isOverlayVisible]]
    }

    private func sendOverlayVisibility(to connection: NWConnection) {
        Self.sendJSON(overlayVisibilityPayload(), to: connection)
    }

    private func broadcastOverlayVisibility() {
        broadcastJSON(overlayVisibilityPayload())
    }

    /// Builds the `now_playing` message from the stored track/artist/album plus
    /// timing and artwork. Returns `nil` when no complete track is stored.
    ///
    /// `elapsed` is parameterized because the replay path interpolates an
    /// estimate (`estimatedElapsed()`) while the live broadcast uses the raw
    /// `currentElapsed`. Safe on this actor: called synchronously with no
    /// suspension between the property reads.
    private func nowPlayingPayload(elapsed: TimeInterval) -> [String: Any]? {
        guard let track = currentTrack,
              let artist = currentArtist,
              let album = currentAlbum else { return nil }
        return [
            "type": "now_playing",
            "data": [
                "track": track, "artist": artist, "album": album,
                "duration": currentDuration, "elapsed": elapsed,
                "isPlaying": isPlaying, "artworkURL": currentArtworkURL ?? "",
            ],
        ]
    }

    /// Sends the full current playback snapshot to a newly connected client.
    ///
    /// A hidden overlay withholds the replay from overlay clients so a browser
    /// source cannot paint a card the streamer has turned off. Control clients
    /// are exempt: hiding the overlay is not a reason for a Stream Deck to stop
    /// knowing what is playing.
    private func sendCurrentState(to connection: NWConnection, role: WebSocketAuthToken.Role) {
        guard isOverlayVisible || role == .control else { return }
        guard let message = nowPlayingPayload(elapsed: estimatedElapsed()) else {
            Log.debug(
                "WebSocketServerService: No playback state to replay on connect",
                category: .websocket
            )
            Self.sendJSON(
                [
                    "type": "playback_state",
                    "data": ["isPlaying": false, "track": "", "artist": "", "album": ""],
                ],
                to: connection
            )
            return
        }
        Log.debug(
            "WebSocketServerService: Replaying last-known state to new client (track=\(currentTrack ?? ""))",
            category: .websocket
        )
        Self.sendJSON(message, to: connection)
    }

    /// Sends a `now_playing` snapshot (track/artist/album/timing/artwork) to
    /// every connected client. No-op when no track has been stored yet.
    ///
    /// While the overlay is hidden this narrows to control clients rather than
    /// stopping: the browser source must not paint a hidden card, but a Stream
    /// Deck that went silent on every track change for the whole time the
    /// overlay was off would just be showing the streamer stale information.
    private func broadcastNowPlaying() {
        guard let message = nowPlayingPayload(elapsed: currentElapsed) else { return }
        if isOverlayVisible {
            broadcastJSON(message)
        } else {
            broadcastJSON(message, to: controlConnections())
        }
    }

    /// The connected clients holding the control credential.
    private func controlConnections() -> [NWConnection] {
        connections.filter { connectionRoles[ObjectIdentifier($0)] == .control }
    }

    /// Count of clients rendering the overlay, i.e. everything except Stream Deck.
    private func overlayConnectionCount() -> Int {
        connections.count { connectionRoles[ObjectIdentifier($0)] != .control }
    }

    /// Sends a lightweight `playback_state` (play/pause) update to every
    /// connected client. Used when only the playing flag changes.
    private func broadcastPlaybackState() {
        broadcastJSON([
            "type": "playback_state",
            "data": [
                "isPlaying": isPlaying,
                "track": currentTrack ?? "",
                "artist": currentArtist ?? "",
                "album": currentAlbum ?? "",
            ],
        ])
    }

    /// Sends a `progress` tick (elapsed/duration) to every connected client
    /// while playback is active. Driven by the periodic progress task.
    private func broadcastProgress() {
        // No clients = nothing to do. Skipping the serialization when no overlay
        // is connected (the common idle case) avoids per-tick work.
        guard Self.shouldRunProgressTimer(
            isEnabled: isEnabled,
            isOverlayVisible: isOverlayVisible,
            isPlaying: isPlaying,
            duration: currentDuration,
            connectionCount: overlayConnectionCount()
        ) else { return }
        broadcastJSON([
            "type": "progress",
            "data": [
                "elapsed": estimatedElapsed(),
                "duration": currentDuration,
                "isPlaying": isPlaying,
            ],
        ])
    }

    /// Interpolates elapsed time using the wall clock.
    private func estimatedElapsed() -> TimeInterval {
        guard let lastUpdate = lastElapsedUpdate, isPlaying else { return currentElapsed }
        return min(currentElapsed + Date().timeIntervalSince(lastUpdate), currentDuration)
    }

    // MARK: - Progress Timer

    /// Pure policy shared by every progress-loop entry point and regression tests.
    nonisolated static func shouldRunProgressTimer(
        isEnabled: Bool,
        isOverlayVisible: Bool,
        isPlaying: Bool,
        duration: TimeInterval,
        connectionCount: Int
    ) -> Bool {
        isEnabled
            && isOverlayVisible
            && isPlaying
            && duration.isFinite
            && duration > 0
            && connectionCount > 0
    }

    /// Starts or stops the periodic task so disabled, hidden, paused, and
    /// client-free states have no timer wakeups at all.
    private func reconcileProgressTimer() {
        // Only overlay clients consume `progress`; a lone Stream Deck ignores
        // the frame, so its presence must not keep the timer awake.
        let shouldRun = Self.shouldRunProgressTimer(
            isEnabled: isEnabled,
            isOverlayVisible: isOverlayVisible,
            isPlaying: isPlaying,
            duration: currentDuration,
            connectionCount: overlayConnectionCount())
        if shouldRun {
            if progressTask == nil { startProgressTimer() }
        } else {
            stopProgressTimer()
        }
    }

    /// Starts (or restarts) the periodic progress broadcast loop using the
    /// current interval. Cancels any running loop before scheduling.
    private func startProgressTimer() {
        stopProgressTimer()
        guard Self.shouldRunProgressTimer(
            isEnabled: isEnabled,
            isOverlayVisible: isOverlayVisible,
            isPlaying: isPlaying,
            duration: currentDuration,
            connectionCount: overlayConnectionCount()
        ) else { return }

        let interval = currentProgressInterval
        progressTask = Task { [weak self] in
            while !Task.isCancelled {
                // Progress ticks tolerate ~10% jitter; the tolerance lets macOS
                // coalesce the wakeup with other timers.
                try? await Task.sleep(for: .seconds(interval), tolerance: .seconds(interval * 0.1))
                if Task.isCancelled { return }
                await self?.broadcastProgress()
            }
        }
    }

    /// Cancels and clears the progress broadcast task if one is active.
    private func stopProgressTimer() {
        progressTask?.cancel()
        progressTask = nil
    }

    /// Exposed internally for deterministic lifecycle tests.
    var isProgressTimerActive: Bool { progressTask != nil }

    /// Exposed internally for artwork identity regression tests.
    var artworkState: (track: String?, artist: String?, url: String?) {
        (currentTrack, currentArtist, currentArtworkURL)
    }

    // MARK: - JSON Helpers

    /// Serializes `dict` to JSON and sends it as a single WebSocket text frame.
    /// Nonisolated. Does not touch actor state.
    private static func sendJSON(_ dict: [String: Any], to connection: NWConnection) {
        // Guards a malformed leaf from raising an ObjC exception inside
        // `data(withJSONObject:)` (uncatchable by `try?`).
        guard let jsonData = JSONObjectSerialization.data(from: dict) else { return }
        sendJSONData(jsonData, to: connection)
    }

    /// Sends already-encoded JSON so fan-out does not serialize or copy the
    /// identical payload once per connection.
    private static func sendJSONData(_ jsonData: Data, to connection: NWConnection) {
        MetricsService.shared.recordWebSocketMessage(byteCount: jsonData.count)

        let metadata = NWProtocolWebSocket.Metadata(opcode: .text)
        let context = NWConnection.ContentContext(identifier: "websocket", metadata: [metadata])

        connection.send(
            content: jsonData,
            contentContext: context,
            isComplete: true,
            completion: .contentProcessed { error in
                if let error { Log.debug("WebSocketServerService: Send failed: \(error)", category: .websocket) }
            }
        )
    }

    /// Fan-outs a JSON payload to every active connection in a single pass.
    ///
    /// - Parameter dict: Top-level JSON object to serialize and broadcast.
    private func broadcastJSON(_ dict: [String: Any]) {
        broadcastJSON(dict, to: connections)
    }

    /// Fan-outs to a subset of clients, encoding once for the whole set.
    ///
    /// - Parameters:
    ///   - dict: Top-level JSON object to serialize and send.
    ///   - targets: Connections to send to. Empty is a no-op.
    private func broadcastJSON(_ dict: [String: Any], to targets: [NWConnection]) {
        guard !targets.isEmpty else { return }
        guard let jsonData = JSONObjectSerialization.data(from: dict) else { return }
        for connection in targets { Self.sendJSONData(jsonData, to: connection) }
    }

    // MARK: - State Notification

    /// Updates the snapshot, yields onto `stateChanges`, and posts a
    /// `NotificationCenter` event on the main actor.
    private func transition(to newState: ServerState) {
        writeStateSnapshot(newState)
        notifyStateChange()
    }

    private func notifyStateChange() {
        let currentState = state
        let count = connectionCount
        stateContinuation.yield((currentState, count))

        Task { @MainActor in
            NotificationCenter.default.postWebSocketServerState(currentState.rawValue, clients: count)
        }
    }
}
