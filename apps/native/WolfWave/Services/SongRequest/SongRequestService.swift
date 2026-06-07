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

    /// Whether the song-request feature's master toggle is on. Every request
    /// path (chat `!sr`, channel points, bits) is rejected when this is off, so
    /// the per-command and per-redemption toggles can't accept requests on their
    /// own while the feature as a whole is disabled.
    var isFeatureEnabled: Bool {
        Foundation.UserDefaults.standard.bool(forKey: AppConstants.UserDefaults.songRequestEnabled)
    }

    var isAutoAdvanceEnabled: Bool {
        Preferences.bool(AppConstants.UserDefaults.songRequestAutoAdvance, default: true)
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

    /// Whether the fallback playlist is currently playing (no active requests).
    private(set) var isPlayingFallback = false

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

                guard self.isAutoAdvanceEnabled else { continue }
                guard !self.isHoldEnabled else { continue }
                // Music.app closed: nothing to advance, and probing player state
                // would relaunch the app the user just quit. Buffered requests
                // flush via the didLaunchApplication observer when Music reopens.
                guard self.musicController.isMusicAppRunning else { continue }

                let isPlaying = self.musicController.isPlaying
                let isPaused = self.musicController.isPaused

                // Debounce stopped detection: a flaky AppleScript read returns
                // "stopped" on error, so require two consecutive stopped polls
                // before advancing/taking over to avoid a spurious mid-track skip.
                if !isPlaying && !isPaused {
                    self.stoppedPollStreak += 1
                } else {
                    self.stoppedPollStreak = 0
                }
                let confirmedStopped = self.stoppedPollStreak >= 2

                if self.queue.nowPlaying != nil {
                    self.takeoverBaselineTrackID = nil

                    // Playback clearly stopped (two reads): advance, or drain.
                    if confirmedStopped {
                        if !self.queue.isEmpty {
                            await self.advanceQueue()
                        } else {
                            await self.handleQueueEmptied()
                        }
                        self.playingRequestTrackID = nil
                        continue
                    }

                    // Still playing: detect when Music.app has moved off the
                    // request's own track. That happens when the request ends and
                    // Music autoplays the next (related) track, or when the
                    // streamer hits skip inside Music.app. Music never reports
                    // "stopped" in either case, so without this the queue stalls
                    // and a non-request track keeps playing. Hand off to the next
                    // queued request the moment the loaded track diverges.
                    if isPlaying {
                        let currentID = self.musicController.currentTrackID
                        if let baseline = self.playingRequestTrackID {
                            if let currentID, currentID != baseline {
                                self.playingRequestTrackID = nil
                                if !self.queue.isEmpty {
                                    await self.advanceQueue()
                                } else {
                                    await self.handleQueueEmptied()
                                }
                            }
                        } else {
                            // First playing tick for this request: establish the
                            // divergence baseline from whatever Music.app loaded.
                            self.playingRequestTrackID = currentID
                        }
                    }
                    continue
                }

                // No request is playing.
                self.playingRequestTrackID = nil

                // Nothing to do unless requests wait.
                guard !self.queue.isEmpty else {
                    self.takeoverBaselineTrackID = nil
                    continue
                }

                if confirmedStopped || self.isPlayingFallback {
                    // Silence, or the fallback playlist is filling: start the
                    // first queued request immediately.
                    self.takeoverBaselineTrackID = nil
                    await self.advanceQueue()
                } else if isPlaying {
                    // The streamer's own track is playing. Honor "play when the
                    // current song ends": remember the track that's playing, then
                    // take over the moment it changes (finishes or gets skipped),
                    // rather than cutting it off mid-song.
                    let currentID = self.musicController.currentTrackID
                    if let baseline = self.takeoverBaselineTrackID {
                        if currentID == nil || currentID != baseline {
                            self.takeoverBaselineTrackID = nil
                            await self.advanceQueue()
                        }
                    } else {
                        self.takeoverBaselineTrackID = currentID
                    }
                } else {
                    // Paused, or a single unconfirmed stopped read: wait.
                    continue
                }
            }
        }
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
                if musicController.isMusicAppRunning && !isHoldEnabled {
                    if queue.nowPlaying == nil && (!musicController.isPlaying || isPlayingFallback) {
                        // Nothing is playing, OR fallback playlist is filling: start the request now
                        await playNextInQueue()
                    }
                    // else: a real request is already playing; auto-advance will pick this one up
                }
                // else: Music.app is closed or hold is active, request stays buffered in the queue
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
        // Drop the divergence baseline so the poll re-establishes it for the
        // track Music.app loads next, instead of instantly re-skipping it.
        playingRequestTrackID = nil

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
        playingRequestTrackID = nil
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
        if musicController.isMusicAppRunning, !isHoldEnabled,
           queue.nowPlaying == nil, (!musicController.isPlaying || isPlayingFallback) {
            takeoverBaselineTrackID = nil
            await playNextInQueue()
        }
        return boosted
    }

    // MARK: - Private Helpers

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
            isPlayingFallback = false
            Log.debug("SongRequestService: Now playing \"\(item.title)\" by \(item.artist) (requested by \(item.requesterUsername))", category: "SongRequest")
        } catch PlaybackError.musicAppNotRunning {
            // Music.app closed: put the item back at the front so it plays first when Music.app re-opens
            queue.insertAtHead(item)
            queue.clearNowPlaying()
            Log.debug("SongRequestService: Music.app closed, \"\(item.title)\" re-queued at head", category: "SongRequest")
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
