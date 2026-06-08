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
    private(set) var state: ConnectionState = .disconnected {
        didSet {
            guard oldValue != state else { return }
            _stateSnapshot.set(state)
            stateContinuation.yield(state)
        }
    }

    /// Discord Application ID resolved from Info.plist / environment.
    private let clientID: String

    /// File descriptor for the connected Unix domain socket, or -1.
    private var socketFD: Int32 = -1

    /// Monotonic token bumped on every disconnect/teardown.
    ///
    /// `connectIfNeeded` captures this before awaiting the off-actor
    /// `openIPCSocket` hop. If a `setEnabled(false)` (or any other teardown)
    /// lands during that await, the generation changes; the connect then closes
    /// the just-opened fd on ``ipcQueue`` and bails without committing
    /// `socketFD`/`state`, so an in-flight connect can never win after a disable.
    private var connectionGeneration: UInt64 = 0

    /// Dedicated serial queue for the blocking socket syscalls.
    ///
    /// `connect`, `read`, `write`, and `setsockopt` block the calling thread.
    /// Running them here (instead of on the actor's serial executor) keeps a
    /// stalled handshake or slow peer from parking the actor. The queue is
    /// serial, so the connection lifecycle stays single-threaded. There is
    /// never concurrent access to `socketFD` from two IPC operations at once.
    private nonisolated let ipcQueue = DispatchQueue(label: "com.mrdemonwolf.wolfwave.discord-ipc")

    /// Current reconnect delay (doubles on each failure, capped).
    private var reconnectDelay: TimeInterval = AppConstants.Discord.reconnectBaseDelay

    /// Active polling task (availability checks while disconnected).
    private var pollTask: Task<Void, Never>?

    /// Active reconnect task (scheduled after a connection loss).
    private var reconnectTask: Task<Void, Never>?

    /// Current availability poll interval (may be widened in reduced-power mode).
    private var currentPollInterval: TimeInterval = AppConstants.Discord.availabilityPollInterval

    /// Whether the service is enabled by the user.
    private var isEnabled = false

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
        await sendActivityFrame(Self.buildIdleActivity())
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

        let activity = Self.buildActivity(
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

    // MARK: - Payload Builder (internal for testing)

    /// Builds the Discord `activity` payload dictionary from track metadata + user settings.
    ///
    /// Pure function. No socket I/O, no instance state. Exposed `internal` so unit
    /// tests can drive it directly with isolated `UserDefaults` suites.
    ///
    /// - Parameters:
    ///   - playlist: Current Apple Music playlist name (empty if none / unknown).
    ///   - now: Injected clock for deterministic timestamps in tests.
    nonisolated static func buildActivity(
        track: String,
        artist: String,
        album: String,
        playlist: String = "",
        artworkURL: String?,
        duration: TimeInterval,
        elapsed: TimeInterval,
        appleMusicURL: String?,
        songLinkURL: String?,
        isPaused: Bool = false,
        defaults: UserDefaults,
        now: Date
    ) -> [String: Any] {
        let playlistDisplay = resolvePlaylistDisplay(
            playlist: playlist, album: album, defaults: defaults
        )
        let style = DiscordPlaylistStyle.resolved(
            from: defaults.string(forKey: AppConstants.UserDefaults.discordPlaylistStyle)
        )

        var activity: [String: Any] = [
            "type": AppConstants.Discord.listeningActivityType,
            "details": track,
            "state": stateLine(artist: artist, playlist: playlistDisplay, style: style),
        ]

        let largeImage = artworkURL ?? AppConstants.Discord.artAssetAppleMusic
        // When paused: swap the small badge to the "pause" art asset (uploaded
        // to the Discord developer portal under Rich Presence > Art Assets) and
        // override the tooltip. Source-of-truth keeps `large_image` intact so
        // album art still shows.
        let smallImageKey = isPaused ? AppConstants.Discord.artAssetPause : AppConstants.Discord.artAssetAppleMusic
        let smallTextValue = isPaused ? "Paused" : smallText(playlist: playlistDisplay, style: style)
        activity["assets"] = [
            "large_image": largeImage,
            "large_text": album,
            "small_image": smallImageKey,
            "small_text": smallTextValue,
        ]

        // Discord has no native paused flag. Omitting `timestamps` stops the
        // live ticker on the client so it doesn't keep counting up past the
        // real elapsed value while the user is paused. Resumes will rebuild
        // the timestamps from the next non-paused update.
        if duration > 0 && !isPaused {
            let nowEpoch = now.timeIntervalSince1970
            let start = nowEpoch - elapsed
            let end = start + duration
            activity["timestamps"] = [
                "start": Int(start * 1000),
                "end": Int(end * 1000),
            ]
        }

        var buttons: [[String: String]] = []
        if let btn = resolveButton(index: 1, url: appleMusicURL, defaults: defaults) {
            buttons.append(btn)
        }
        if let btn = resolveButton(index: 2, url: songLinkURL, defaults: defaults) {
            buttons.append(btn)
        }
        if !buttons.isEmpty {
            activity["buttons"] = buttons
        }

        return activity
    }

    /// Builds the minimal opt-in "Idle" activity payload (no track, timestamps,
    /// or buttons). Pure function. No socket I/O, no instance state. Exposed
    /// `internal` so unit tests can assert its shape.
    nonisolated static func buildIdleActivity() -> [String: Any] {
        // Large image is the WolfWave logo (not the Apple Music note) so the
        // idle marker is visually distinct from active playback, with Apple
        // Music demoted to the small source badge. Requires the `wolfwave` art
        // asset to be uploaded to the Discord portal.
        [
            "type": AppConstants.Discord.listeningActivityType,
            "details": AppConstants.Discord.idleDetails,
            "state": AppConstants.Discord.idleState,
            "assets": [
                "large_image": AppConstants.Discord.artAssetWolfWave,
                "large_text": "WolfWave",
                "small_image": AppConstants.Discord.artAssetAppleMusic,
                "small_text": AppConstants.Discord.idleSmallText,
            ],
        ]
    }

    /// Resolves a button payload from settings + a candidate URL.
    ///
    /// Returns nil when the user disabled the button, the URL is missing, or the
    /// label resolves to empty after trimming. Custom labels override defaults;
    /// empty stored label means "use the default". Labels are trimmed and
    /// truncated to `buttonLabelMaxLength` defensively.
    ///
    /// - Parameter index: 1 or 2.
    nonisolated static func resolveButton(
        index: Int,
        url: String?,
        defaults: UserDefaults
    ) -> [String: String]? {
        guard let url, !url.isEmpty else { return nil }
        guard let keys = buttonKeys(for: index) else { return nil }

        // Missing key defaults to enabled (true).
        let enabled = (defaults.object(forKey: keys.enabled) as? Bool) ?? true
        guard enabled else { return nil }

        let stored = (defaults.string(forKey: keys.label) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let resolved = stored.isEmpty ? keys.defaultLabel : stored
        let truncated = String(resolved.prefix(AppConstants.Discord.buttonLabelMaxLength))
        guard !truncated.isEmpty else { return nil }

        return ["label": truncated, "url": url]
    }

    /// Maps a button index to its enabled/label `UserDefaults` keys and default
    /// label. Returns nil for any index other than 1 or 2.
    private nonisolated static func buttonKeys(
        for index: Int
    ) -> (enabled: String, label: String, defaultLabel: String)? {
        switch index {
        case 1:
            return (
                AppConstants.UserDefaults.discordButton1Enabled,
                AppConstants.UserDefaults.discordButton1Label,
                AppConstants.Discord.defaultButton1Label
            )
        case 2:
            return (
                AppConstants.UserDefaults.discordButton2Enabled,
                AppConstants.UserDefaults.discordButton2Label,
                AppConstants.Discord.defaultButton2Label
            )
        default:
            return nil
        }
    }

    // MARK: - Playlist Resolution

    /// The outcome of resolving the current playlist for presence display.
    enum PlaylistDisplay: Equatable, Sendable {
        /// Show the playlist's real name.
        case named(String)
        /// A playlist is active but the user opted not to reveal its name.
        case anonymous
    }

    /// Resolves how the current playlist should be displayed, or `nil` to hide it.
    ///
    /// Returns `nil` when the playlist feature is disabled, the name is empty, a
    /// generic container (`Library` / `Music` / `Apple Music`), or identical to
    /// the album, so the card never surfaces a non-playlist as a playlist.
    /// When `discordPlaylistShowName` is off, returns `.anonymous` so the
    /// listening context survives without leaking the playlist's name.
    nonisolated static func resolvePlaylistDisplay(
        playlist: String,
        album: String,
        defaults: UserDefaults
    ) -> PlaylistDisplay? {
        guard defaults.bool(forKey: AppConstants.UserDefaults.discordPlaylistEnabled) else {
            return nil
        }

        let name = playlist.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return nil }

        let folded = name.lowercased()
        guard !AppConstants.Discord.genericPlaylistNames.contains(folded) else { return nil }
        guard folded != album.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() else {
            return nil
        }

        // Missing key defaults to revealing the name (true).
        let showName = (defaults.object(forKey: AppConstants.UserDefaults.discordPlaylistShowName) as? Bool) ?? true
        return showName ? .named(name) : .anonymous
    }

    /// Builds the activity `state` line, appending the playlist for `.artistLine` style.
    nonisolated static func stateLine(
        artist: String,
        playlist: PlaylistDisplay?,
        style: DiscordPlaylistStyle
    ) -> String {
        let cap = AppConstants.Discord.activityTextMaxLength
        guard style == .artistLine, let playlist else {
            return String(artist.prefix(cap))
        }
        let label: String
        switch playlist {
        case .named(let name): label = name
        case .anonymous:       label = AppConstants.Discord.playlistAnonymousLabel
        }
        let joined = artist.isEmpty
            ? label
            : artist + AppConstants.Discord.playlistSeparator + label
        return String(joined.prefix(cap))
    }

    /// Builds the small-icon tooltip text, describing the playlist for `.iconTooltip` style.
    nonisolated static func smallText(
        playlist: PlaylistDisplay?,
        style: DiscordPlaylistStyle
    ) -> String {
        guard style == .iconTooltip, let playlist else { return "Apple Music" }
        switch playlist {
        case .named(let name):
            let text = AppConstants.Discord.playlistTooltipPrefix
                + AppConstants.Discord.playlistSeparator + name
            return String(text.prefix(AppConstants.Discord.activityTextMaxLength))
        case .anonymous:
            return AppConstants.Discord.playlistAnonymousTooltip
        }
    }

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
    private func tempDirectoryCandidates() -> [String] {
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

    // MARK: - Connection

    /// Attempts to connect to Discord's IPC socket.
    ///
    /// Tries each candidate temp directory, and within each, tries sockets 0 through 9.
    /// Keeps the first successful connection.
    private func connectIfNeeded() async {
        guard state == .disconnected else { return }
        guard !clientID.isEmpty else {
            Log.warn("DiscordRPCService: No client ID configured: skipping connection", category: "Discord")
            return
        }

        state = .connecting

        let candidates = tempDirectoryCandidates()
        guard !candidates.isEmpty else {
            Log.error("DiscordRPCService: Cannot determine any temp directory", category: "Discord")
            state = .disconnected
            return
        }

        for basePath in candidates {
            Log.debug("DiscordRPCService: Searching for IPC socket in \(basePath)", category: "Discord")

            for slot in 0..<AppConstants.Discord.ipcSocketSlots {
                let socketPath = URL(filePath: basePath)
                    .appending(path: "\(AppConstants.Discord.ipcSocketPrefix)\(slot)")
                    .path(percentEncoded: false)

                // The blocking `connect()` (plus the socket setup and timeout
                // opts it gates) runs off the actor executor on `ipcQueue`. On
                // success it returns the ready fd with timeouts applied; on
                // failure it returns -1 after closing any partial fd. The actor
                // only records the result and runs the handshake.
                //
                // Capture the generation BEFORE the await. If a disconnect /
                // teardown bumps it (or the service is disabled) while the open
                // is in flight, close the just-opened fd on `ipcQueue` and bail
                // without committing `socketFD`/`state`, so a stale connect can
                // never overwrite a fresh teardown.
                let generation = connectionGeneration
                let fd = await runOnIPCQueue { Self.openIPCSocket(at: socketPath, slot: slot) }
                guard fd >= 0 else { continue }

                guard isEnabled, connectionGeneration == generation, state == .connecting else {
                    await runOnIPCQueue { Self.closeFD(fd) }
                    return
                }

                socketFD = fd
                if await performHandshake() {
                    state = .connected
                    reconnectDelay = AppConstants.Discord.reconnectBaseDelay
                    return
                } else {
                    Log.warn("DiscordRPCService: Handshake failed on slot \(slot)", category: "Discord")
                    // performHandshake may have already torn down via
                    // handleConnectionLost -> disconnect(), which closes the fd
                    // and resets socketFD to -1. Only close here if the fd is
                    // still ours; otherwise we'd double-close (EBADF, and a
                    // recycled fd could be hit in edge cases).
                    if socketFD == fd {
                        await runOnIPCQueue { Self.closeFD(fd) }
                        socketFD = -1
                    }
                }
            }
        }

        Log.debug("DiscordRPCService: No active IPC socket found in any candidate directory", category: "Discord")
        state = .disconnected
    }

    /// Opens, connects, and applies timeouts to a Unix-domain socket at
    /// `socketPath`. Pure of actor state so it can run on ``ipcQueue`` (where the
    /// blocking `connect()` belongs). Returns the connected fd with send/receive
    /// timeouts applied, or -1 on any failure (closing any partial fd first).
    /// `slot` is used only for logging.
    private nonisolated static func openIPCSocket(at socketPath: String, slot: Int) -> Int32 {
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { return -1 }

        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)

        let pathBytes = socketPath.utf8CString
        guard pathBytes.count <= MemoryLayout.size(ofValue: addr.sun_path) else {
            Darwin.close(fd)
            return -1
        }

        withUnsafeMutablePointer(to: &addr.sun_path) { sunPathPtr in
            sunPathPtr.withMemoryRebound(to: CChar.self, capacity: pathBytes.count) { dest in
                pathBytes.withUnsafeBufferPointer { src in
                    guard let srcBase = src.baseAddress else { return }
                    _ = memcpy(dest, srcBase, pathBytes.count)
                }
            }
        }

        let addrLen = socklen_t(MemoryLayout<sockaddr_un>.size)
        let result = withUnsafePointer(to: &addr) { addrPtr in
            addrPtr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPtr in
                Darwin.connect(fd, sockaddrPtr, addrLen)
            }
        }

        guard result == 0 else {
            let err = errno
            Log.debug("DiscordRPCService: connect() failed on slot \(slot): errno \(err) (\(String(cString: strerror(err))))", category: "Discord")
            Darwin.close(fd)
            return -1
        }

        setSocketTimeouts(fd)
        return fd
    }

    /// Sends the RPC handshake (opcode 0) with the client ID.
    ///
    /// - Returns: True if handshake was sent and a response was received.
    private func performHandshake() async -> Bool {
        let handshake: [String: Any] = [
            "v": AppConstants.Discord.rpcVersion,
            "client_id": clientID,
        ]

        guard await sendFrame(opcode: .handshake, payload: handshake) else {
            return false
        }

        // Read the READY response
        guard let (opcode, _) = await readFrame() else {
            Log.warn("DiscordRPCService: No handshake response", category: "Discord")
            return false
        }

        if opcode == Opcode.close.rawValue {
            Log.warn("DiscordRPCService: Received CLOSE during handshake", category: "Discord")
            return false
        }

        return true
    }

    /// Disconnects from the IPC socket.
    ///
    /// Bumps ``connectionGeneration`` so any in-flight connect that resumes after
    /// this teardown discards its fd instead of committing it. The close runs on
    /// ``ipcQueue`` so it serializes after any queued read/write still holding the
    /// captured fd, never racing them or closing a recycled descriptor.
    private func disconnect() async {
        connectionGeneration &+= 1

        guard socketFD >= 0 else {
            if state != .disconnected { state = .disconnected }
            return
        }
        let fd = socketFD
        socketFD = -1
        state = .disconnected
        await runOnIPCQueue { Self.closeFD(fd) }
    }

    // MARK: - Frame I/O

    /// Suspends the actor and runs `work` on ``ipcQueue``, resuming with its result.
    ///
    /// This is the bridge that keeps the blocking socket syscalls off the actor's
    /// serial executor. `work` runs on the dedicated serial `ipcQueue`; the actor
    /// `await`s the continuation, so a stalled `read`/`write`/`connect` parks only
    /// the queue's worker thread, never the actor. Because `ipcQueue` is serial,
    /// only one such block runs at a time, preserving single-threaded socket
    /// access. `work` must be self-contained: it takes only `Sendable` inputs and
    /// touches no actor state, so the hop is safe.
    private nonisolated func runOnIPCQueue<T: Sendable>(
        _ work: @escaping @Sendable () -> T
    ) async -> T {
        await withCheckedContinuation { continuation in
            ipcQueue.async {
                continuation.resume(returning: work())
            }
        }
    }

    /// Applies send/receive timeouts to the IPC socket.
    ///
    /// The frame I/O uses blocking `Darwin.read`/`Darwin.write` on ``ipcQueue``.
    /// Without a timeout, a Discord peer that stalls mid-frame (or stops draining
    /// its receive buffer) would block the queue's worker thread forever.
    /// `SO_RCVTIMEO`/`SO_SNDTIMEO` make a stalled read/write fail with `EAGAIN`,
    /// which the frame I/O treats as a lost connection. Pure: no actor state.
    private nonisolated static func setSocketTimeouts(_ fd: Int32) {
        var tv = timeval(tv_sec: AppConstants.Discord.socketTimeoutSeconds, tv_usec: 0)
        let size = socklen_t(MemoryLayout<timeval>.size)
        _ = setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, size)
        _ = setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &tv, size)
    }

    /// Result of a blocking write, carrying the failing `errno` captured on the
    /// same `ipcQueue` worker thread that ran the syscall.
    ///
    /// `errno` is thread-local, so it must be read inside the queue closure (right
    /// after the failing syscall) rather than back on the actor executor where it
    /// reflects unrelated work. `errno` is meaningful only when `ok == false`.
    struct WriteResult: Sendable {
        let ok: Bool
        let errno: Int32
    }

    /// Result of a blocking read, carrying the bytes (nil on failure) plus the
    /// failing `errno` captured on the `ipcQueue` worker thread. `errno` is
    /// meaningful only when `data == nil`.
    struct ReadResult: Sendable {
        let data: Data?
        let errno: Int32
    }

    /// Writes all of `data` to socket `fd`, looping over partial writes.
    ///
    /// A stream socket may accept fewer bytes than requested per `write`, so a
    /// single call can't be assumed to flush the whole frame. Returns `ok: false`
    /// (with the captured `errno`) if the socket errors or times out before
    /// everything is written. The `errno` is read on this worker thread so it
    /// reflects the actual failure, not later actor-executor work. Pure of actor
    /// state (takes `fd` explicitly) so it can run on ``ipcQueue``.
    private nonisolated static func writeFully(_ data: Data, fd: Int32) -> WriteResult {
        guard !data.isEmpty else { return WriteResult(ok: true, errno: 0) }
        return data.withUnsafeBytes { raw -> WriteResult in
            guard let base = raw.baseAddress else { return WriteResult(ok: false, errno: 0) }
            var total = 0
            while total < data.count {
                let n = Darwin.write(fd, base + total, data.count - total)
                if n > 0 {
                    total += n
                } else if n < 0 && errno == EINTR {
                    continue
                } else {
                    return WriteResult(ok: false, errno: errno)
                }
            }
            return WriteResult(ok: true, errno: 0)
        }
    }

    /// Reads exactly `count` bytes from socket `fd`, looping over partial reads.
    ///
    /// A stream socket may return fewer bytes than requested per `read`, so a
    /// single call can't be assumed to fill the buffer. Returns `data: nil` (with
    /// the captured `errno`) if the peer closes (`read` returns 0) or the socket
    /// errors/times out before `count` bytes arrive. The `errno` is read on this
    /// worker thread so it reflects the actual failure, not later actor-executor
    /// work. A clean peer close (`read` returns 0) leaves `errno == 0`. Pure of
    /// actor state (takes `fd` explicitly) so it can run on ``ipcQueue``.
    private nonisolated static func readFully(_ count: Int, fd: Int32) -> ReadResult {
        guard count > 0 else { return ReadResult(data: Data(), errno: 0) }
        var buffer = Data(count: count)
        var failErrno: Int32 = 0
        let ok = buffer.withUnsafeMutableBytes { raw -> Bool in
            guard let base = raw.baseAddress else { return false }
            var total = 0
            while total < count {
                let n = Darwin.read(fd, base + total, count - total)
                if n > 0 {
                    total += n
                } else if n < 0 && errno == EINTR {
                    continue
                } else {
                    // peer closed (n == 0, errno stays 0) or error/timeout (n < 0)
                    failErrno = n < 0 ? errno : 0
                    return false
                }
            }
            return true
        }
        return ok ? ReadResult(data: buffer, errno: 0) : ReadResult(data: nil, errno: failErrno)
    }

    /// Closes `fd` on ``ipcQueue`` so the close serializes after any queued
    /// read/write on the same descriptor. Pure of actor state. A no-op for a
    /// negative `fd`. Closing on the queue (never on the actor executor) prevents
    /// a double-close or closing a recycled descriptor while an in-flight
    /// `readFully`/`writeFully` still holds the captured fd value.
    private nonisolated static func closeFD(_ fd: Int32) {
        guard fd >= 0 else { return }
        Darwin.close(fd)
    }

    /// Sends a framed message to Discord.
    ///
    /// Frame format: `[opcode: UInt32 LE][length: UInt32 LE][JSON payload]`
    ///
    /// - Parameters:
    ///   - opcode: The IPC opcode.
    ///   - payload: Dictionary to serialize as JSON.
    /// - Returns: True if the write succeeded.
    @discardableResult
    private func sendFrame(opcode: Opcode, payload: [String: Any]) async -> Bool {
        let fd = socketFD
        guard fd >= 0 else { return false }

        // `isValidJSONObject` short-circuits before `data(withJSONObject:)`, so a
        // non-JSON leaf (NaN/Inf Double, non-String key) returns false instead of
        // raising an ObjC `NSInvalidArgumentException` that `try?` cannot catch.
        guard JSONSerialization.isValidJSONObject(payload),
              let jsonData = try? JSONSerialization.data(withJSONObject: payload) else {
            Log.error("DiscordRPCService: Failed to serialize payload", category: "Discord")
            return false
        }

        var header = Data(count: 8)
        header.withUnsafeMutableBytes { buf in
            buf.storeBytes(of: opcode.rawValue.littleEndian, toByteOffset: 0, as: UInt32.self)
            buf.storeBytes(of: UInt32(jsonData.count).littleEndian, toByteOffset: 4, as: UInt32.self)
        }

        // Blocking write runs off the actor executor on `ipcQueue`. The frame is
        // fully built here, so the closure only flushes bytes to `fd`. The
        // `errno` is captured inside the closure (on the worker thread) so it
        // reflects the actual write failure, not unrelated actor-executor work.
        let frame = header + jsonData
        let result = await runOnIPCQueue { Self.writeFully(frame, fd: fd) }
        guard result.ok else {
            let err = result.errno
            Log.error("DiscordRPCService: Write failed/timed out with errno \(err) (\(String(cString: strerror(err))))", category: "Discord")
            await handleConnectionLost()
            return false
        }

        return true
    }

    /// Reads a single framed message from Discord.
    ///
    /// - Returns: Tuple of (opcode, JSON payload) or nil on failure.
    private func readFrame() async -> (UInt32, [String: Any]?)? {
        let fd = socketFD
        guard fd >= 0 else { return nil }

        // Blocking reads run off the actor executor on `ipcQueue`. The queue is
        // serial, so the header read always completes before the body read, and
        // no other IPC operation interleaves on `fd`. The `errno` is captured
        // inside the closure (on the worker thread) so it reflects the actual
        // read failure, not unrelated actor-executor work.
        let headerResult = await runOnIPCQueue { Self.readFully(8, fd: fd) }
        guard let headerBuf = headerResult.data else {
            let err = headerResult.errno
            Log.error("DiscordRPCService: Header read failed/timed out with errno \(err) (\(String(cString: strerror(err))))", category: "Discord")
            return nil
        }

        let opcode = headerBuf.withUnsafeBytes { buf in
            UInt32(littleEndian: buf.load(fromByteOffset: 0, as: UInt32.self))
        }
        let length = headerBuf.withUnsafeBytes { buf in
            UInt32(littleEndian: buf.load(fromByteOffset: 4, as: UInt32.self))
        }

        guard length > 0 else { return (opcode, nil) }
        guard length < AppConstants.Discord.maxIPCFrameBytes else {
            Log.warn("DiscordRPCService: Oversized IPC frame (\(length) bytes); disconnecting", category: "Discord")
            return nil
        }

        let bodyLength = Int(length)
        let bodyResult = await runOnIPCQueue { Self.readFully(bodyLength, fd: fd) }
        guard let bodyBuf = bodyResult.data else {
            let err = bodyResult.errno
            Log.error("DiscordRPCService: Body read failed/timed out with errno \(err) (\(String(cString: strerror(err))))", category: "Discord")
            return nil
        }

        let json = Self.decodeFramePayload(bodyBuf)
        return (opcode, json)
    }

    /// Decodes a Discord IPC frame body into a JSON object, or nil if the bytes
    /// aren't a JSON object. Pure and static so it's unit-testable without a live
    /// socket. `JSONSerialization.jsonObject(with:)` throws (caught by `try?`) on
    /// malformed input and never raises, so a hostile or garbled frame can't crash.
    static func decodeFramePayload(_ data: Data) -> [String: Any]? {
        (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }

    // MARK: - Reconnection

    /// Computes the next exponential-backoff delay: doubles `current` and clamps
    /// to `max`. Pure and `nonisolated` so the backoff math is unit-testable
    /// without the actor. Reset is just `base` (see `reconnectBaseDelay`).
    nonisolated static func nextBackoff(
        _ current: TimeInterval, base: TimeInterval, max: TimeInterval
    ) -> TimeInterval {
        Swift.min(current * 2, max)
    }

    /// Handles a lost connection by disconnecting and scheduling reconnect.
    private func handleConnectionLost() async {
        await disconnect()

        guard isEnabled else { return }

        let delay = reconnectDelay
        Log.info("DiscordRPCService: Scheduling reconnect in \(delay)s", category: "Discord")
        reconnectTask?.cancel()
        reconnectTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled, let self else { return }
            await self.attemptReconnect()
        }

        reconnectDelay = Self.nextBackoff(
            reconnectDelay,
            base: AppConstants.Discord.reconnectBaseDelay,
            max: AppConstants.Discord.reconnectMaxDelay)
    }

    private func attemptReconnect() async {
        guard isEnabled else { return }
        await connectIfNeeded()
    }

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
