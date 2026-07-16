//
//  SongRequestService.swift
//  WolfWave
//
//  Created by Nathanial Henniges on 2026-04-15.
//  Copyright © 2026 MrDemonWolf, Inc. All rights reserved.
//

import AppKit
import Foundation
import MusicKit

/// Orchestrates the song request system.
///
/// Coordinates search resolution, blocklist checking, queue management,
/// and Apple Music playback via MusicKit. State is polled by the queue
/// settings view via a refresh timer, so this type does not adopt the
/// `@Observable` macro.
final class SongRequestService {
    // MARK: - Types

    /// Result of processing a song request.
    enum RequestResult {
        case added(item: SongRequestItem, position: Int)
        /// Approval mode is on: the request is held for the streamer to approve or
        /// reject before it reaches the live queue.
        case pendingApproval(item: SongRequestItem)
        case queueFull(max: Int)
        case userLimitReached(max: Int)
        case alreadyInQueue
        case blocked
        case notFound(query: String)
        case linkNotFound
        case notAuthorized
        /// The song-request feature's master toggle is off. No request of any
        /// kind (chat, channel points, bits) is accepted.
        case featureDisabled
        case error(String)
    }

    // MARK: - Properties

    let queue: SongRequestQueue
    let blocklist: SongBlocklist
    let musicController: any AppleMusicControlling
    let searchResolver: SongSearchResolver

    /// Who may request a song via the `!sr` chat command.
    var chatAudience: RequestAudience {
        let raw = Foundation.UserDefaults.standard.string(forKey: AppConstants.UserDefaults.songRequestChatAudience)
        return RequestAudience(rawValue: raw ?? "") ?? .everyone
    }

    /// One-time migration of the legacy `songRequestSubscriberOnly` boolean to
    /// the `songRequestChatAudience` setting. No-op once the new key exists.
    static func migrateAccessSettings(defaults: Foundation.UserDefaults = .standard) {
        guard defaults.string(forKey: AppConstants.UserDefaults.songRequestChatAudience) == nil else { return }
        let legacySubOnly = defaults.bool(forKey: AppConstants.UserDefaults.songRequestSubscriberOnly)
        let audience: RequestAudience = legacySubOnly ? .subscribers : .everyone
        defaults.set(audience.rawValue, forKey: AppConstants.UserDefaults.songRequestChatAudience)
    }

    // MARK: - Setup Gate & Playlist Health

    /// One-time grandfather of the setup gate. Anyone who already had song
    /// requests turned on (or a song-list link configured) before the guided
    /// setup existed is marked complete, so the update never bounces an existing
    /// streamer back through setup. No-op once `songRequestSetupComplete` has
    /// been written. Mirrors `migrateAccessSettings`.
    static func migrateSetupState(defaults: Foundation.UserDefaults = .standard) {
        guard defaults.object(forKey: AppConstants.UserDefaults.songRequestSetupComplete) == nil else { return }
        let alreadyEnabled = defaults.bool(forKey: AppConstants.UserDefaults.songRequestEnabled)
        let link = defaults.string(forKey: AppConstants.UserDefaults.songRequestSongListURL) ?? ""
        let hasLink = !link.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        if alreadyEnabled || hasLink {
            defaults.set(true, forKey: AppConstants.UserDefaults.songRequestSetupComplete)
        }
        // Fresh installs are left unset (false) so they go through the wizard.
    }

    /// The fallback to apply after a health check. Pure data so the policy is
    /// unit-testable without touching UserDefaults or the network.
    struct HealthOutcome: Equatable {
        /// Status written to `songRequestPlaylistStatus` (drives the banner).
        var status: PlaylistSetupStatus
        /// Turn off `!playlist` (cosmetic link break).
        var disableLink = false
        /// Re-engage the setup gate and stop the feature (essential break).
        var reEngageGate = false
        /// Write a refreshed public share URL when the playlist was republished.
        var updatedShareURL: String?
    }

    /// Maps a playlist probe to the fallback policy. Returns `nil` for an
    /// unreachable API so a network blip never clears a real banner or flips a
    /// toggle. Pure: the only inputs are the probe and the currently stored link.
    ///
    /// - `.missing` is an essential break (the rebuild attempt already failed by
    ///   the time the caller passes `.missing` here) so it re-engages the gate.
    /// - `.notPublic` only matters when a link was stored; then it's a cosmetic
    ///   `!playlist` break. With no stored link, a private playlist is fine.
    /// - `.ok` refreshes the stored link if the public URL changed (republished).
    static func resolveHealth(
        probe: AppleMusicLibraryService.PlaylistProbe,
        storedShareURL: String
    ) -> HealthOutcome? {
        let trimmed = storedShareURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let hasLink = !trimmed.isEmpty
        switch probe {
        case .unreachable:
            return nil
        case .missing:
            return HealthOutcome(status: .playlistMissing, reEngageGate: true)
        case .notPublic:
            return hasLink
                ? HealthOutcome(status: .linkUnshared, disableLink: true)
                : HealthOutcome(status: .ok)
        case .ok(let url):
            if hasLink, let url, url != trimmed {
                return HealthOutcome(status: .ok, updatedShareURL: url)
            }
            return HealthOutcome(status: .ok)
        }
    }

    /// Checks that the song-request playlist setup is still healthy and applies
    /// the fallback when it is not. Safe to call on launch and whenever the pane
    /// appears.
    ///
    /// Order of checks, cheapest and most essential first: setup not finished →
    /// nothing to police; Apple Music access lost → prompt a re-grant; otherwise
    /// probe the playlist (rebuilding it once if it was deleted) and resolve the
    /// link state. An unreachable API changes nothing.
    func runSetupHealthCheck() async {
        let defaults = Foundation.UserDefaults.standard

        // Before setup is finished the pane shows the "Set up" call to action,
        // not a banner, so there is nothing to police yet.
        guard defaults.bool(forKey: AppConstants.UserDefaults.songRequestSetupComplete) else {
            setPlaylistStatus(.ok)
            return
        }

        // Apple Music access is the first essential. Non-destructive: requests
        // already guard on auth, and re-granting clears this on the next check.
        guard musicController.isAuthorized else {
            applyHealth(HealthOutcome(status: .musicAccessLost))
            return
        }

        let library = AppleMusicLibraryService()
        let storedURL = defaults.string(forKey: AppConstants.UserDefaults.songRequestSongListURL) ?? ""
        var probe = await library.probeRequestsPlaylist()

        // A deleted playlist self-heals: rebuild it once before treating the loss
        // as an essential break. After a rebuild the new playlist is private, so
        // re-probe to capture the (not-yet-public) link state.
        if case .missing = probe {
            library.resetCachedPlaylistID()
            if (try? await library.ensureRequestsPlaylist()) != nil {
                probe = await library.probeRequestsPlaylist()
            }
        }

        guard let outcome = Self.resolveHealth(probe: probe, storedShareURL: storedURL) else { return }
        applyHealth(outcome)
    }

    /// Persists a `HealthOutcome`: updates a refreshed link, turns off `!playlist`
    /// on a cosmetic break, re-engages the gate and stops the feature on an
    /// essential break, then records the status that drives the banner.
    private func applyHealth(_ outcome: HealthOutcome) {
        let defaults = Foundation.UserDefaults.standard
        if let updated = outcome.updatedShareURL {
            defaults.set(updated, forKey: AppConstants.UserDefaults.songRequestSongListURL)
        }
        if outcome.disableLink {
            defaults.set(false, forKey: AppConstants.UserDefaults.songListCommandEnabled)
        }
        if outcome.reEngageGate {
            defaults.set(false, forKey: AppConstants.UserDefaults.songRequestSetupComplete)
            defaults.set(false, forKey: AppConstants.UserDefaults.songRequestEnabled)
            NotificationCenter.default.postEnabled(.songRequestSettingChanged, enabled: false)
            Log.info("SongRequestService: Playlist setup broke; re-engaging setup gate", category: "SongRequest")
        }
        setPlaylistStatus(outcome.status)
    }

    /// Writes the playlist health status that backs the pane's `@AppStorage`
    /// banner. Only writes on a change to avoid waking observers needlessly.
    private func setPlaylistStatus(_ status: PlaylistSetupStatus) {
        let defaults = Foundation.UserDefaults.standard
        let key = AppConstants.UserDefaults.songRequestPlaylistStatus
        guard defaults.string(forKey: key) != status.rawValue else { return }
        defaults.set(status.rawValue, forKey: key)
    }

    /// Whether the song-request feature's master toggle is on. Every request
    /// path (chat `!sr`, channel points, bits) is rejected when this is off, so
    /// the per-command and per-redemption toggles can't accept requests on their
    /// own while the feature as a whole is disabled.
    var isFeatureEnabled: Bool {
        FeatureFlags.songRequestEnabled
    }

    var isAutoAdvanceEnabled: Bool {
        Preferences.bool(AppConstants.UserDefaults.songRequestAutoAdvance, default: true)
    }

    /// Whether resolved requests wait in a holding pen for the streamer to approve
    /// before they reach the live queue. Off by default: requests auto-queue.
    var isApprovalRequired: Bool {
        Preferences.bool(AppConstants.UserDefaults.songRequestApprovalRequired, default: false)
    }

    /// Whether Apple Music's own autoplay should keep going once the request
    /// queue empties (when no fallback playlist is configured). Off means the
    /// stream goes silent on an empty queue.
    var isAutoplayWhenEmptyEnabled: Bool {
        Preferences.bool(AppConstants.UserDefaults.songRequestAutoplayWhenEmpty, default: true)
    }

    var isHoldEnabled: Bool {
        FeatureFlags.songRequestHoldEnabled
    }

    /// Toggle hold mode. When enabled, new requests buffer without playing and
    /// auto-advance is suspended. When disabled, the first buffered song plays immediately.
    func setHold(_ enabled: Bool) async {
        Foundation.UserDefaults.standard.set(enabled, forKey: AppConstants.UserDefaults.songRequestHoldEnabled)
        NotificationCenter.default.postEnabled(.songRequestHoldChanged, enabled: enabled)
        Log.debug("SongRequestService: Hold \(enabled ? "enabled" : "released")", category: "SongRequest")

        if !enabled {
            guard musicController.isMusicAppRunning else { return }
            if queue.nowPlaying == nil && !queue.isEmpty {
                await playNextInQueue()
                if let nowPlaying = queue.nowPlaying {
                    sendChatMessage?("Now playing: \"\(nowPlaying.title)\" by \(nowPlaying.artist) (requested by \(nowPlaying.requesterUsername))")
                }
            }
        }
    }

    private var playbackObserver: Task<Void, Never>?

    private var musicAppLaunchObserver: NSObjectProtocol?

    /// Interval between auto-advance polls. Injectable so tests can use a small
    /// value instead of waiting the full production cadence.
    private let pollInterval: Duration

    /// Reentrancy guard for `playNextInQueue()`. Set and checked with no
    /// intervening `await`, so two near-simultaneous callers (e.g. two
    /// `processRequest` calls while Music.app is closed) can't both dequeue and
    /// start playback for the same slot.
    private var isStartingPlayback = false

    /// Track identifier of the streamer's own song that a queued request is
    /// waiting to follow. Set the first time the poll notices a pending request
    /// while the streamer's own (non-request, non-fallback) track is playing,
    /// then cleared once that track changes so the request takes over. This is
    /// what implements the "play when the current song ends" takeover policy
    /// instead of interrupting a track mid-play.
    private var takeoverBaselineTrackID: String?

    /// Consecutive poll ticks that have read Music.app as stopped. The poll
    /// requires two in a row before advancing or taking over, so a single flaky
    /// AppleScript read (which returns "stopped" on error) can't trigger a
    /// spurious skip mid-track.
    private var stoppedPollStreak = 0

    /// Persistent track ID Music.app loaded for the request that is currently
    /// playing. Established on the first poll tick after a request starts, then
    /// compared against Music.app's live current track. If they diverge while
    /// playback continues, the request either finished (Music autoplayed the next
    /// track) or the streamer hit skip inside Music.app. Either way the request is
    /// done, so the next queued request takes over instead of leaving a
    /// non-request track parked on the now-playing slot forever.
    private var playingRequestTrackID: String?

    /// Consecutive poll ticks the loaded track has differed from the takeover
    /// baseline (the streamer's own track a request is waiting to follow). Like
    /// `stoppedPollStreak`, a track change must be seen on two reads in a row
    /// before the queue takes over, so a single transient AppleScript read can't
    /// trigger a spurious takeover that cuts the streamer's song off mid-play.
    private var takeoverDivergenceStreak = 0

    /// Consecutive poll ticks the loaded track has differed from the playing
    /// request's baseline. Same two-in-a-row debounce as `takeoverDivergenceStreak`,
    /// applied to the "request finished / streamer skipped" hand-off.
    private var requestDivergenceStreak = 0

    /// Number of consecutive confirming reads a stop or track change needs before
    /// the queue acts on it. Two ≈ one extra poll interval of latency at a track
    /// boundary (unnoticeable) in exchange for immunity to a single flaky read.
    private let pollConfirmations = 2

    /// Whether the fallback playlist is currently playing (no active requests).
    private(set) var isPlayingFallback = false

    /// Per-item count of consecutive failed play attempts. A request can fail to
    /// play because its track is still syncing down from iCloud Music Library
    /// right after being added; keeping a count lets the poll retry a few times
    /// before giving up on one that never becomes playable (e.g. a song that
    /// isn't available or the streamer has no active subscription).
    private var playAttemptCounts: [UUID: Int] = [:]

    /// Maximum play attempts before a stuck request is dropped with a chat notice.
    private let maxPlayAttempts = 3

    /// Callback used to relay status messages back to Twitch chat. Set by
    /// `AppDelegate` once `TwitchChatService` is wired up.
    var sendChatMessage: ((String) -> Void)?

    // MARK: - Init

    /// Creates a song request service with overridable collaborators.
    ///
    /// All collaborators default to production implementations. Tests inject
    /// fakes via the parameters.
    ///
    /// - Parameters:
    ///   - queue: Backing queue store.
    ///   - blocklist: Title/artist blocklist.
    ///   - musicController: Apple Music controller (AppleScript-backed in prod).
    ///   - searchResolver: MusicKit/URL resolver. Defaults to one bound to
    ///     `musicController`.
    ///   - pollInterval: Auto-advance poll cadence. Defaults to 2 seconds; tests
    ///     pass a small value to avoid waiting the full production interval.
    init(
        queue: SongRequestQueue = SongRequestQueue(),
        blocklist: SongBlocklist = SongBlocklist(),
        musicController: any AppleMusicControlling = AppleMusicController(),
        searchResolver: SongSearchResolver? = nil,
        pollInterval: Duration = .seconds(2)
    ) {
        self.queue = queue
        self.blocklist = blocklist
        self.musicController = musicController
        self.searchResolver = searchResolver ?? SongSearchResolver(musicController: musicController)
        self.pollInterval = pollInterval
    }

    // MARK: - Lifecycle

    /// Begins watching Apple Music playback and the Music.app launch state.
    ///
    /// Spawns a 2-second polling task that auto-advances the queue when the
    /// current track stops (not paused), plus an `NSWorkspace` observer that
    /// flushes buffered requests when Music.app launches.
    ///
    /// - Important: Idempotent. Calling twice cancels and re-creates observers.
    func startPlaybackMonitoring() {
        stopPlaybackMonitoring()

        // Watch for Music.app launching so buffered requests flush automatically.
        musicAppLaunchObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didLaunchApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] note in
            guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                  app.bundleIdentifier == AppConstants.Music.bundleIdentifier else { return }
            Task { await self?.handleMusicAppLaunched() }
        }

        playbackObserver = Task { [weak self] in
            guard let self else { return }

            while !Task.isCancelled {
                // Auto-advance polling is not time-critical. A 20% tolerance lets
                // macOS coalesce the wakeup (0.4s at the default 2s cadence).
                try? await Task.sleep(for: self.pollInterval, tolerance: self.pollInterval / 5)
                await self.pollTick()
            }
        }
    }

    /// One auto-advance poll evaluation: reads a playback snapshot and applies
    /// the advance / takeover / fallback rules. The monitoring loop calls this
    /// every `pollInterval`.
    ///
    /// Internal (not private) on purpose: tests drive ticks through this method
    /// directly, so debounce and yield behavior is asserted per-tick instead of
    /// racing the wall-clock polling task (which gets starved on loaded CI hosts).
    func pollTick() async {
        guard isAutoAdvanceEnabled else { return }
        guard !isHoldEnabled else { return }
        // Music.app closed: nothing to advance, and probing player state
        // would relaunch the app the user just quit. Buffered requests
        // flush via the didLaunchApplication observer when Music reopens.
        guard musicController.isMusicAppRunning else { return }

        // One atomic read of player state + the loaded track's identity.
        // A nil snapshot means the AppleScript read failed this tick
        // (Apple Events to Music.app time out intermittently on macOS 26):
        // treat it as "no information" and skip the tick entirely, so a
        // flaky read can never be mistaken for a stop or a track change and
        // cut a song off mid-play. Streak counters are left untouched so a
        // single dropped read doesn't reset an in-progress debounce.
        guard let snapshot = musicController.playbackSnapshot() else { return }

        // Debounce stopped detection: require two consecutive stopped reads
        // before advancing/taking over, so one flaky read can't skip a track.
        let confirmedStopped: Bool
        if snapshot.state == .stopped {
            stoppedPollStreak += 1
            confirmedStopped = stoppedPollStreak >= pollConfirmations
        } else {
            stoppedPollStreak = 0
            confirmedStopped = false
        }

        if queue.nowPlaying != nil {
            // A request is playing.
            takeoverBaselineTrackID = nil
            takeoverDivergenceStreak = 0

            // Playback clearly stopped (two reads): advance, or drain.
            if confirmedStopped {
                playingRequestTrackID = nil
                requestDivergenceStreak = 0
                if !queue.isEmpty {
                    await advanceQueue()
                } else {
                    await handleQueueEmptied()
                }
                return
            }

            // Still playing: hand off to the next request the moment the
            // request's own track is replaced: the request ended and Music
            // autoplayed the next track, or the streamer skipped inside
            // Music.app. Music never reports "stopped" in either case.
            if snapshot.state == .playing {
                await handleRequestPlaybackDivergence(currentKey: snapshot.trackKey)
            }
            return
        }

        // No request is playing.
        playingRequestTrackID = nil
        requestDivergenceStreak = 0

        // Nothing to do unless requests wait.
        guard !queue.isEmpty else {
            takeoverBaselineTrackID = nil
            takeoverDivergenceStreak = 0
            return
        }

        if confirmedStopped || isPlayingFallback {
            // Silence, or the fallback playlist is filling: start the first
            // queued request. The fallback is explicit filler that yields to
            // a real request right away.
            takeoverBaselineTrackID = nil
            takeoverDivergenceStreak = 0
            await advanceQueue()
        } else if snapshot.state == .playing {
            // The streamer's own track is playing. Honor "play when the
            // current song ends": remember the loaded track, then take over
            // only once it changes to a different, confirmed track, never on
            // a single transient read that would cut the song off mid-play.
            await handleStreamerTrackTakeover(currentKey: snapshot.trackKey)
        }
        // Paused, or an unconfirmed stopped read: wait.
    }

    /// Stops the polling task and removes the Music.app launch observer.
    /// Safe to call when no monitoring is active.
    func stopPlaybackMonitoring() {
        playbackObserver?.cancel()
        playbackObserver = nil
        if let observer = musicAppLaunchObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
            musicAppLaunchObserver = nil
        }
    }

    // MARK: - Song Request Processing

    /// Resolves a query into a track, runs blocklist + queue validation, and
    /// either enqueues or starts playback as appropriate.
    ///
    /// Used by `SongRequestCommand` (`!sr`), channel-point redemptions, and
    /// bit cheers. The `RequestAudience` gate applies only to chat commands.
    /// Redemptions are gated by their own enable toggle.
    ///
    /// - Parameters:
    ///   - query: Search string, Apple Music link, Spotify link, or YouTube link.
    ///   - username: Twitch display name of the requester.
    ///   - source: How the request arrived (chat command, channel points, bits).
    /// - Returns: A `RequestResult` describing the outcome (added, blocked,
    ///   queue-full, not-found, etc.)
    func processRequest(query: String, username: String, source: RequestSource) async -> RequestResult {
        // Master gate. The settings UI hides itself when this is off, but the
        // `!sr` command, channel-point reward, and bit handler can each still
        // fire from their own independent toggles, so the only safe place to
        // enforce "feature off = no requests" is this shared chokepoint.
        guard isFeatureEnabled else { return .featureDisabled }

        if case .chatCommand(let context) = source {
            let audience = chatAudience
            if !audience.permits(context) {
                return .error(audience.denialMessage)
            }
        }

        guard musicController.isAuthorized || musicController.authStatus == .notDetermined else {
            return .notAuthorized
        }

        let searchResult = await searchResolver.resolve(query: query)

        switch searchResult {
        case .found(let song):
            if await blocklist.isBlocked(title: song.title, artist: song.artistName) {
                return .blocked
            }

            let item = SongRequestItem(song: song, requesterUsername: username)

            // Approval mode: park the resolved request in the holding pen and let
            // the streamer approve/reject it from the Queue pane. The per-user and
            // capacity gates run at approval time via `queue.addApproved`.
            if isApprovalRequired {
                switch queue.addPending(item) {
                case .added:
                    return .pendingApproval(item: item)
                case .queueFull(let max):
                    return .queueFull(max: max)
                case .alreadyInQueue:
                    return .alreadyInQueue
                case .userLimitReached(let max):
                    // Defensive only: addPending is not per-user capped today, so
                    // this never fires. Handled because AddResult is shared with add(_:).
                    return .userLimitReached(max: max)
                }
            }

            // Resolve the requester's per-user limit from their roles. Chat
            // requests use the sender's badges; channel-point / bit requests have
            // no chat badges, so they fall back to the everyone tier.
            let effectiveUserLimit: Int
            if case .chatCommand(let context) = source {
                effectiveUserLimit = SongRequestLimits.effectiveLimit(
                    isSubscriber: context.isSubscriber,
                    isVIP: context.isVIP,
                    isModerator: context.isModerator,
                    isBroadcaster: context.isBroadcaster
                )
            } else {
                effectiveUserLimit = SongRequestLimits.nonChatLimit()
            }
            let addResult = queue.add(item, perUserLimit: effectiveUserLimit)

            switch addResult {
            case .added(let position):
                if musicController.isMusicAppRunning && !isHoldEnabled && queue.nowPlaying == nil {
                    // Start now only from an idle or fallback state; never interrupt
                    // the streamer's actively-playing track (or act on a flaky read).
                    // When a track is playing, the poll takes over at its boundary.
                    await startImmediatelyIfIdle()
                }
                // else: a request is already playing, Music.app is closed, or hold is
                // active; the request stays buffered for the poll / launch flush.
                return .added(item: item, position: position)
            case .queueFull(let max):
                return .queueFull(max: max)
            case .userLimitReached(let max):
                return .userLimitReached(max: max)
            case .alreadyInQueue:
                return .alreadyInQueue
            }

        case .notFound(let query):
            return .notFound(query: query)
        case .linkNotFound:
            return .linkNotFound
        case .error(let message):
            return .error(message)
        }
    }

    /// Skips the now-playing track and immediately starts the next queued
    /// request. Falls back to the drain policy (fallback playlist / autoplay /
    /// silence) when the queue empties.
    ///
    /// - Returns: The newly-playing item, or `nil` when the queue empties.
    func skip() async -> SongRequestItem? {
        // Take the playback-transition guard so the auto-advance poll can't
        // interleave a second dequeue across the `playNow` await and consume two
        // tracks for one skip.
        guard !isStartingPlayback else { return nil }
        isStartingPlayback = true
        defer { isStartingPlayback = false }
        takeoverBaselineTrackID = nil
        takeoverDivergenceStreak = 0
        // Drop the divergence baseline so the poll re-establishes it for the
        // track Music.app loads next, instead of instantly re-skipping it.
        playingRequestTrackID = nil
        requestDivergenceStreak = 0

        let next = queue.skip()
        if let next {
            // There's a next request: it's already `nowPlaying`; start it.
            if let song = next.song {
                do {
                    try await musicController.playNow(song: song)
                    Log.debug("SongRequestService: Skipped to \"\(next.title)\"", category: "SongRequest")
                } catch {
                    Log.debug("SongRequestService: Failed to play after skip: \(error)", category: "SongRequest")
                }
            }
            isPlayingFallback = false
            return next
        }
        // Queue emptied by the skip: honor the drain policy (fallback / autoplay /
        // silence) instead of an unconditional stop.
        await handleQueueEmptied()
        return nil
    }

    /// Skips whatever is currently playing, used by the chat vote-skip feature.
    ///
    /// When a queued request is playing, this delegates to `skip()` so the next
    /// request takes over. When the queue is idle, it advances Apple Music's own
    /// player so vote-skip still works during normal playback.
    ///
    /// - Returns: The newly-playing request when one exists, otherwise `nil`.
    @discardableResult
    func voteSkip() async -> SongRequestItem? {
        if queue.nowPlaying != nil {
            return await skip()
        }
        do {
            try await musicController.skipToNext()
            Log.debug("SongRequestService: Vote-skip advanced the Apple Music track", category: "SongRequest")
        } catch {
            Log.debug("SongRequestService: Vote-skip failed to advance track: \(error)", category: "SongRequest")
        }
        return nil
    }

    /// Removes every request from the queue and clears Music.app's player.
    ///
    /// - Returns: Number of items that were in the queue before clearing.
    func clearQueue() async -> Int {
        let count = queue.clear()
        takeoverBaselineTrackID = nil
        takeoverDivergenceStreak = 0
        playingRequestTrackID = nil
        requestDivergenceStreak = 0
        playAttemptCounts.removeAll()
        await musicController.clearPlayerQueue()
        return count
    }

    /// Bit-cheer boost: moves the cheerer's most-recent queued request to the
    /// front, then starts it immediately when nothing from the request queue is
    /// playing (idle player or the fallback playlist is filling). Without this
    /// kick, a boost over a fallback playlist would silently sit until the
    /// fallback track happened to end. Returns the boosted item, or `nil` when
    /// the user has nothing queued or the feature is off.
    @discardableResult
    func boost(username: String) async -> SongRequestItem? {
        guard isFeatureEnabled else { return nil }
        guard let boosted = queue.boost(username: username) else { return nil }
        if musicController.isMusicAppRunning, !isHoldEnabled, queue.nowPlaying == nil {
            takeoverBaselineTrackID = nil
            takeoverDivergenceStreak = 0
            await startImmediatelyIfIdle()
        }
        return boosted
    }

    // MARK: - Approval

    /// Number of requests waiting for approval.
    var pendingApprovalCount: Int { queue.pendingCount }

    /// Approve a held request: move it into the live queue and start it if idle.
    /// No-op (returns `nil`) when the ID is unknown or the queue is full.
    @discardableResult
    func approve(id: UUID) async -> SongRequestItem? {
        guard let item = queue.takePending(id: id) else { return nil }
        guard case .added = queue.addApproved(item) else {
            // Live queue is full: put the request back in the pending pen so the
            // streamer can retry once a slot frees up, instead of losing it.
            queue.addPending(item)
            sendChatMessage?("Couldn't queue \"\(item.title)\". The queue is full. Still pending; approve again once there's room.")
            return nil
        }
        if musicController.isMusicAppRunning, !isHoldEnabled, queue.nowPlaying == nil {
            takeoverBaselineTrackID = nil
            takeoverDivergenceStreak = 0
            await startImmediatelyIfIdle()
        }
        sendChatMessage?("Approved: \"\(item.title)\" by \(item.artist) (requested by \(item.requesterUsername))")
        return item
    }

    /// Reject a held request and drop it. Returns the removed item, or `nil` when
    /// the ID is unknown.
    @discardableResult
    func reject(id: UUID) -> SongRequestItem? {
        guard let item = queue.takePending(id: id) else { return nil }
        sendChatMessage?("Request declined: \"\(item.title)\" (\(item.requesterUsername))")
        return item
    }

    /// Drop every held request without approving any. Returns the number removed.
    @discardableResult
    func clearPending() -> Int {
        queue.clearPending()
    }

    // MARK: - Private Helpers

    /// Starts the just-added (or just-boosted) request immediately, but only from
    /// a state where doing so won't cut a song off mid-play.
    ///
    /// Starts now when the fallback playlist is filling (explicit filler that
    /// yields to a real request) or when nothing is actively playing (silent or
    /// paused). When the streamer's own track is actively playing, or the
    /// playback read is inconclusive (`nil`), this does nothing, and the
    /// auto-advance poll starts the request at the next confirmed track boundary.
    /// That is the "wait until the current song ends" rule, applied at the entry
    /// point so a request never interrupts a live read that happened to flake.
    private func startImmediatelyIfIdle() async {
        if isPlayingFallback {
            await playNextInQueue()
            return
        }
        // A nil snapshot is an inconclusive read: don't risk interrupting; let the
        // poll take over at the next confirmed boundary.
        guard let snapshot = musicController.playbackSnapshot() else { return }
        guard snapshot.state != .playing else { return }
        await playNextInQueue()
    }

    /// Boundary detection for the takeover poll: starts the first queued request
    /// once the streamer's own track changes.
    ///
    /// Ignores an unknown (`nil`) track key: a failed metadata read is "no
    /// information", never a boundary, and requires the new track to be seen on
    /// `pollConfirmations` reads in a row, so a single transient read can't be
    /// mistaken for a song change and cut the streamer's track off mid-play.
    private func handleStreamerTrackTakeover(currentKey: String?) async {
        guard let currentKey else {
            // A track is loaded but its identity couldn't be read this tick. Hold
            // the baseline and wait; never treat "unknown" as "the song changed".
            return
        }
        guard let baseline = takeoverBaselineTrackID else {
            // First read with the streamer's track loaded: baseline it.
            takeoverBaselineTrackID = currentKey
            takeoverDivergenceStreak = 0
            return
        }
        guard currentKey != baseline else {
            // Same song still loaded: reset any in-progress divergence streak.
            takeoverDivergenceStreak = 0
            return
        }
        takeoverDivergenceStreak += 1
        guard takeoverDivergenceStreak >= pollConfirmations else { return }
        takeoverBaselineTrackID = nil
        takeoverDivergenceStreak = 0
        await advanceQueue()
    }

    /// Boundary detection while a request is playing: advances to the next queued
    /// request once the request's own track is replaced (it ended and Music
    /// autoplayed on, or the streamer skipped inside Music.app). Same `nil`
    /// tolerance and two-in-a-row confirmation as `handleStreamerTrackTakeover`.
    private func handleRequestPlaybackDivergence(currentKey: String?) async {
        guard let currentKey else { return }
        guard let baseline = playingRequestTrackID else {
            // First playing tick for this request: establish the divergence
            // baseline from whatever Music.app loaded.
            playingRequestTrackID = currentKey
            requestDivergenceStreak = 0
            return
        }
        guard currentKey != baseline else {
            requestDivergenceStreak = 0
            return
        }
        requestDivergenceStreak += 1
        guard requestDivergenceStreak >= pollConfirmations else { return }
        playingRequestTrackID = nil
        requestDivergenceStreak = 0
        if !queue.isEmpty {
            await advanceQueue()
        } else {
            await handleQueueEmptied()
        }
    }

    /// Dequeues the next item and asks Music.app to play it. Re-queues at the
    /// head if Music.app is closed; advances past unplayable items otherwise.
    ///
    /// Guarded against reentrancy: the `isStartingPlayback` check and set happen
    /// with no `await` between them, so two near-simultaneous callers can't both
    /// dequeue and start playback for the same slot.
    private func playNextInQueue() async {
        guard !isStartingPlayback else { return }
        isStartingPlayback = true
        defer { isStartingPlayback = false }
        await playNextInQueueUnguarded()
    }

    /// Body of `playNextInQueue` without the reentrancy guard, so the
    /// skip-unplayable retry can recurse without deadlocking on the guard.
    private func playNextInQueueUnguarded() async {
        guard let item = queue.dequeue(), let song = item.song else { return }

        do {
            try await musicController.playNow(song: song)
            playAttemptCounts[item.id] = nil
            isPlayingFallback = false
            Log.debug("SongRequestService: Now playing \"\(item.title)\" by \(item.artist) (requested by \(item.requesterUsername))", category: "SongRequest")
        } catch PlaybackError.musicAppNotRunning {
            // Music.app closed: put the item back at the front so it plays first when Music.app re-opens
            queue.insertAtHead(item)
            queue.clearNowPlaying()
            Log.debug("SongRequestService: Music.app closed, \"\(item.title)\" re-queued at head", category: "SongRequest")
        } catch PlaybackError.notPlayable(let title) {
            // The song was added to the library but isn't playable yet (usually
            // still syncing down from iCloud right after the add). Keep it queued
            // at the head and let the poll retry, but cap attempts so a genuinely
            // unavailable track (no subscription) is eventually dropped instead of
            // looping forever.
            let attempts = (playAttemptCounts[item.id] ?? 0) + 1
            if attempts >= maxPlayAttempts {
                playAttemptCounts[item.id] = nil
                queue.clearNowPlaying()
                Log.debug("SongRequestService: Dropping \"\(title)\" after \(attempts) failed play attempts (unavailable or no subscription)", category: "SongRequest")
                sendChatMessage?("Couldn't play \"\(title)\" (not available on Apple Music). Skipping it.")
                await playNextInQueueUnguarded()
            } else {
                playAttemptCounts[item.id] = attempts
                queue.insertAtHead(item)
                queue.clearNowPlaying()
                Log.debug("SongRequestService: \"\(title)\" not ready (attempt \(attempts)/\(maxPlayAttempts)), re-queued; will retry", category: "SongRequest")
            }
        } catch {
            Log.debug("SongRequestService: Failed to play \"\(item.title)\": \(error)", category: "SongRequest")
            await playNextInQueueUnguarded()
        }
    }

    /// Advances to the next queued track when the current request finishes,
    /// or kicks off the fallback playlist if the queue has run dry.
    private func advanceQueue() async {
        guard !queue.isEmpty else {
            await handleQueueEmptied()
            return
        }
        isPlayingFallback = false
        await playNextInQueue()
        if let nowPlaying = queue.nowPlaying {
            sendChatMessage?("Now playing: \"\(nowPlaying.title)\" by \(nowPlaying.artist) (requested by \(nowPlaying.requesterUsername))")
        }
    }

    /// Decides what happens once the request queue runs dry. Previously the poll
    /// just cleared now-playing and let Music.app do whatever, so the fallback
    /// playlist never started on a normal drain and "Resume Autoplay When Empty"
    /// did nothing. Now: play the configured fallback playlist if set; otherwise
    /// either leave Apple Music autoplaying (toggle on) or stop for silence
    /// (toggle off). Honors hold mode and never relaunches a closed Music.app.
    private func handleQueueEmptied() async {
        queue.clearNowPlaying()
        guard !isHoldEnabled, musicController.isMusicAppRunning else { return }

        let fallback = Foundation.UserDefaults.standard
            .string(forKey: AppConstants.UserDefaults.songRequestFallbackPlaylist) ?? ""
        if !fallback.isEmpty {
            await startFallbackIfConfigured()
        } else if isAutoplayWhenEmptyEnabled {
            isPlayingFallback = false
            Log.debug("SongRequestService: Queue empty, Apple Music continues normally", category: "SongRequest")
        } else {
            await musicController.clearPlayerQueue()
            isPlayingFallback = false
            Log.debug("SongRequestService: Queue empty, autoplay off, stopping playback", category: "SongRequest")
        }
    }

    /// Called when Music.app starts. Flushes the first buffered request (or
    /// starts the fallback playlist) after a 500 ms grace period so Music.app
    /// has time to initialize its AppleScript surface.
    private func handleMusicAppLaunched() async {
        Log.debug("SongRequestService: Music.app launched, flushing buffered requests", category: "SongRequest")
        // Give Music.app a moment to finish launching before sending commands
        try? await Task.sleep(for: .milliseconds(500))
        guard !isHoldEnabled else {
            Log.debug("SongRequestService: Hold enabled, skipping flush on Music.app launch", category: "SongRequest")
            return
        }
        if queue.nowPlaying == nil && !queue.isEmpty {
            await playNextInQueue()
        } else if queue.isEmpty {
            await startFallbackIfConfigured()
        }
    }

    /// Plays the user-configured fallback playlist when the queue is empty,
    /// so the stream is never silent. No-op when no playlist is configured
    /// or hold mode is active.
    private func startFallbackIfConfigured() async {
        guard !isHoldEnabled else { return }
        let name = Foundation.UserDefaults.standard.string(forKey: AppConstants.UserDefaults.songRequestFallbackPlaylist) ?? ""
        guard !name.isEmpty else { return }
        guard musicController.isMusicAppRunning else { return }
        do {
            try await musicController.playFallbackPlaylist(name: name)
            isPlayingFallback = true
            Log.debug("SongRequestService: Fallback playlist '\(name)' playing", category: "SongRequest")
        } catch {
            Log.debug("SongRequestService: Failed to start fallback playlist: \(error)", category: "SongRequest")
        }
    }
}
