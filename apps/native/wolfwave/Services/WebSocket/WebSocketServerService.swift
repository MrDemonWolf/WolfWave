//
//  WebSocketServerService.swift
//  wolfwave
//
//  Created by MrDemonWolf, Inc. on 2/13/26.
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
/// - The listener binds to `.ipv4(.loopback)` so connections must originate on the
///   same Mac. Localhost is **not** treated as an authentication boundary on its own:
///   any browser tab or sibling process on the host could still reach this port.
/// - Every accepted connection must present the `wolfwave.token.<hex>` WebSocket
///   subprotocol (`Sec-WebSocket-Protocol`) on the handshake. The token is minted on
///   first launch by `WebSocketAuthToken.currentOrCreate()`, persisted in the macOS
///   Keychain via `KeychainService.saveToken(_:)`, and never logged in full —
///   redacted log lines only carry the first 4 characters.
/// - Connections without the subprotocol, or with a mismatched value, are rejected
///   by the `NWProtocolWebSocket` client-request handler before the connection
///   transitions to `.ready`; the snapshot count is not bumped and no playback
///   frames are sent.
/// - Rotating the token via `updateAuthToken(_:)` restarts the listener so every
///   already-authorized client is dropped.
/// - The init that omits `authToken` exists for unit tests that exercise the pure
///   lifecycle / state machine without standing up Keychain.
actor WebSocketServerService {

    // MARK: - Types

    enum ServerState: String, Sendable {
        case stopped, starting, listening, error
    }

    // MARK: - Nonisolated Snapshot

    /// Protects the snapshot variables read from outside the actor.
    private nonisolated let snapshotLock = NSLock()
    nonisolated(unsafe) private var _stateSnapshot: ServerState = .stopped
    nonisolated(unsafe) private var _connectionCountSnapshot: Int = 0

    /// Latest server state, safe to read synchronously from any thread.
    nonisolated var state: ServerState {
        snapshotLock.withLock { _stateSnapshot }
    }

    /// Latest connected-client count, safe to read synchronously from any thread.
    nonisolated var connectionCount: Int {
        snapshotLock.withLock { _connectionCountSnapshot }
    }

    private func writeStateSnapshot(_ newState: ServerState) {
        snapshotLock.withLock { _stateSnapshot = newState }
    }

    private func writeConnectionCountSnapshot(_ count: Int) {
        snapshotLock.withLock { _connectionCountSnapshot = count }
    }

    // MARK: - State Change Stream

    /// Replaces the legacy `onStateChange` callback. Consumers iterate
    /// `for await (state, clientCount) in service.stateChanges`.
    nonisolated let stateChanges: AsyncStream<(ServerState, Int)>
    private nonisolated let stateContinuation: AsyncStream<(ServerState, Int)>.Continuation

    /// Number of currently-connected overlay clients. Safe to call from any
    /// thread. Used by the tray menu's "Stream Widgets" status subtitle.
    nonisolated var connectedClientCount: Int { connectionCount }

    // MARK: - Properties

    private var port: UInt16
    /// Token a client must echo back as the `wolfwave.token.<hex>` subprotocol on
    /// the WebSocket handshake. `nil` disables auth — used only by lifecycle tests
    /// that construct the service via `init(port:)`.
    private var authToken: String?
    private var listener: NWListener?
    private var connections: [NWConnection] = []
    /// Dispatch queue used only for Network.framework callbacks. All state is actor-confined.
    private nonisolated let networkQueue = DispatchQueue(
        label: AppConstants.DispatchQueues.websocketServer,
        qos: .utility
    )
    private var isEnabled = false
    private var widgetHTTP: WidgetHTTPService?
    private var retryTask: Task<Void, Never>?

    // MARK: - Playback State

    private var currentTrack: String?
    private var currentArtist: String?
    private var currentAlbum: String?
    private var currentDuration: TimeInterval = 0
    private var currentElapsed: TimeInterval = 0
    private var isPlaying = false
    private var currentArtworkURL: String?
    private var lastElapsedUpdate: Date?
    private var progressTask: Task<Void, Never>?
    private var currentProgressInterval: TimeInterval = AppConstants.WebSocketServer.progressBroadcastInterval

    // MARK: - Init

    init(port: UInt16 = AppConstants.WebSocketServer.defaultPort) {
        self.port = port
        self.authToken = nil
        let (stream, continuation) = AsyncStream<(ServerState, Int)>.makeStream(
            bufferingPolicy: .bufferingNewest(64)
        )
        self.stateChanges = stream
        self.stateContinuation = continuation
    }

    /// Production initializer — enforces the supplied token on every handshake.
    init(port: UInt16, authToken: String) {
        self.port = port
        self.authToken = authToken
        let (stream, continuation) = AsyncStream<(ServerState, Int)>.makeStream(
            bufferingPolicy: .bufferingNewest(64)
        )
        self.stateChanges = stream
        self.stateContinuation = continuation
    }

    deinit {
        stateContinuation.finish()
    }

    // MARK: - Public API

    /// Starts or stops the server based on the given flag.
    func setEnabled(_ enabled: Bool) {
        isEnabled = enabled
        if enabled {
            startServer()
        } else {
            stopServer()
        }
    }

    /// Starts or stops the widget HTTP server independently.
    func setWidgetHTTPEnabled(_ enabled: Bool) {
        if enabled {
            // Only start if WebSocket server is listening and HTTP isn't already running
            guard state == .listening, widgetHTTP == nil else { return }
            let storedWidgetPort = UserDefaults.standard.integer(forKey: AppConstants.UserDefaults.widgetPort)
            let widgetPort: UInt16 = storedWidgetPort > 0
                ? (UInt16(exactly: storedWidgetPort) ?? AppConstants.WebSocketServer.widgetDefaultPort)
                : AppConstants.WebSocketServer.widgetDefaultPort
            widgetHTTP = WidgetHTTPService(port: widgetPort, authToken: authToken)
            widgetHTTP?.start()
            Log.info("WebSocketServerService: Widget HTTP server started", category: "WebSocket")
        } else {
            widgetHTTP?.stop()
            widgetHTTP = nil
            Log.info("WebSocketServerService: Widget HTTP server stopped", category: "WebSocket")
        }
    }

    /// Swaps the auth token. Restarts the listener if it was running so every
    /// already-connected client is dropped and forced to re-handshake with the
    /// new credential. Caller is responsible for persisting the token to
    /// Keychain before invoking this.
    func updateAuthToken(_ newToken: String) {
        authToken = newToken
        guard listener != nil else { return }
        stopServer()
        startServer()
    }

    /// Changes the listening port. Restarts the server if it was already running.
    func updatePort(_ newPort: UInt16) {
        guard newPort >= AppConstants.WebSocketServer.minPort,
              newPort <= AppConstants.WebSocketServer.maxPort else { return }

        let wasListening = state == .listening
        port = newPort

        if wasListening {
            stopServer()
            startServer()
        }
    }

    /// Stores new track metadata and broadcasts a `now_playing` message to all clients.
    func updateNowPlaying(
        track: String,
        artist: String,
        album: String,
        duration: TimeInterval,
        elapsed: TimeInterval,
        artworkURL: String? = nil
    ) {
        currentTrack = track
        currentArtist = artist
        currentAlbum = album
        currentDuration = duration
        currentElapsed = elapsed
        isPlaying = true
        lastElapsedUpdate = Date()
        if let artworkURL { currentArtworkURL = artworkURL }

        broadcastNowPlaying()
        startProgressTimer()
    }

    /// Updates the artwork URL and re-broadcasts the current track to all clients.
    func updateArtworkURL(_ url: String) {
        currentArtworkURL = url
        broadcastNowPlaying()
    }

    /// Broadcasts widget theme/customization config to all connected clients.
    func broadcastWidgetConfig() {
        let defaults = UserDefaults.standard
        let config: [String: Any] = [
            "type": "widget_config",
            "data": [
                "theme": defaults.string(forKey: AppConstants.UserDefaults.widgetTheme) ?? "Default",
                "layout": defaults.string(forKey: AppConstants.UserDefaults.widgetLayout) ?? "Horizontal",
                "textColor": defaults.string(forKey: AppConstants.UserDefaults.widgetTextColor) ?? "#FFFFFF",
                "backgroundColor": defaults.string(forKey: AppConstants.UserDefaults.widgetBackgroundColor) ?? "#1A1A2E",
                "fontFamily": defaults.string(forKey: AppConstants.UserDefaults.widgetFontFamily) ?? "System",
            ],
        ]
        broadcastJSON(config)
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

    /// Marks playback as stopped and broadcasts the state change.
    func clearNowPlaying() {
        isPlaying = false
        lastElapsedUpdate = nil

        stopProgressTimer()
        broadcastPlaybackState()
    }

    // MARK: - Server Lifecycle

    /// Brings up the `NWListener` on the configured port and wires state and
    /// connection callbacks. Network.framework callbacks fire on `networkQueue`
    /// and hop back into the actor.
    private func startServer() {
        guard listener == nil else { return }

        transition(to: .starting)

        let parameters = NWParameters.tcp
        let wsOptions = NWProtocolWebSocket.Options()
        wsOptions.autoReplyPing = true

        // Gate the handshake on the auth token. Network.framework invokes this
        // closure on `networkQueue` for every inbound upgrade request, *before*
        // the connection transitions to `.ready`. Rejected clients never reach
        // `handleNewConnection`, so they can't pollute the active connection set.
        let expectedToken = authToken
        wsOptions.setClientRequestHandler(networkQueue) { subprotocols, _ in
            let accept = WebSocketAuthToken.shouldAccept(
                expectedToken: expectedToken,
                offeredSubprotocols: subprotocols
            )
            if accept {
                let selected: String? = expectedToken.map(WebSocketAuthToken.expectedSubprotocol(for:))
                    ?? subprotocols.first
                return NWProtocolWebSocket.Response(
                    status: .accept,
                    subprotocol: selected,
                    additionalHeaders: nil
                )
            }
            Log.info(
                "WebSocketServerService: Rejecting unauthenticated client (offered \(subprotocols.count) subprotocol(s))",
                category: "WebSocket"
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
                Log.error("WebSocketServerService: Invalid port \(port)", category: "WebSocket")
                transition(to: .error)
                return
            }
            parameters.requiredLocalEndpoint = NWEndpoint.hostPort(host: .ipv4(.loopback), port: nwPort)
            listener = try NWListener(using: parameters)
        } catch {
            Log.error("WebSocketServerService: Failed to create listener: \(error)", category: "WebSocket")
            transition(to: .error)
            scheduleRetry()
            return
        }

        listener?.stateUpdateHandler = { [weak self] newState in
            guard let self else { return }
            Task { await self.handleListenerState(newState) }
        }

        listener?.newConnectionHandler = { [weak self] connection in
            guard let self else { return }
            Task { await self.handleNewConnection(connection) }
        }

        listener?.start(queue: networkQueue)

        let widgetHTTPEnabled = UserDefaults.standard.object(forKey: AppConstants.UserDefaults.widgetHTTPEnabled) as? Bool ?? false
        if widgetHTTPEnabled {
            let storedWidgetPort = UserDefaults.standard.integer(forKey: AppConstants.UserDefaults.widgetPort)
            let widgetPort: UInt16 = storedWidgetPort > 0
                ? (UInt16(exactly: storedWidgetPort) ?? AppConstants.WebSocketServer.widgetDefaultPort)
                : AppConstants.WebSocketServer.widgetDefaultPort
            widgetHTTP = WidgetHTTPService(port: widgetPort, authToken: authToken)
            widgetHTTP?.start()
        }
    }

    /// Handles `NWListener.stateUpdateHandler` transitions inside the actor.
    private func handleListenerState(_ newState: NWListener.State) {
        switch newState {
        case .ready:
            Log.info("WebSocketServerService: Listening on port \(port)", category: "WebSocket")
            transition(to: .listening)
        case .failed(let error):
            Log.error("WebSocketServerService: Listener failed: \(error)", category: "WebSocket")
            listener = nil
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
        retryTask?.cancel()
        retryTask = nil

        widgetHTTP?.stop()
        widgetHTTP = nil

        stopProgressTimer()

        listener?.cancel()
        listener = nil

        let conns = connections
        connections.removeAll()
        writeConnectionCountSnapshot(0)

        for conn in conns { conn.cancel() }

        transition(to: .stopped)
        Log.info("WebSocketServerService: Server stopped", category: "WebSocket")
    }

    /// Retries starting the server after a delay if still enabled.
    private func scheduleRetry() {
        guard isEnabled else { return }

        Log.info("WebSocketServerService: Retrying in \(AppConstants.WebSocketServer.retryDelay)s", category: "WebSocket")
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
    private func handleNewConnection(_ connection: NWConnection) {
        connection.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            Task { await self.handleConnectionState(connection, state: state) }
        }
        connection.start(queue: networkQueue)
    }

    private func handleConnectionState(_ connection: NWConnection, state: NWConnection.State) {
        switch state {
        case .ready:
            connections.append(connection)
            let count = connections.count
            writeConnectionCountSnapshot(count)
            Log.info("WebSocketServerService: Client connected (\(count) total)", category: "WebSocket")
            notifyStateChange()
            sendWelcome(to: connection)
            sendCurrentState(to: connection)
            sendWidgetConfig(to: connection)
            Self.receiveMessage(from: connection)
        case .failed(let error):
            Log.debug("WebSocketServerService: Client failed: \(error)", category: "WebSocket")
            removeConnection(connection)
        case .cancelled:
            removeConnection(connection)
        default:
            break
        }
    }

    /// Drops `connection` from the active set and broadcasts the new count.
    private func removeConnection(_ connection: NWConnection) {
        connections.removeAll { $0 === connection }
        let count = connections.count
        writeConnectionCountSnapshot(count)

        Log.debug("WebSocketServerService: Client disconnected (\(count) remaining)", category: "WebSocket")
        notifyStateChange()
    }

    /// Keeps the connection alive by continuously consuming inbound messages.
    /// Nonisolated — does not touch actor state.
    private static func receiveMessage(from connection: NWConnection) {
        connection.receiveMessage { _, _, _, error in
            if error != nil { return }
            receiveMessage(from: connection)
        }
    }

    // MARK: - Message Broadcasting

    /// Sends the initial `welcome` envelope (server identity + version) to a
    /// freshly-accepted connection.
    private func sendWelcome(to connection: NWConnection) {
        let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown"
        Self.sendJSON(["type": "welcome", "server": "WolfWave", "version": appVersion], to: connection)
    }

    /// Sends the current widget theme/layout config to a newly connected client.
    private func sendWidgetConfig(to connection: NWConnection) {
        let defaults = UserDefaults.standard
        let config: [String: Any] = [
            "type": "widget_config",
            "data": [
                "theme": defaults.string(forKey: AppConstants.UserDefaults.widgetTheme) ?? "Default",
                "layout": defaults.string(forKey: AppConstants.UserDefaults.widgetLayout) ?? "Horizontal",
                "textColor": defaults.string(forKey: AppConstants.UserDefaults.widgetTextColor) ?? "#FFFFFF",
                "backgroundColor": defaults.string(forKey: AppConstants.UserDefaults.widgetBackgroundColor) ?? "#1A1A2E",
                "fontFamily": defaults.string(forKey: AppConstants.UserDefaults.widgetFontFamily) ?? "System",
            ],
        ]
        Self.sendJSON(config, to: connection)
    }

    /// Sends the full current playback snapshot to a newly connected client.
    private func sendCurrentState(to connection: NWConnection) {
        let track = currentTrack
        let artist = currentArtist
        let album = currentAlbum
        let duration = currentDuration
        let elapsed = estimatedElapsed()
        let playing = isPlaying
        let artwork = currentArtworkURL

        guard let track, let artist, let album else { return }

        let message: [String: Any] = [
            "type": "now_playing",
            "data": [
                "track": track, "artist": artist, "album": album,
                "duration": duration, "elapsed": elapsed,
                "isPlaying": playing, "artworkURL": artwork ?? "",
            ],
        ]
        Self.sendJSON(message, to: connection)
    }

    /// Sends a `now_playing` snapshot (track/artist/album/timing/artwork) to
    /// every connected client. No-op when no track has been stored yet.
    private func broadcastNowPlaying() {
        guard let track = currentTrack,
              let artist = currentArtist,
              let album = currentAlbum else { return }

        broadcastJSON([
            "type": "now_playing",
            "data": [
                "track": track, "artist": artist, "album": album,
                "duration": currentDuration, "elapsed": currentElapsed,
                "isPlaying": isPlaying, "artworkURL": currentArtworkURL ?? "",
            ],
        ])
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
        guard isPlaying else { return }
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

    /// Starts (or restarts) the periodic progress broadcast loop using the
    /// current interval. Cancels any running loop before scheduling.
    private func startProgressTimer() {
        stopProgressTimer()

        let interval = currentProgressInterval
        progressTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(interval))
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

    // MARK: - JSON Helpers

    /// Serializes `dict` to JSON and sends it as a single WebSocket text frame.
    /// Nonisolated — does not touch actor state.
    private static func sendJSON(_ dict: [String: Any], to connection: NWConnection) {
        guard let jsonData = try? JSONSerialization.data(withJSONObject: dict),
              let jsonString = String(data: jsonData, encoding: .utf8) else { return }

        MetricsService.shared.recordWebSocketMessage(byteCount: jsonData.count)

        let metadata = NWProtocolWebSocket.Metadata(opcode: .text)
        let context = NWConnection.ContentContext(identifier: "websocket", metadata: [metadata])

        connection.send(
            content: jsonString.data(using: .utf8),
            contentContext: context,
            isComplete: true,
            completion: .contentProcessed { error in
                if let error { Log.debug("WebSocketServerService: Send failed: \(error)", category: "WebSocket") }
            }
        )
    }

    /// Fan-outs a JSON payload to every active connection in a single pass.
    ///
    /// - Parameter dict: Top-level JSON object to serialize and broadcast.
    private func broadcastJSON(_ dict: [String: Any]) {
        let conns = connections
        for connection in conns { Self.sendJSON(dict, to: connection) }
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
            NotificationCenter.default.post(
                name: NSNotification.Name(AppConstants.Notifications.websocketServerStateChanged),
                object: nil,
                userInfo: ["state": currentState.rawValue, "clients": count]
            )
        }
    }
}
