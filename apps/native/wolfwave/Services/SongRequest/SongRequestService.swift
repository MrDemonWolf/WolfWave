//
//  SongRequestService.swift
//  wolfwave
//
//  Created by MrDemonWolf, Inc. on 4/8/26.
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
        case error(String)
    }

    // MARK: - Properties

    let queue: SongRequestQueue
    let blocklist: SongBlocklist
    let musicController: any AppleMusicControlling
    let searchResolver: SongSearchResolver

    var isSubscriberOnly: Bool {
        Foundation.UserDefaults.standard.bool(forKey: AppConstants.UserDefaults.songRequestSubscriberOnly)
    }

    var isAutoAdvanceEnabled: Bool {
        let defaults = Foundation.UserDefaults.standard
        if defaults.object(forKey: AppConstants.UserDefaults.songRequestAutoAdvance) == nil { return true }
        return defaults.bool(forKey: AppConstants.UserDefaults.songRequestAutoAdvance)
    }

    var isHoldEnabled: Bool {
        Foundation.UserDefaults.standard.bool(forKey: AppConstants.UserDefaults.songRequestHoldEnabled)
    }

    /// Toggle hold mode. When enabled, new requests buffer without playing and
    /// auto-advance is suspended. When disabled, the first buffered song plays immediately.
    func setHold(_ enabled: Bool) async {
        Foundation.UserDefaults.standard.set(enabled, forKey: AppConstants.UserDefaults.songRequestHoldEnabled)
        NotificationCenter.default.post(name: .songRequestHoldChanged, object: nil, userInfo: ["enabled": enabled])
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
    init(
        queue: SongRequestQueue = SongRequestQueue(),
        blocklist: SongBlocklist = SongBlocklist(),
        musicController: any AppleMusicControlling = AppleMusicController(),
        searchResolver: SongSearchResolver? = nil
    ) {
        self.queue = queue
        self.blocklist = blocklist
        self.musicController = musicController
        self.searchResolver = searchResolver ?? SongSearchResolver(musicController: musicController)
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
                try? await Task.sleep(for: .seconds(2))

                guard self.isAutoAdvanceEnabled else { continue }
                guard !self.isHoldEnabled else { continue }
                // Don't advance when the user has paused — only when playback has stopped/finished
                guard !self.musicController.isPlaying && !self.musicController.isPaused else { continue }

                if self.queue.nowPlaying != nil && !self.queue.isEmpty {
                    await self.advanceQueue()
                } else if self.queue.nowPlaying != nil && self.queue.isEmpty {
                    self.queue.clearNowPlaying()
                    Log.debug("SongRequestService: Queue empty, Apple Music continues normally", category: "SongRequest")
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

    /// Resolves a chat query into a track, runs blocklist + queue validation,
    /// and either enqueues or starts playback as appropriate.
    ///
    /// Used by `SongRequestCommand` (`!sr`) and tests.
    ///
    /// - Parameters:
    ///   - query: Search string, Apple Music link, Spotify link, or YouTube link.
    ///   - username: Twitch display name of the requester.
    ///   - context: Sender context (used for sub/mod gating).
    /// - Returns: A `RequestResult` describing the outcome — added, blocked,
    ///   queue-full, not-found, etc.
    func processRequest(query: String, username: String, context: BotCommandContext) async -> RequestResult {
        if isSubscriberOnly && !context.isSubscriber && !context.isPrivileged {
            return .error("Song requests are subscriber-only right now")
        }

        guard musicController.isAuthorized || musicController.authStatus == .notDetermined else {
            return .notAuthorized
        }

        let searchResult = await searchResolver.resolve(query: query)

        switch searchResult {
        case .found(let song):
            if blocklist.isBlocked(title: song.title, artist: song.artistName) {
                return .blocked
            }

            let item = SongRequestItem(song: song, requesterUsername: username)
            let addResult = queue.add(item)

            switch addResult {
            case .added(let position):
                if musicController.isMusicAppRunning && !isHoldEnabled {
                    if queue.nowPlaying == nil && (!musicController.isPlaying || isPlayingFallback) {
                        // Nothing is playing, OR fallback playlist is filling — start the request now
                        await playNextInQueue()
                    }
                    // else: a real request is already playing; auto-advance will pick this one up
                }
                // else: Music.app is closed or hold is active — request stays buffered in the queue
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
    /// request. Stops Music.app playback if the queue is empty.
    ///
    /// - Returns: The newly-playing item, or `nil` when the queue empties.
    func skip() async -> SongRequestItem? {
        let next = queue.skip()
        if let next, let song = next.song {
            do {
                try await musicController.playNow(song: song)
                Log.debug("SongRequestService: Skipped to \"\(next.title)\"", category: "SongRequest")
            } catch {
                Log.debug("SongRequestService: Failed to play after skip: \(error)", category: "SongRequest")
            }
        } else {
            // No next song — stop Music.app
            await musicController.clearPlayerQueue()
        }
        return next
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
        await musicController.clearPlayerQueue()
        return count
    }

    // MARK: - Private Helpers

    /// Dequeues the next item and asks Music.app to play it. Re-queues at the
    /// head if Music.app is closed; advances past unplayable items otherwise.
    private func playNextInQueue() async {
        guard let item = queue.dequeue(), let song = item.song else { return }

        do {
            try await musicController.playNow(song: song)
            isPlayingFallback = false
            Log.debug("SongRequestService: Now playing \"\(item.title)\" by \(item.artist) (requested by \(item.requesterUsername))", category: "SongRequest")
        } catch PlaybackError.musicAppNotRunning {
            // Music.app closed — put the item back at the front so it plays first when Music.app re-opens
            queue.insertAtHead(item)
            queue.clearNowPlaying()
            Log.debug("SongRequestService: Music.app closed — \"\(item.title)\" re-queued at head", category: "SongRequest")
        } catch {
            Log.debug("SongRequestService: Failed to play \"\(item.title)\": \(error)", category: "SongRequest")
            await playNextInQueue()
        }
    }

    /// Advances to the next queued track when the current request finishes,
    /// or kicks off the fallback playlist if the queue has run dry.
    private func advanceQueue() async {
        guard !queue.isEmpty else {
            queue.clearNowPlaying()
            await startFallbackIfConfigured()
            return
        }
        isPlayingFallback = false
        await playNextInQueue()
        if let nowPlaying = queue.nowPlaying {
            sendChatMessage?("Now playing: \"\(nowPlaying.title)\" by \(nowPlaying.artist) (requested by \(nowPlaying.requesterUsername))")
        }
    }

    /// Called when Music.app starts. Flushes the first buffered request (or
    /// starts the fallback playlist) after a 500 ms grace period so Music.app
    /// has time to initialize its AppleScript surface.
    private func handleMusicAppLaunched() async {
        Log.debug("SongRequestService: Music.app launched — flushing buffered requests", category: "SongRequest")
        // Give Music.app a moment to finish launching before sending commands
        try? await Task.sleep(for: .milliseconds(500))
        guard !isHoldEnabled else {
            Log.debug("SongRequestService: Hold enabled — skipping flush on Music.app launch", category: "SongRequest")
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
