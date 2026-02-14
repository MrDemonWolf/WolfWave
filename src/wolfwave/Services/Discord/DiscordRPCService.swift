//
//  DiscordRPCService.swift
//  wolfwave
//
//  Created by MrDemonWolf, Inc. on 2/7/26.
//

import AppKit
import Foundation

// MARK: - Discord RPC Service

/// Manages Discord Rich Presence via the local IPC socket.
///
/// Connects to Discord's Unix domain socket at `$TMPDIR/discord-ipc-{0..9}`,
/// performs the RPC handshake, and sends SET_ACTIVITY commands to display
/// "Listening to Apple Music" on the user's Discord profile.
///
/// No bot token is required — only a Discord Application ID from the
/// Developer Portal, provided via `DISCORD_CLIENT_ID` in Config.xcconfig.
///
/// Thread Safety:
/// - All socket I/O runs on a dedicated serial dispatch queue.
/// - Public methods are safe to call from any thread.
///
/// Reconnection:
/// - Automatically reconnects with exponential backoff when Discord restarts.
/// - Polls for Discord availability when not connected.
final class DiscordRPCService: @unchecked Sendable {

    // MARK: - Types

    /// IPC frame opcodes per Discord RPC spec.
    private enum Opcode: UInt32 {
        case handshake = 0
        case frame     = 1
        case close     = 2
    }

    /// Connection state.
    enum ConnectionState: String, Sendable {
        case disconnected
        case connecting
        case connected
    }

    // MARK: - Properties

    /// Current connection state. Updated on the IPC queue, read from any thread.
    private(set) var state: ConnectionState = .disconnected {
        didSet {
            let newState = state
            DispatchQueue.main.async { [weak self] in
                self?.onStateChange?(newState)
            }
        }
    }

    /// Callback invoked on the main thread whenever connection state changes.
    var onStateChange: ((ConnectionState) -> Void)?

    /// Discord Application ID resolved from Info.plist / environment.
    private let clientID: String

    /// File descriptor for the connected Unix domain socket, or -1.
    private var socketFD: Int32 = -1

    /// Serial queue for all socket I/O.
    private let ipcQueue = DispatchQueue(
        label: AppConstants.DispatchQueues.discordIPC,
        qos: .utility
    )

    /// Current reconnect delay (doubles on each failure, capped).
    private var reconnectDelay: TimeInterval = AppConstants.Discord.reconnectBaseDelay

    /// Timer source for availability polling / reconnect.
    private var pollTimer: DispatchSourceTimer?

    /// Whether the service is enabled by the user.
    private var isEnabled = false

    /// Lock protecting `isEnabled` reads/writes across threads.
    private let enabledLock = NSLock()

    /// Process ID sent with SET_ACTIVITY (Discord requires it).
    private let pid = ProcessInfo.processInfo.processIdentifier

    /// Cache of iTunes artwork URLs. Key: "artist|track", Value: artwork URL string.
    private var artworkCache: [String: String] = [:]

    /// Tracks the last artwork lookup key to avoid redundant re-sends.
    private var lastArtworkKey: String?

    // MARK: - Init

    /// Creates the service. Does not connect until `setEnabled(true)` is called.
    ///
    /// - Parameter clientID: Discord Application ID. If nil, attempts to resolve
    ///   from Info.plist (`DISCORD_CLIENT_ID`) or environment.
    init(clientID: String? = nil) {
        self.clientID = clientID ?? Self.resolveClientID() ?? ""
    }

    deinit {
        disconnect()
        pollTimer?.cancel()
        pollTimer = nil
    }

    // MARK: - Public API

    /// Enables or disables the service.
    ///
    /// When enabled, immediately attempts to connect to Discord.
    /// When disabled, disconnects and stops polling.
    func setEnabled(_ enabled: Bool) {
        enabledLock.withLock { isEnabled = enabled }

        if enabled {
            ipcQueue.async { [weak self] in
                self?.connectIfNeeded()
                self?.startPolling()
            }
        } else {
            ipcQueue.async { [weak self] in
                self?.stopPolling()
                self?.clearPresence()
                self?.disconnect()
            }
        }
    }

    /// Updates the Rich Presence to show the currently playing track.
    ///
    /// Fetches album artwork from the iTunes Search API on cache miss and
    /// re-sends the presence once the artwork URL is available. Cached artwork
    /// is used immediately on subsequent calls for the same track.
    ///
    /// - Parameters:
    ///   - track: Song title (shown as "details").
    ///   - artist: Artist name (shown as "state").
    ///   - album: Album name (shown in large image tooltip).
    ///   - duration: Total track duration in seconds (0 if unknown).
    ///   - elapsed: Elapsed time in seconds (0 if unknown).
    func updatePresence(
        track: String,
        artist: String,
        album: String,
        duration: TimeInterval = 0,
        elapsed: TimeInterval = 0
    ) {
        ipcQueue.async { [weak self] in
            guard let self, self.state == .connected else { return }

            let cacheKey = "\(artist)|\(track)"

            // Send immediately with cached artwork (or nil on first encounter)
            let cachedArtwork = self.artworkCache[cacheKey]
            self.sendPresenceActivity(
                track: track, artist: artist, album: album,
                artworkURL: cachedArtwork,
                duration: duration, elapsed: elapsed
            )

            // Fetch artwork asynchronously on cache miss
            if cachedArtwork == nil {
                self.fetchArtworkURL(track: track, artist: artist) { [weak self] url in
                    guard let self, let url else { return }
                    self.ipcQueue.async {
                        self.artworkCache[cacheKey] = url
                        guard self.state == .connected else { return }
                        // Re-send presence with the artwork
                        self.sendPresenceActivity(
                            track: track, artist: artist, album: album,
                            artworkURL: url,
                            duration: duration, elapsed: elapsed
                        )
                    }
                }
            }
        }
    }

    /// Clears the Rich Presence (e.g., when playback stops).
    func clearPresence() {
        ipcQueue.async { [weak self] in
            guard let self, self.state == .connected else { return }

            let payload: [String: Any] = [
                "cmd": "SET_ACTIVITY",
                "args": [
                    "pid": self.pid,
                ],
                "nonce": UUID().uuidString,
            ]

            self.sendFrame(opcode: .frame, payload: payload)
        }
    }

    // MARK: - Presence Helpers

    /// Builds and sends a SET_ACTIVITY frame with the given track metadata.
    ///
    /// - Parameters:
    ///   - track: Song title.
    ///   - artist: Artist name.
    ///   - album: Album name (used as large image tooltip).
    ///   - artworkURL: Optional iTunes artwork URL. If nil, falls back to the
    ///     static "apple_music" asset uploaded in the Discord Developer Portal.
    ///   - duration: Total track duration in seconds (0 if unknown).
    ///   - elapsed: Elapsed time in seconds (0 if unknown).
    private func sendPresenceActivity(
        track: String,
        artist: String,
        album: String,
        artworkURL: String?,
        duration: TimeInterval,
        elapsed: TimeInterval
    ) {
        var activity: [String: Any] = [
            "type": AppConstants.Discord.listeningActivityType,
            "details": track,
            "state": "by \(artist)",
        ]

        // Assets — prefer dynamic artwork URL from iTunes, fall back to static asset
        let largeImage = artworkURL ?? "apple_music"
        var assets: [String: Any] = [
            "large_image": largeImage,
            "large_text": album,
        ]
        // Show Apple Music branding as small icon when we have album art
        if artworkURL != nil {
            assets["small_image"] = "apple_music"
            assets["small_text"] = "Apple Music"
        }
        activity["assets"] = assets

        // Timestamps — show a progress bar if duration is known
        if duration > 0 {
            let now = Date().timeIntervalSince1970
            let start = now - elapsed
            let end = start + duration
            activity["timestamps"] = [
                "start": Int(start * 1000),
                "end": Int(end * 1000),
            ]
        }

        let payload: [String: Any] = [
            "cmd": "SET_ACTIVITY",
            "args": [
                "pid": self.pid,
                "activity": activity,
            ],
            "nonce": UUID().uuidString,
        ]

        sendFrame(opcode: .frame, payload: payload)
    }

    // MARK: - iTunes Artwork Lookup

    /// Fetches album artwork URL from the iTunes Search API.
    ///
    /// Searches for the track by name and artist and returns the first result's
    /// artwork URL scaled to 512×512. The completion handler is called on an
    /// arbitrary URLSession queue.
    ///
    /// - Parameters:
    ///   - track: Song title.
    ///   - artist: Artist name.
    ///   - completion: Called with the artwork URL, or nil if not found or on error.
    private func fetchArtworkURL(track: String, artist: String, completion: @escaping (String?) -> Void) {
        let query = "\(track) \(artist)"
        guard let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "https://itunes.apple.com/search?media=music&entity=song&limit=1&term=\(encoded)") else {
            completion(nil)
            return
        }

        URLSession.shared.dataTask(with: url) { data, _, error in
            guard let data, error == nil,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let results = json["results"] as? [[String: Any]],
                  let first = results.first,
                  let artworkUrl = first["artworkUrl100"] as? String else {
                Log.debug("Discord: iTunes artwork lookup failed for \"\(track)\" by \(artist)", category: "Discord")
                completion(nil)
                return
            }

            // Upscale from 100×100 to 512×512 for better quality on Discord
            let highRes = artworkUrl.replacingOccurrences(of: "100x100", with: "512x512")
            completion(highRes)
        }.resume()
    }

    // MARK: - Client ID Resolution

    /// Resolves the Discord Application ID from Info.plist or environment.
    ///
    /// Lookup order:
    /// 1. `DISCORD_CLIENT_ID` key in Info.plist (expanded from Config.xcconfig at build time)
    /// 2. `DISCORD_CLIENT_ID` environment variable (for dev/CI overrides)
    ///
    /// - Returns: The client ID string, or nil if not configured.
    static func resolveClientID() -> String? {
        if let plistValue = Bundle.main.object(forInfoDictionaryKey: "DISCORD_CLIENT_ID") as? String,
           !plistValue.isEmpty,
           plistValue != "$(DISCORD_CLIENT_ID)",
           plistValue != "your_discord_application_id_here" {
            return plistValue
        }

        if let env = ProcessInfo.processInfo.environment["DISCORD_CLIENT_ID"], !env.isEmpty {
            return env
        }

        return nil
    }

    // MARK: - Temp Directory

    /// Known Discord bundle identifiers (stable, Canary, PTB).
    private static let discordBundleIDs = [
        "com.hnc.Discord",
        "com.hnc.Discord.Canary",
        "com.hnc.Discord.PTB",
    ]

    /// Returns candidate temp directory paths for locating Discord's IPC socket.
    ///
    /// In a sandboxed app, `$TMPDIR`, `NSTemporaryDirectory()`, and `confstr` all
    /// return the container path (`~/Library/Containers/<id>/Data/tmp/`), but Discord
    /// places its IPC socket in the OS-level temp directory (`/var/folders/.../T/`).
    ///
    /// Strategy (in priority order):
    /// 1. Read the real `TMPDIR` from a running Discord process via `sysctl(KERN_PROCARGS2)`.
    ///    This kernel query is not blocked by App Sandbox.
    /// 2. Fall back to `confstr(_CS_DARWIN_USER_TEMP_DIR)` (works for non-sandboxed apps).
    ///
    /// All returned paths are resolved through symlinks so the sandbox sees the
    /// canonical form (e.g., `/private/var/folders/…` instead of `/var/folders/…`).
    ///
    /// - Returns: Array of directory paths to search, most likely first.
    private func tempDirectoryCandidates() -> [String] {
        var candidates: [String] = []

        // 1. Read the REAL TMPDIR from Discord's own process environment.
        //    sysctl(KERN_PROCARGS2) returns argv + environ for same-user processes
        //    and is NOT redirected by App Sandbox.
        if let discordTmpDir = readDiscordTmpDir() {
            let resolved = Self.resolveSymlinks(discordTmpDir)
            candidates.append(resolved)
        }

        // 2. confstr — works outside sandbox, returns container path inside sandbox.
        let len = confstr(_CS_DARWIN_USER_TEMP_DIR, nil, 0)
        if len > 0 {
            var buf = [CChar](repeating: 0, count: len)
            confstr(_CS_DARWIN_USER_TEMP_DIR, &buf, len)
            let resolved = Self.resolveSymlinks(String(cString: buf))
            if !candidates.contains(resolved) {
                candidates.append(resolved)
            }
        }

        return candidates
    }

    /// Resolves symlinks in a path to produce the canonical filesystem path.
    ///
    /// On macOS, `/var` is a symlink to `/private/var`. The App Sandbox checks
    /// against canonical paths, so `connect()` to `/var/folders/.../discord-ipc-0`
    /// won't match an SBPL rule for `/private/var/folders/...`. This method
    /// ensures paths use the real, resolved form.
    private static func resolveSymlinks(_ path: String) -> String {
        // URL.resolvingSymlinksInPath() resolves all symlinks and also
        // standardizes the path (removes trailing slashes, `.`, `..`).
        URL(fileURLWithPath: path).resolvingSymlinksInPath().path
    }

    /// Reads the `TMPDIR` environment variable from a running Discord process.
    ///
    /// Uses `sysctl(KERN_PROCARGS2)` which returns the command-line arguments and
    /// environment of any same-user process. This is a kernel info query, not a
    /// file-system operation, so App Sandbox does not block it.
    ///
    /// - Returns: Discord's TMPDIR value, or nil if Discord is not running or
    ///   the environment cannot be read.
    private func readDiscordTmpDir() -> String? {
        // Find a running Discord process
        var discordPID: pid_t = 0
        for bundleID in Self.discordBundleIDs {
            if let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first {
                discordPID = app.processIdentifier
                break
            }
        }
        guard discordPID > 0 else { return nil }

        // Query the size of the process args buffer
        var mib: [Int32] = [CTL_KERN, KERN_PROCARGS2, discordPID]
        var size: size_t = 0
        guard sysctl(&mib, 3, nil, &size, nil, 0) == 0, size > 0 else {
            return nil
        }

        // Read the process args buffer
        var buffer = [UInt8](repeating: 0, count: size)
        guard sysctl(&mib, 3, &buffer, &size, nil, 0) == 0 else {
            return nil
        }

        // KERN_PROCARGS2 layout:
        //   [argc: Int32][exec_path\0][padding\0...][argv[0]\0]...[argv[n]\0][env[0]\0]...
        guard size > MemoryLayout<Int32>.size else { return nil }
        let argc = buffer.withUnsafeBufferPointer { buf in
            buf.baseAddress!.withMemoryRebound(to: Int32.self, capacity: 1) { $0.pointee }
        }

        // Collect all null-terminated strings after the header
        var strings: [String] = []
        var current: [UInt8] = []
        for i in MemoryLayout<Int32>.size..<size {
            let byte = buffer[i]
            if byte == 0 {
                if !current.isEmpty {
                    if let str = String(bytes: current, encoding: .utf8) {
                        strings.append(str)
                    }
                    current = []
                }
            } else {
                current.append(byte)
            }
        }

        // strings[0] = exec path, strings[1..argc] = argv, rest = environment
        let envStart = 1 + Int(argc)
        guard envStart < strings.count else { return nil }

        for i in envStart..<strings.count {
            if strings[i].hasPrefix("TMPDIR=") {
                let value = String(strings[i].dropFirst(7))
                Log.debug("Discord: Read TMPDIR from Discord process: \(value)", category: "Discord")
                return value
            }
        }

        return nil
    }

    // MARK: - Connection

    /// Attempts to connect to Discord's IPC socket.
    ///
    /// Tries each candidate temp directory, and within each, tries sockets 0 through 9.
    /// Keeps the first successful connection.
    private func connectIfNeeded() {
        guard state == .disconnected else { return }
        guard !clientID.isEmpty else {
            Log.warn("Discord: No client ID configured — skipping connection", category: "Discord")
            return
        }

        state = .connecting

        let candidates = tempDirectoryCandidates()
        guard !candidates.isEmpty else {
            Log.error("Discord: Cannot determine any temp directory", category: "Discord")
            state = .disconnected
            return
        }

        for basePath in candidates {
            Log.debug("Discord: Searching for IPC socket in \(basePath)", category: "Discord")

            for slot in 0..<AppConstants.Discord.ipcSocketSlots {
                let socketPath = (basePath as NSString).appendingPathComponent(
                    "\(AppConstants.Discord.ipcSocketPrefix)\(slot)"
                )

                let fd = socket(AF_UNIX, SOCK_STREAM, 0)
                guard fd >= 0 else { continue }

                var addr = sockaddr_un()
                addr.sun_family = sa_family_t(AF_UNIX)

                let pathBytes = socketPath.utf8CString
                guard pathBytes.count <= MemoryLayout.size(ofValue: addr.sun_path) else {
                    Darwin.close(fd)
                    continue
                }

                withUnsafeMutablePointer(to: &addr.sun_path) { sunPathPtr in
                    sunPathPtr.withMemoryRebound(to: CChar.self, capacity: pathBytes.count) { dest in
                        pathBytes.withUnsafeBufferPointer { src in
                            _ = memcpy(dest, src.baseAddress!, pathBytes.count)
                        }
                    }
                }

                let addrLen = socklen_t(MemoryLayout<sockaddr_un>.size)
                let result = withUnsafePointer(to: &addr) { addrPtr in
                    addrPtr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPtr in
                        Darwin.connect(fd, sockaddrPtr, addrLen)
                    }
                }

                if result == 0 {
                    socketFD = fd

                    if performHandshake() {
                        state = .connected
                        reconnectDelay = AppConstants.Discord.reconnectBaseDelay
                        return
                    } else {
                        Log.warn("Discord: Handshake failed on slot \(slot)", category: "Discord")
                        Darwin.close(fd)
                        socketFD = -1
                    }
                } else {
                    let err = errno
                    Log.debug("Discord: connect() failed on slot \(slot): errno \(err) (\(String(cString: strerror(err))))", category: "Discord")
                    Darwin.close(fd)
                }
            }
        }

        Log.debug("Discord: No active IPC socket found in any candidate directory", category: "Discord")
        state = .disconnected
    }

    /// Sends the RPC handshake (opcode 0) with the client ID.
    ///
    /// - Returns: True if handshake was sent and a response was received.
    private func performHandshake() -> Bool {
        let handshake: [String: Any] = [
            "v": AppConstants.Discord.rpcVersion,
            "client_id": clientID,
        ]

        guard sendFrame(opcode: .handshake, payload: handshake) else {
            return false
        }

        // Read the READY response
        guard let (opcode, _) = readFrame() else {
            Log.warn("Discord: No handshake response", category: "Discord")
            return false
        }

        if opcode == Opcode.close.rawValue {
            Log.warn("Discord: Received CLOSE during handshake", category: "Discord")
            return false
        }

        return true
    }

    /// Disconnects from the IPC socket.
    private func disconnect() {
        guard socketFD >= 0 else { return }
        Darwin.close(socketFD)
        socketFD = -1
        state = .disconnected
    }

    // MARK: - Frame I/O

    /// Sends a framed message to Discord.
    ///
    /// Frame format: `[opcode: UInt32 LE][length: UInt32 LE][JSON payload]`
    ///
    /// - Parameters:
    ///   - opcode: The IPC opcode.
    ///   - payload: Dictionary to serialize as JSON.
    /// - Returns: True if the write succeeded.
    @discardableResult
    private func sendFrame(opcode: Opcode, payload: [String: Any]) -> Bool {
        guard socketFD >= 0 else { return false }

        guard let jsonData = try? JSONSerialization.data(withJSONObject: payload) else {
            Log.error("Discord: Failed to serialize payload", category: "Discord")
            return false
        }

        var header = Data(count: 8)
        header.withUnsafeMutableBytes { buf in
            buf.storeBytes(of: opcode.rawValue.littleEndian, toByteOffset: 0, as: UInt32.self)
            buf.storeBytes(of: UInt32(jsonData.count).littleEndian, toByteOffset: 4, as: UInt32.self)
        }

        let frameData = header + jsonData

        let written = frameData.withUnsafeBytes { buf in
            Darwin.write(socketFD, buf.baseAddress!, frameData.count)
        }

        if written != frameData.count {
            Log.error("Discord: Write failed (wrote \(written)/\(frameData.count))", category: "Discord")
            handleConnectionLost()
            return false
        }

        return true
    }

    /// Reads a single framed message from Discord.
    ///
    /// - Returns: Tuple of (opcode, JSON payload) or nil on failure.
    private func readFrame() -> (UInt32, [String: Any]?)? {
        guard socketFD >= 0 else { return nil }

        var headerBuf = Data(count: 8)
        let headerRead = headerBuf.withUnsafeMutableBytes { buf in
            Darwin.read(socketFD, buf.baseAddress!, 8)
        }
        guard headerRead == 8 else { return nil }

        let opcode = headerBuf.withUnsafeBytes { buf in
            UInt32(littleEndian: buf.load(fromByteOffset: 0, as: UInt32.self))
        }
        let length = headerBuf.withUnsafeBytes { buf in
            UInt32(littleEndian: buf.load(fromByteOffset: 4, as: UInt32.self))
        }

        guard length > 0, length < 65536 else { return (opcode, nil) }

        var bodyBuf = Data(count: Int(length))
        let bodyRead = bodyBuf.withUnsafeMutableBytes { buf in
            Darwin.read(socketFD, buf.baseAddress!, Int(length))
        }
        guard bodyRead == Int(length) else { return nil }

        let json = try? JSONSerialization.jsonObject(with: bodyBuf) as? [String: Any]
        return (opcode, json)
    }

    // MARK: - Reconnection

    /// Handles a lost connection by disconnecting and scheduling reconnect.
    private func handleConnectionLost() {
        disconnect()

        let shouldReconnect = enabledLock.withLock { isEnabled }

        guard shouldReconnect else { return }

        Log.info("Discord: Scheduling reconnect in \(reconnectDelay)s", category: "Discord")
        ipcQueue.asyncAfter(deadline: .now() + reconnectDelay) { [weak self] in
            guard let self else { return }
            let stillEnabled = self.enabledLock.withLock { self.isEnabled }
            guard stillEnabled else { return }
            self.connectIfNeeded()
        }

        reconnectDelay = min(reconnectDelay * 2, AppConstants.Discord.reconnectMaxDelay)
    }

    // MARK: - Polling

    /// Starts polling for Discord availability when not connected.
    private func startPolling() {
        stopPolling()

        let timer = DispatchSource.makeTimerSource(queue: ipcQueue)
        timer.schedule(
            deadline: .now() + AppConstants.Discord.availabilityPollInterval,
            repeating: AppConstants.Discord.availabilityPollInterval
        )
        timer.setEventHandler { [weak self] in
            guard let self else { return }
            let enabled = self.enabledLock.withLock { self.isEnabled }
            guard enabled, self.state == .disconnected else { return }
            self.connectIfNeeded()
        }
        timer.activate()
        pollTimer = timer
    }

    /// Stops the availability poll timer.
    private func stopPolling() {
        pollTimer?.cancel()
        pollTimer = nil
    }
}
