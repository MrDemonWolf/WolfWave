//
//  DiscordRPCService.swift
//  WolfWave
//
//  Created by Nathanial Henniges on 2026-02-07.
//  Copyright © 2026 MrDemonWolf, Inc. All rights reserved.
//

import AppKit
import Foundation

// MARK: - Discord Playlist Style

/// How the current Apple Music playlist is surfaced in Discord Rich Presence.
///
/// Raw values are persisted in `UserDefaults`, so keep them stable across releases.
nonisolated enum DiscordPlaylistStyle: String, CaseIterable, Sendable {
    /// Playlist joins the artist on the activity's second line (`state`).
    case artistLine
    /// Playlist appears only in the small-icon hover tooltip (`assets.small_text`).
    case iconTooltip

    /// The style applied when no preference (or an unknown value) is stored.
    static let `default`: DiscordPlaylistStyle = .artistLine

    /// Resolves a stored raw value to a style, falling back to ``default``.
    static func resolved(from raw: String?) -> DiscordPlaylistStyle {
        guard let raw, let style = DiscordPlaylistStyle(rawValue: raw) else {
            return .default
        }
        return style
    }
}

// MARK: - Discord RPC Service

/// Manages Discord Rich Presence via the local IPC socket.
///
/// Connects to Discord's Unix domain socket at `$TMPDIR/discord-ipc-{0..9}`,
/// performs the RPC handshake, and sends SET_ACTIVITY commands to display
/// "Listening to Apple Music" on the user's Discord profile.
///
/// No bot token is required, only a Discord Application ID from the
/// Developer Portal, provided via `DISCORD_CLIENT_ID` in Config.xcconfig.
///
/// Thread Safety:
/// - Implemented as an `actor`. All mutable state runs on the actor's serial
///   executor.
/// - The *blocking* socket syscalls (`connect`, `read`, `write`, `setsockopt`)
///   do **not** run on the actor executor. They are dispatched onto a dedicated
///   serial `ipcQueue` and bridged back with `withCheckedContinuation`, so the
///   actor `await`s the result without parking its executor. A stalled handshake
///   or slow peer can no longer delay `updatePresence` or any other
///   actor-isolated call. The serial queue keeps the connection lifecycle
///   single-threaded (one connect / handshake / frame at a time), exactly as the
///   actor-serialized version did. The blocking primitives are pure functions of
///   an explicit `fd` parameter and never touch actor state.
/// - State changes and resolved artwork URLs are published as `AsyncStream`s
///   on `stateChanges` and `artworkResolutions`. The streams are `nonisolated`
///   so consumers can iterate without an extra actor hop.
///
/// Reconnection:
/// - Automatically reconnects with exponential backoff when Discord restarts.
/// - Polls for Discord availability when not connected.
actor DiscordRPCService {

    // MARK: - Types

    /// IPC frame opcodes per Discord RPC spec.
    /// Widened from `private` to `internal` so the IPC extension
    /// (`DiscordRPCService+IPC.swift`) can reference it across files.
    enum Opcode: UInt32 {
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

    /// Payload yielded by ``artworkResolutions`` when artwork resolves for a track.
    struct ArtworkResolution: Sendable, Equatable {
        let url: String
        let track: String
        let artist: String
    }

    // MARK: - Streams (nonisolated)

    /// Connection-state transitions, yielded whenever ``state`` changes.
    ///
    /// Consumers iterate via `for await newState in service.stateChanges`.
    nonisolated let stateChanges: AsyncStream<ConnectionState>
    private nonisolated let stateContinuation: AsyncStream<ConnectionState>.Continuation

    /// Track artwork URLs, yielded once `ArtworkService` resolves the lookup.
    ///
    /// Consumers iterate via `for await resolution in service.artworkResolutions`.
    nonisolated let artworkResolutions: AsyncStream<ArtworkResolution>
    private nonisolated let artworkContinuation: AsyncStream<ArtworkResolution>.Continuation

    // MARK: - Properties

    /// Lock-guarded mirror of ``state`` for nonisolated reads.
    private nonisolated let _stateSnapshot = Atomic<ConnectionState>(.disconnected)

    /// Latest connection state, safe to read synchronously from any thread.
    /// Mirrors ``state``; updated whenever the actor mutates `state`.
    nonisolated var stateSnapshot: ConnectionState {
        _stateSnapshot.value
    }

    /// Current connection state. Publishes to ``stateChanges`` on each transition
    /// and mirrors into ``stateSnapshot`` for nonisolated reads.
    ///
    /// Setter widened from `private(set)` to `internal` so the IPC extension
    /// (`DiscordRPCService+IPC.swift`) can transition it across files.
    var state: ConnectionState = .disconnected {
        didSet {
            guard oldValue != state else { return }
            _stateSnapshot.set(state)
            stateContinuation.yield(state)
        }
    }

    /// Discord Application ID resolved from Info.plist / environment.
    /// Widened from `private` for `DiscordRPCService+IPC.swift`.
    let clientID: String

    /// File descriptor for the connected Unix domain socket, or -1.
    /// Widened from `private` for `DiscordRPCService+IPC.swift`.
    var socketFD: Int32 = -1

    /// Monotonic token bumped on every disconnect/teardown.
    ///
    /// `connectIfNeeded` captures this before awaiting the off-actor
    /// `openIPCSocket` hop. If a `setEnabled(false)` (or any other teardown)
    /// lands during that await, the generation changes; the connect then closes
    /// the just-opened fd on ``ipcQueue`` and bails without committing
    /// `socketFD`/`state`, so an in-flight connect can never win after a disable.
    /// Widened from `private` for `DiscordRPCService+IPC.swift`.
    var connectionGeneration: UInt64 = 0

    /// Dedicated serial queue for the blocking socket syscalls.
    ///
    /// `connect`, `read`, `write`, and `setsockopt` block the calling thread.
    /// Running them here (instead of on the actor's serial executor) keeps a
    /// stalled handshake or slow peer from parking the actor. The queue is
    /// serial, so the connection lifecycle stays single-threaded. There is
    /// never concurrent access to `socketFD` from two IPC operations at once.
    /// Widened from `private` for `DiscordRPCService+IPC.swift`.
    nonisolated let ipcQueue = DispatchQueue(label: "com.mrdemonwolf.wolfwave.discord-ipc")

    /// Current reconnect delay (doubles on each failure, capped).
    /// Widened from `private` for `DiscordRPCService+IPC.swift`.
    var reconnectDelay: TimeInterval = AppConstants.Discord.reconnectBaseDelay

    /// Active polling task (availability checks while disconnected).
    private var pollTask: Task<Void, Never>?

    /// Active reconnect task (scheduled after a connection loss).
    /// Widened from `private` for `DiscordRPCService+IPC.swift`.
    var reconnectTask: Task<Void, Never>?

    /// Current availability poll interval (may be widened in reduced-power mode).
    private var currentPollInterval: TimeInterval = AppConstants.Discord.availabilityPollInterval

    /// Whether the service is enabled by the user.
    /// Widened from `private` for `DiscordRPCService+IPC.swift`.
    var isEnabled = false

    /// Process ID sent with SET_ACTIVITY (Discord requires it).
    private let pid = ProcessInfo.processInfo.processIdentifier

    /// Snapshot of the most recent `updatePresence` call. Used to re-send the
    /// current activity when display settings (button labels, toggles, state format)
    /// change via `discordPresenceSettingsChanged`, so users see the effect of a
    /// label edit without waiting for the next track change.
    private struct LastPresence {
        let track: String
        let artist: String
        let album: String
        let playlist: String
        let duration: TimeInterval
        let elapsed: TimeInterval
        let isPaused: Bool
        let capturedAt: Date
    }
    private var lastPresence: LastPresence?

    /// Observer token for `discordPresenceSettingsChanged`.
    private nonisolated(unsafe) var settingsObserver: NSObjectProtocol?

    /// Cached result of `readDiscordTmpDir()` to avoid sysctl on every connect.
    private var cachedDiscordTmpDir: String?
    /// When `cachedDiscordTmpDir` was last populated.
    private var cachedDiscordTmpDirAt: Date = .distantPast
    /// How long the TMPDIR cache is valid (Discord's TMPDIR doesn't change mid-session).
    private let discordTmpDirTTL: TimeInterval = 30

    // MARK: - Init

    /// Creates the service. Does not connect until `setEnabled(true)` is called.
    ///
    /// - Parameter clientID: Discord Application ID. If nil, attempts to resolve
    ///   from Info.plist (`DISCORD_CLIENT_ID`) or environment.
    init(clientID: String? = nil) {
        self.clientID = clientID ?? Self.resolveClientID() ?? ""

        let (stateStream, stateCont) = AsyncStream<ConnectionState>.makeStream()
        self.stateChanges = stateStream
        self.stateContinuation = stateCont

        let (artStream, artCont) = AsyncStream<ArtworkResolution>.makeStream()
        self.artworkResolutions = artStream
        self.artworkContinuation = artCont

        // Re-send presence when display settings change so users see button-label
        // edits and similar tweaks immediately. Delivery is pinned to the main
        // queue so the block never fires on an arbitrary thread while `init` is
        // still completing (the closure captures `self`); the block only hops
        // into a detached Task, so main-queue delivery adds no real work.
        let name = Notification.Name.discordPresenceSettingsChanged
        self.settingsObserver = NotificationCenter.default.addObserver(
            forName: name, object: nil, queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            Task { await self.resendLastPresence() }
        }
    }

    deinit {
        if let settingsObserver {
            NotificationCenter.default.removeObserver(settingsObserver)
        }
        pollTask?.cancel()
        reconnectTask?.cancel()
        // `deinit` is nonisolated and cannot `await`, so dispatch the close onto
        // `ipcQueue` (capturing the fd value, never `self`) so it still
        // serializes after any queued read/write that holds the same descriptor.
        // A bare `Darwin.close(socketFD)` here could double-close or close a
        // recycled fd that a still-queued I/O block is mid-syscall on.
        let fd = socketFD
        if fd >= 0 {
            ipcQueue.async { Darwin.close(fd) }
        }
        stateContinuation.finish()
        artworkContinuation.finish()
    }

    // MARK: - Public API

    /// Enables or disables the service.
    ///
    /// When enabled, immediately attempts to connect to Discord.
    /// When disabled, disconnects and stops polling.
    func setEnabled(_ enabled: Bool) async {
        isEnabled = enabled

        if enabled {
            await connectIfNeeded()
            startPolling()
        } else {
            stopPolling()
            reconnectTask?.cancel()
            reconnectTask = nil
            reconnectDelay = AppConstants.Discord.reconnectBaseDelay
            await performClearPresence()
            await disconnect()
        }
    }

    /// Tests the Discord IPC connection by attempting to connect if not already connected.
    ///
    /// If already connected, returns immediately with `true`. Otherwise triggers
    /// a connection attempt and returns whether it succeeded.
    func testConnection() async -> Bool {
        if state == .connected { return true }
        await connectIfNeeded()
        return state == .connected
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
    ///   - playlist: Current Apple Music playlist name (empty if none / unknown).
    ///   - duration: Total track duration in seconds (0 if unknown).
    ///   - elapsed: Elapsed time in seconds (0 if unknown).
    ///   - isPaused: `true` when the loaded track is paused. Discord has no
    ///     native paused flag, so when set we omit `timestamps` (stops the live
    ///     ticker) and swap `small_image` to a `pause` art asset with a
    ///     `"Paused"` tooltip. Track text stays unchanged.
    func updatePresence(
        track: String,
        artist: String,
        album: String,
        playlist: String,
        duration: TimeInterval = 0,
        elapsed: TimeInterval = 0,
        isPaused: Bool = false
    ) async {
        guard state == .connected else { return }

        // Check shared cache for immediate use (artwork + track links)
        let cached = ArtworkService.shared.cachedTrackLinks(track: track, artist: artist)
        await sendPresenceActivity(
            track: track, artist: artist, album: album, playlist: playlist,
            artworkURL: cached.artworkURL,
            duration: duration, elapsed: elapsed,
            appleMusicURL: cached.trackViewURL,
            songLinkURL: cached.songLinkURL,
            isPaused: isPaused
        )

        // Fetch track links asynchronously on cache miss
        if cached.artworkURL == nil {
            ArtworkService.shared.fetchTrackLinks(track: track, artist: artist) { [weak self] links in
                guard let self else { return }
                // Re-send if any link resolved. Buttons can appear even without artwork
                let hasNewData = links.artworkURL != nil
                    || links.trackViewURL != nil
                    || links.songLinkURL != nil
                guard hasNewData else { return }

                Task { [weak self] in
                    guard let self else { return }
                    await self.handleResolvedLinks(
                        track: track, artist: artist, album: album, playlist: playlist,
                        links: links, duration: duration, elapsed: elapsed,
                        isPaused: isPaused
                    )
                }
            }
        }
    }

    /// Updates the availability poll interval and restarts the timer if currently polling.
    ///
    /// - Parameter interval: New poll interval in seconds.
    func updatePollInterval(_ interval: TimeInterval) {
        currentPollInterval = interval
        if pollTask != nil {
            startPolling()
        }
    }

    /// Clears the Rich Presence (e.g., when playback stops).
    func clearPresence() async {
        await performClearPresence()
    }

    /// Shows the opt-in "Idle" activity used when nothing is playing and the
    /// user chose to keep WolfWave visible on their profile instead of clearing
    /// it. No track, timestamps, or buttons, just a static idle marker.
    func showIdleStatus() async {
        guard state == .connected else { return }
        // Idle has no track to re-send on a settings change.
        lastPresence = nil
        await sendActivityFrame(DiscordPresenceBuilder.buildIdleActivity())
    }

    // MARK: - Resolution Handling

    private func handleResolvedLinks(
        track: String,
        artist: String,
        album: String,
        playlist: String,
        links: TrackLinks,
        duration: TimeInterval,
        elapsed: TimeInterval,
        isPaused: Bool
    ) async {
        if state == .connected {
            await sendPresenceActivity(
                track: track, artist: artist, album: album, playlist: playlist,
                artworkURL: links.artworkURL,
                duration: duration, elapsed: elapsed,
                appleMusicURL: links.trackViewURL,
                songLinkURL: links.songLinkURL,
                isPaused: isPaused
            )
        }
        // Notify listeners (e.g., WebSocket server) only when artwork is resolved
        if let artworkURL = links.artworkURL {
            artworkContinuation.yield(
                ArtworkResolution(url: artworkURL, track: track, artist: artist)
            )
        }
    }

    // MARK: - Presence Helpers

    private func performClearPresence() async {
        lastPresence = nil
        guard state == .connected else { return }

        let payload: [String: Any] = [
            "cmd": "SET_ACTIVITY",
            "args": [
                "pid": pid,
            ],
            "nonce": UUID().uuidString,
        ]

        await sendFrame(opcode: .frame, payload: payload)
    }

    /// Builds and sends a SET_ACTIVITY frame with the given track metadata.
    ///
    /// - Parameters:
    ///   - track: Song title.
    ///   - artist: Artist name.
    ///   - album: Album name (used as large image tooltip).
    ///   - playlist: Current Apple Music playlist name (empty if none / unknown).
    ///   - artworkURL: Optional iTunes artwork URL. If nil, falls back to a source-specific
    ///     asset uploaded in the Discord Developer Portal.
    ///   - duration: Total track duration in seconds (0 if unknown).
    ///   - elapsed: Elapsed time in seconds (0 if unknown).
    private func sendPresenceActivity(
        track: String,
        artist: String,
        album: String,
        playlist: String,
        artworkURL: String?,
        duration: TimeInterval,
        elapsed: TimeInterval,
        appleMusicURL: String? = nil,
        songLinkURL: String? = nil,
        isPaused: Bool = false
    ) async {
        // Cache so settings changes can trigger a re-send without waiting for the next track.
        lastPresence = LastPresence(
            track: track, artist: artist, album: album, playlist: playlist,
            duration: duration, elapsed: elapsed,
            isPaused: isPaused,
            capturedAt: Date()
        )

        let activity = DiscordPresenceBuilder.buildActivity(
            track: track,
            artist: artist,
            album: album,
            playlist: playlist,
            artworkURL: artworkURL,
            duration: duration,
            elapsed: elapsed,
            appleMusicURL: appleMusicURL,
            songLinkURL: songLinkURL,
            isPaused: isPaused,
            defaults: .standard,
            now: Date()
        )

        await sendActivityFrame(activity)
    }

    /// Wraps an `activity` dictionary in a `SET_ACTIVITY` frame and sends it.
    private func sendActivityFrame(_ activity: [String: Any]) async {
        let payload: [String: Any] = [
            "cmd": "SET_ACTIVITY",
            "args": [
                "pid": pid,
                "activity": activity,
            ],
            "nonce": UUID().uuidString,
        ]

        await sendFrame(opcode: .frame, payload: payload)
    }

    /// Re-sends the most recent presence with current settings applied.
    ///
    /// Called when `discordPresenceSettingsChanged` fires (e.g. user toggled a button
    /// in settings). Re-uses cached `TrackLinks` via `ArtworkService.shared` so no
    /// network round-trip is required.
    private func resendLastPresence() async {
        guard state == .connected, let snap = lastPresence else { return }

        // Recompute elapsed from the captured timestamp so the progress bar stays accurate.
        let drift = Date().timeIntervalSince(snap.capturedAt)
        let elapsed = snap.duration > 0
            ? min(snap.elapsed + drift, snap.duration)
            : snap.elapsed

        let cached = ArtworkService.shared.cachedTrackLinks(track: snap.track, artist: snap.artist)
        await sendPresenceActivity(
            track: snap.track,
            artist: snap.artist,
            album: snap.album,
            playlist: snap.playlist,
            artworkURL: cached.artworkURL,
            duration: snap.duration,
            elapsed: elapsed,
            appleMusicURL: cached.trackViewURL,
            songLinkURL: cached.songLinkURL,
            isPaused: snap.isPaused
        )
    }

    // Presence payload + playlist-resolution builders (buildActivity,
    // buildIdleActivity, resolveButton, buttonKeys, PlaylistDisplay,
    // resolvePlaylistDisplay, stateLine, smallText) live in
    // DiscordPresenceBuilder.swift.

    // MARK: - Client ID Resolution

    /// Resolves the Discord Application ID from Info.plist or environment.
    ///
    /// Lookup order:
    /// 1. `DISCORD_CLIENT_ID` key in Info.plist (expanded from Config.xcconfig at build time)
    /// 2. `DISCORD_CLIENT_ID` environment variable (for dev/CI overrides)
    ///
    /// - Returns: The client ID string, or nil if not configured.
    nonisolated static func resolveClientID() -> String? {
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
    /// Widened from `private` so `connectIfNeeded` in `DiscordRPCService+IPC.swift`
    /// can call it across files.
    func tempDirectoryCandidates() -> [String] {
        var candidates: [String] = []

        // 1. Read the REAL TMPDIR from Discord's own process environment.
        //    sysctl(KERN_PROCARGS2) returns argv + environ for same-user processes
        //    and is NOT redirected by App Sandbox.
        //    Result is cached for `discordTmpDirTTL` seconds. Discord's TMPDIR
        //    doesn't change while it's running, so calling sysctl on every
        //    connect attempt is wasteful.
        let now = Date()
        let discordTmpDir: String?
        if let cached = cachedDiscordTmpDir, now.timeIntervalSince(cachedDiscordTmpDirAt) < discordTmpDirTTL {
            discordTmpDir = cached
        } else {
            discordTmpDir = readDiscordTmpDir()
            cachedDiscordTmpDir = discordTmpDir
            cachedDiscordTmpDirAt = now
        }

        if let discordTmpDir {
            let resolved = Self.resolveSymlinks(discordTmpDir)
            candidates.append(resolved)
        }

        // 2. confstr: works outside sandbox, returns container path inside sandbox.
        let len = confstr(_CS_DARWIN_USER_TEMP_DIR, nil, 0)
        if len > 0 {
            var buf = [CChar](repeating: 0, count: len)
            confstr(_CS_DARWIN_USER_TEMP_DIR, &buf, len)
            let bytes = buf.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }
            let resolved = Self.resolveSymlinks(String(decoding: bytes, as: UTF8.self))
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
    nonisolated private static func resolveSymlinks(_ path: String) -> String {
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
        let argc = buffer.withUnsafeBufferPointer { buf -> Int32 in
            guard let baseAddress = buf.baseAddress else { return 0 }
            return baseAddress.withMemoryRebound(to: Int32.self, capacity: 1) { $0.pointee }
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

        // strings[0] = exec path, strings[1..argc] = argv, rest = environment.
        // `argc >= 0` guards the `strings[i]` subscript below: a malformed
        // negative argc would otherwise produce a negative lower bound.
        guard argc >= 0 else { return nil }
        let envStart = 1 + Int(argc)
        guard envStart >= 0, envStart < strings.count else { return nil }

        for i in envStart..<strings.count {
            if strings[i].hasPrefix("TMPDIR=") {
                let value = String(strings[i].dropFirst(7))
                Log.debug("DiscordRPCService: Read TMPDIR from Discord process: \(value)", category: "Discord")
                return value
            }
        }

        return nil
    }

    // IPC connection, frame I/O, and reconnection (connectIfNeeded,
    // openIPCSocket, performHandshake, disconnect, runOnIPCQueue,
    // setSocketTimeouts, WriteResult/ReadResult, writeFully, readFully, closeFD,
    // sendFrame, readFrame, decodeFramePayload, nextBackoff, handleConnectionLost,
    // attemptReconnect) live in DiscordRPCService+IPC.swift.

    // MARK: - Polling

    /// Starts polling for Discord availability when not connected.
    private func startPolling() {
        stopPolling()

        let interval = currentPollInterval
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                // Availability polling tolerates coarse timing, allow 10%
                // tolerance so the wakeup coalesces with other timers.
                try? await Task.sleep(for: .seconds(interval), tolerance: .seconds(interval * 0.1))
                guard !Task.isCancelled, let self else { return }
                await self.pollTick()
            }
        }
    }

    private func pollTick() async {
        guard isEnabled, state == .disconnected else { return }
        await connectIfNeeded()
    }

    /// Stops the availability poll timer.
    private func stopPolling() {
        pollTask?.cancel()
        pollTask = nil
    }
}
