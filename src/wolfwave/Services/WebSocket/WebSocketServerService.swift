//
//  WebSocketServerService.swift
//  wolfwave
//
//  Created by MrDemonWolf, Inc. on 2/13/26.
//

import Foundation
import Network

// MARK: - WebSocket Server Service

/// Local WebSocket server that broadcasts now-playing data to stream overlay clients.
///
/// Uses Network.framework `NWListener` to accept WebSocket connections on a configurable
/// local port. Connected clients (e.g., OBS browser sources) receive JSON messages for
/// track changes, playback state, and progress updates.
///
/// Thread Safety:
/// - All Network.framework I/O runs on a dedicated serial dispatch queue (`serverQueue`).
/// - Public methods are safe to call from any thread.
/// - `NSLock` instances protect shared state accessed across threads.
///
/// Reconnection:
/// - On listener failure, retries after a delay if still enabled.
final class WebSocketServerService: @unchecked Sendable {

    // MARK: - Types

    /// Server lifecycle states.
    enum ServerState: String, Sendable {
        case stopped
        case starting
        case listening
        case error
    }

    // MARK: - Properties

    /// Current server state.
    private(set) var state: ServerState = .stopped

    /// Callback invoked on the main thread when server state or client count changes.
    var onStateChange: ((ServerState, Int) -> Void)?

    /// The port the server is configured to listen on.
    private var port: UInt16

    /// Network.framework listener.
    private var listener: NWListener?

    /// Connected WebSocket clients.
    private var connections: [NWConnection] = []

    /// Lock protecting `connections` array.
    private let connectionsLock = NSLock()

    /// Serial queue for all Network.framework operations.
    private let serverQueue = DispatchQueue(
        label: AppConstants.DispatchQueues.websocketServer,
        qos: .utility
    )

    /// Whether the server is enabled by the user.
    private var isEnabled = false

    /// Lock protecting `isEnabled`.
    private let enabledLock = NSLock()

    // MARK: - Playback State

    /// Current track title.
    private var currentTrack: String?

    /// Current track artist.
    private var currentArtist: String?

    /// Current track album.
    private var currentAlbum: String?

    /// Current track duration in seconds.
    private var currentDuration: TimeInterval = 0

    /// Current elapsed time in seconds (at time of last update).
    private var currentElapsed: TimeInterval = 0

    /// Whether music is currently playing.
    private var isPlaying = false

    /// Artwork URL for the current track.
    private var currentArtworkURL: String?

    /// Timestamp when elapsed was last updated (for interpolation).
    private var lastElapsedUpdate: Date?

    /// Lock protecting playback state.
    private let playbackLock = NSLock()

    /// Timer for periodic progress broadcasts.
    private var progressTimer: DispatchSourceTimer?

    // MARK: - Init

    /// Creates the service with the given port. Does not start until `setEnabled(true)`.
    ///
    /// - Parameter port: TCP port to listen on. Defaults to `AppConstants.WebSocketServer.defaultPort`.
    init(port: UInt16 = AppConstants.WebSocketServer.defaultPort) {
        self.port = port
    }

    deinit {
        stopServer()
    }

    // MARK: - Public API

    /// Enables or disables the WebSocket server.
    ///
    /// When enabled, starts listening on the configured port.
    /// When disabled, stops the server and disconnects all clients.
    func setEnabled(_ enabled: Bool) {
        enabledLock.lock()
        isEnabled = enabled
        enabledLock.unlock()

        if enabled {
            serverQueue.async { [weak self] in
                self?.startServer()
            }
        } else {
            serverQueue.async { [weak self] in
                self?.stopServer()
            }
        }
    }

    /// Updates the server port. Restarts the server if currently running.
    ///
    /// - Parameter newPort: The new port number (1024–65535).
    func updatePort(_ newPort: UInt16) {
        guard newPort >= AppConstants.WebSocketServer.minPort,
              newPort <= AppConstants.WebSocketServer.maxPort else { return }

        let wasListening = state == .listening
        port = newPort

        if wasListening {
            serverQueue.async { [weak self] in
                self?.stopServer()
                self?.startServer()
            }
        }
    }

    /// Updates the now-playing state and broadcasts to all connected clients.
    ///
    /// - Parameters:
    ///   - track: Song title.
    ///   - artist: Artist name.
    ///   - album: Album name.
    ///   - duration: Total track duration in seconds.
    ///   - elapsed: Elapsed playback time in seconds.
    ///   - artworkURL: Optional artwork URL.
    func updateNowPlaying(
        track: String,
        artist: String,
        album: String,
        duration: TimeInterval,
        elapsed: TimeInterval,
        artworkURL: String? = nil
    ) {
        playbackLock.lock()
        currentTrack = track
        currentArtist = artist
        currentAlbum = album
        currentDuration = duration
        currentElapsed = elapsed
        isPlaying = true
        lastElapsedUpdate = Date()
        if let artworkURL {
            currentArtworkURL = artworkURL
        }
        playbackLock.unlock()

        broadcastNowPlaying()
        startProgressTimer()
    }

    /// Updates the artwork URL and re-broadcasts now-playing data.
    ///
    /// Called when artwork resolves asynchronously after the initial track notification.
    ///
    /// - Parameter url: The resolved artwork URL string.
    func updateArtworkURL(_ url: String) {
        playbackLock.lock()
        currentArtworkURL = url
        playbackLock.unlock()

        broadcastNowPlaying()
    }

    /// Clears the now-playing state (e.g., on pause or stop).
    func clearNowPlaying() {
        playbackLock.lock()
        isPlaying = false
        lastElapsedUpdate = nil
        playbackLock.unlock()

        stopProgressTimer()
        broadcastPlaybackState()
    }

    // MARK: - Server Lifecycle

    /// Starts the NWListener on the configured port.
    private func startServer() {
        guard listener == nil else { return }

        state = .starting
        notifyStateChange()

        let parameters = NWParameters.tcp
        let wsOptions = NWProtocolWebSocket.Options()
        wsOptions.autoReplyPing = true
        parameters.defaultProtocolStack.applicationProtocols.insert(wsOptions, at: 0)

        do {
            listener = try NWListener(using: parameters, on: NWEndpoint.Port(rawValue: port)!)
        } catch {
            Log.error("WebSocket: Failed to create listener: \(error)", category: "WebSocket")
            state = .error
            notifyStateChange()
            scheduleRetry()
            return
        }

        listener?.stateUpdateHandler = { [weak self] newState in
            guard let self else { return }
            switch newState {
            case .ready:
                self.state = .listening
                Log.info("WebSocket: Server listening on port \(self.port)", category: "WebSocket")
                self.notifyStateChange()
            case .failed(let error):
                Log.error("WebSocket: Listener failed: \(error)", category: "WebSocket")
                self.state = .error
                self.notifyStateChange()
                self.listener = nil
                self.scheduleRetry()
            case .cancelled:
                self.state = .stopped
                self.notifyStateChange()
            default:
                break
            }
        }

        listener?.newConnectionHandler = { [weak self] connection in
            self?.handleNewConnection(connection)
        }

        listener?.start(queue: serverQueue)
    }

    /// Stops the server and disconnects all clients.
    private func stopServer() {
        stopProgressTimer()

        listener?.cancel()
        listener = nil

        connectionsLock.lock()
        let conns = connections
        connections.removeAll()
        connectionsLock.unlock()

        for conn in conns {
            conn.cancel()
        }

        state = .stopped
        notifyStateChange()
        Log.info("WebSocket: Server stopped", category: "WebSocket")
    }

    /// Schedules a retry after listener failure, if still enabled.
    private func scheduleRetry() {
        enabledLock.lock()
        let shouldRetry = isEnabled
        enabledLock.unlock()

        guard shouldRetry else { return }

        Log.info("WebSocket: Retrying in \(AppConstants.WebSocketServer.retryDelay)s", category: "WebSocket")
        serverQueue.asyncAfter(deadline: .now() + AppConstants.WebSocketServer.retryDelay) { [weak self] in
            guard let self else { return }
            self.enabledLock.lock()
            let stillEnabled = self.isEnabled
            self.enabledLock.unlock()
            guard stillEnabled, self.listener == nil else { return }
            self.startServer()
        }
    }

    // MARK: - Connection Handling

    /// Handles a new incoming WebSocket connection.
    private func handleNewConnection(_ connection: NWConnection) {
        connection.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            switch state {
            case .ready:
                Log.info("WebSocket: Client connected (\(self.connectionCount + 1) total)", category: "WebSocket")
                self.connectionsLock.lock()
                self.connections.append(connection)
                self.connectionsLock.unlock()
                self.notifyStateChange()

                self.sendWelcome(to: connection)
                self.sendCurrentState(to: connection)
                self.receiveMessage(from: connection)

            case .failed(let error):
                Log.debug("WebSocket: Client connection failed: \(error)", category: "WebSocket")
                self.removeConnection(connection)

            case .cancelled:
                self.removeConnection(connection)

            default:
                break
            }
        }

        connection.start(queue: serverQueue)
    }

    /// Removes a connection from the tracked list.
    private func removeConnection(_ connection: NWConnection) {
        connectionsLock.lock()
        connections.removeAll { $0 === connection }
        let count = connections.count
        connectionsLock.unlock()

        Log.debug("WebSocket: Client disconnected (\(count) remaining)", category: "WebSocket")
        notifyStateChange()
    }

    /// Continuously receives messages from a connection (keep-alive).
    private func receiveMessage(from connection: NWConnection) {
        connection.receiveMessage { [weak self] content, context, isComplete, error in
            if let error {
                Log.debug("WebSocket: Receive error: \(error)", category: "WebSocket")
                return
            }

            // Keep receiving (we don't process inbound messages, just keep the connection alive)
            self?.receiveMessage(from: connection)
        }
    }

    /// Current number of connected clients.
    var connectionCount: Int {
        connectionsLock.lock()
        let count = connections.count
        connectionsLock.unlock()
        return count
    }

    // MARK: - Message Broadcasting

    /// Sends a welcome message to a newly connected client.
    private func sendWelcome(to connection: NWConnection) {
        let welcome: [String: Any] = [
            "type": "welcome",
            "server": "WolfWave",
            "version": "1.0.0",
        ]
        sendJSON(welcome, to: connection)
    }

    /// Sends the current playback state to a newly connected client.
    private func sendCurrentState(to connection: NWConnection) {
        playbackLock.lock()
        let track = currentTrack
        let artist = currentArtist
        let album = currentAlbum
        let duration = currentDuration
        let elapsed = estimatedElapsed()
        let playing = isPlaying
        let artwork = currentArtworkURL
        playbackLock.unlock()

        guard let track, let artist, let album else { return }

        let data: [String: Any] = [
            "track": track,
            "artist": artist,
            "album": album,
            "duration": duration,
            "elapsed": elapsed,
            "isPlaying": playing,
            "artworkURL": artwork ?? "",
        ]

        let message: [String: Any] = [
            "type": "now_playing",
            "data": data,
        ]

        sendJSON(message, to: connection)
    }

    /// Broadcasts a now_playing message to all connected clients.
    private func broadcastNowPlaying() {
        playbackLock.lock()
        let track = currentTrack
        let artist = currentArtist
        let album = currentAlbum
        let duration = currentDuration
        let elapsed = currentElapsed
        let playing = isPlaying
        let artwork = currentArtworkURL
        playbackLock.unlock()

        guard let track, let artist, let album else { return }

        let data: [String: Any] = [
            "track": track,
            "artist": artist,
            "album": album,
            "duration": duration,
            "elapsed": elapsed,
            "isPlaying": playing,
            "artworkURL": artwork ?? "",
        ]

        let message: [String: Any] = [
            "type": "now_playing",
            "data": data,
        ]

        broadcastJSON(message)
    }

    /// Broadcasts a playback_state message (pause/stop/resume).
    private func broadcastPlaybackState() {
        playbackLock.lock()
        let track = currentTrack ?? ""
        let artist = currentArtist ?? ""
        let album = currentAlbum ?? ""
        let playing = isPlaying
        playbackLock.unlock()

        let data: [String: Any] = [
            "isPlaying": playing,
            "track": track,
            "artist": artist,
            "album": album,
        ]

        let message: [String: Any] = [
            "type": "playback_state",
            "data": data,
        ]

        broadcastJSON(message)
    }

    /// Broadcasts a progress message with current elapsed time.
    private func broadcastProgress() {
        playbackLock.lock()
        let elapsed = estimatedElapsed()
        let duration = currentDuration
        let playing = isPlaying
        playbackLock.unlock()

        guard playing else { return }

        let data: [String: Any] = [
            "elapsed": elapsed,
            "duration": duration,
            "isPlaying": playing,
        ]

        let message: [String: Any] = [
            "type": "progress",
            "data": data,
        ]

        broadcastJSON(message)
    }

    /// Estimates the current elapsed time based on the last update and wall clock.
    ///
    /// Must be called with `playbackLock` held.
    private func estimatedElapsed() -> TimeInterval {
        guard let lastUpdate = lastElapsedUpdate, isPlaying else {
            return currentElapsed
        }
        let timeSinceUpdate = Date().timeIntervalSince(lastUpdate)
        return min(currentElapsed + timeSinceUpdate, currentDuration)
    }

    // MARK: - Progress Timer

    /// Starts the periodic progress broadcast timer.
    private func startProgressTimer() {
        stopProgressTimer()

        let timer = DispatchSource.makeTimerSource(queue: serverQueue)
        timer.schedule(
            deadline: .now() + AppConstants.WebSocketServer.progressBroadcastInterval,
            repeating: AppConstants.WebSocketServer.progressBroadcastInterval
        )
        timer.setEventHandler { [weak self] in
            self?.broadcastProgress()
        }
        timer.activate()
        progressTimer = timer
    }

    /// Stops the progress broadcast timer.
    private func stopProgressTimer() {
        progressTimer?.cancel()
        progressTimer = nil
    }

    // MARK: - JSON Helpers

    /// Sends a JSON dictionary as a WebSocket text message to a single connection.
    private func sendJSON(_ dict: [String: Any], to connection: NWConnection) {
        guard let jsonData = try? JSONSerialization.data(withJSONObject: dict),
              let jsonString = String(data: jsonData, encoding: .utf8) else {
            return
        }

        let metadata = NWProtocolWebSocket.Metadata(opcode: .text)
        let context = NWConnection.ContentContext(
            identifier: "websocket",
            metadata: [metadata]
        )

        connection.send(
            content: jsonString.data(using: .utf8),
            contentContext: context,
            isComplete: true,
            completion: .contentProcessed { error in
                if let error {
                    Log.debug("WebSocket: Send failed: \(error)", category: "WebSocket")
                }
            }
        )
    }

    /// Broadcasts a JSON dictionary to all connected clients.
    private func broadcastJSON(_ dict: [String: Any]) {
        connectionsLock.lock()
        let conns = connections
        connectionsLock.unlock()

        for connection in conns {
            sendJSON(dict, to: connection)
        }
    }

    // MARK: - State Notification

    /// Notifies the UI of state changes on the main thread.
    private func notifyStateChange() {
        let currentState = state
        let count = connectionCount
        DispatchQueue.main.async { [weak self] in
            self?.onStateChange?(currentState, count)

            NotificationCenter.default.post(
                name: NSNotification.Name(AppConstants.Notifications.websocketServerStateChanged),
                object: nil,
                userInfo: ["state": currentState.rawValue, "clients": count]
            )
        }
    }
}
