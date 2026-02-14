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
/// Thread-safe — all I/O runs on a dedicated serial queue; locks protect shared state.
final class WebSocketServerService: @unchecked Sendable {

    // MARK: - Types

    enum ServerState: String, Sendable {
        case stopped, starting, listening, error
    }

    // MARK: - Properties

    private(set) var state: ServerState = .stopped

    /// Called on the main thread when server state or client count changes.
    var onStateChange: ((ServerState, Int) -> Void)?

    private var port: UInt16
    private var listener: NWListener?
    private var connections: [NWConnection] = []
    private let connectionsLock = NSLock()
    private let serverQueue = DispatchQueue(
        label: AppConstants.DispatchQueues.websocketServer,
        qos: .utility
    )
    private var isEnabled = false
    private let enabledLock = NSLock()

    // MARK: - Playback State

    private var currentTrack: String?
    private var currentArtist: String?
    private var currentAlbum: String?
    private var currentDuration: TimeInterval = 0
    private var currentElapsed: TimeInterval = 0
    private var isPlaying = false
    private var currentArtworkURL: String?
    private var lastElapsedUpdate: Date?
    private let playbackLock = NSLock()
    private var progressTimer: DispatchSourceTimer?

    // MARK: - Init

    init(port: UInt16 = AppConstants.WebSocketServer.defaultPort) {
        self.port = port
    }

    deinit {
        stopServer()
    }

    // MARK: - Public API

    /// Starts or stops the server based on the given flag.
    func setEnabled(_ enabled: Bool) {
        enabledLock.lock()
        isEnabled = enabled
        enabledLock.unlock()

        if enabled {
            serverQueue.async { [weak self] in self?.startServer() }
        } else {
            serverQueue.async { [weak self] in self?.stopServer() }
        }
    }

    /// Changes the listening port. Restarts the server if it was already running.
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

    /// Stores new track metadata and broadcasts a `now_playing` message to all clients.
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
        if let artworkURL { currentArtworkURL = artworkURL }
        playbackLock.unlock()

        broadcastNowPlaying()
        startProgressTimer()
    }

    /// Updates the artwork URL and re-broadcasts the current track to all clients.
    func updateArtworkURL(_ url: String) {
        playbackLock.lock()
        currentArtworkURL = url
        playbackLock.unlock()

        broadcastNowPlaying()
    }

    /// Marks playback as stopped and broadcasts the state change.
    func clearNowPlaying() {
        playbackLock.lock()
        isPlaying = false
        lastElapsedUpdate = nil
        playbackLock.unlock()

        stopProgressTimer()
        broadcastPlaybackState()
    }

    // MARK: - Server Lifecycle

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
                Log.info("WebSocket: Listening on port \(self.port)", category: "WebSocket")
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

    private func stopServer() {
        stopProgressTimer()

        listener?.cancel()
        listener = nil

        connectionsLock.lock()
        let conns = connections
        connections.removeAll()
        connectionsLock.unlock()

        for conn in conns { conn.cancel() }

        state = .stopped
        notifyStateChange()
        Log.info("WebSocket: Server stopped", category: "WebSocket")
    }

    /// Retries starting the server after a delay if still enabled.
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
                Log.debug("WebSocket: Client failed: \(error)", category: "WebSocket")
                self.removeConnection(connection)
            case .cancelled:
                self.removeConnection(connection)
            default:
                break
            }
        }
        connection.start(queue: serverQueue)
    }

    private func removeConnection(_ connection: NWConnection) {
        connectionsLock.lock()
        connections.removeAll { $0 === connection }
        let count = connections.count
        connectionsLock.unlock()

        Log.debug("WebSocket: Client disconnected (\(count) remaining)", category: "WebSocket")
        notifyStateChange()
    }

    /// Keeps the connection alive by continuously consuming inbound messages.
    private func receiveMessage(from connection: NWConnection) {
        connection.receiveMessage { [weak self] _, _, _, error in
            if error != nil { return }
            self?.receiveMessage(from: connection)
        }
    }

    var connectionCount: Int {
        connectionsLock.lock()
        let count = connections.count
        connectionsLock.unlock()
        return count
    }

    // MARK: - Message Broadcasting

    private func sendWelcome(to connection: NWConnection) {
        sendJSON(["type": "welcome", "server": "WolfWave", "version": "1.0.0"], to: connection)
    }

    /// Sends the full current playback snapshot to a newly connected client.
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

        let message: [String: Any] = [
            "type": "now_playing",
            "data": [
                "track": track, "artist": artist, "album": album,
                "duration": duration, "elapsed": elapsed,
                "isPlaying": playing, "artworkURL": artwork ?? "",
            ],
        ]
        sendJSON(message, to: connection)
    }

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

        broadcastJSON([
            "type": "now_playing",
            "data": [
                "track": track, "artist": artist, "album": album,
                "duration": duration, "elapsed": elapsed,
                "isPlaying": playing, "artworkURL": artwork ?? "",
            ],
        ])
    }

    private func broadcastPlaybackState() {
        playbackLock.lock()
        let track = currentTrack ?? ""
        let artist = currentArtist ?? ""
        let album = currentAlbum ?? ""
        let playing = isPlaying
        playbackLock.unlock()

        broadcastJSON([
            "type": "playback_state",
            "data": ["isPlaying": playing, "track": track, "artist": artist, "album": album],
        ])
    }

    private func broadcastProgress() {
        playbackLock.lock()
        let elapsed = estimatedElapsed()
        let duration = currentDuration
        let playing = isPlaying
        playbackLock.unlock()

        guard playing else { return }

        broadcastJSON([
            "type": "progress",
            "data": ["elapsed": elapsed, "duration": duration, "isPlaying": playing],
        ])
    }

    /// Interpolates elapsed time using the wall clock. Must be called with `playbackLock` held.
    private func estimatedElapsed() -> TimeInterval {
        guard let lastUpdate = lastElapsedUpdate, isPlaying else { return currentElapsed }
        return min(currentElapsed + Date().timeIntervalSince(lastUpdate), currentDuration)
    }

    // MARK: - Progress Timer

    private func startProgressTimer() {
        stopProgressTimer()

        let timer = DispatchSource.makeTimerSource(queue: serverQueue)
        timer.schedule(
            deadline: .now() + AppConstants.WebSocketServer.progressBroadcastInterval,
            repeating: AppConstants.WebSocketServer.progressBroadcastInterval
        )
        timer.setEventHandler { [weak self] in self?.broadcastProgress() }
        timer.activate()
        progressTimer = timer
    }

    private func stopProgressTimer() {
        progressTimer?.cancel()
        progressTimer = nil
    }

    // MARK: - JSON Helpers

    private func sendJSON(_ dict: [String: Any], to connection: NWConnection) {
        guard let jsonData = try? JSONSerialization.data(withJSONObject: dict),
              let jsonString = String(data: jsonData, encoding: .utf8) else { return }

        let metadata = NWProtocolWebSocket.Metadata(opcode: .text)
        let context = NWConnection.ContentContext(identifier: "websocket", metadata: [metadata])

        connection.send(
            content: jsonString.data(using: .utf8),
            contentContext: context,
            isComplete: true,
            completion: .contentProcessed { error in
                if let error { Log.debug("WebSocket: Send failed: \(error)", category: "WebSocket") }
            }
        )
    }

    private func broadcastJSON(_ dict: [String: Any]) {
        connectionsLock.lock()
        let conns = connections
        connectionsLock.unlock()

        for connection in conns { sendJSON(dict, to: connection) }
    }

    // MARK: - State Notification

    /// Posts a notification and invokes the callback on the main thread.
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
