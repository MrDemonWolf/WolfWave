//
//  SongRequestService.swift
//  wolfwave
//
//  Created by MrDemonWolf, Inc. on 4/8/26.
//

import AppKit
import Foundation
import MusicKit
import Observation

/// Orchestrates the song request system.
///
/// Coordinates search resolution, blocklist checking, queue management,
/// and Apple Music playback via MusicKit.
@Observable
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

    @ObservationIgnored
    private var playbackObserver: Task<Void, Never>?

    @ObservationIgnored
    private var musicAppLaunchObserver: NSObjectProtocol?

    /// Whether the fallback playlist is currently playing (no active requests).
    private(set) var isPlayingFallback = false

    @ObservationIgnored
    var sendChatMessage: ((String) -> Void)?

    // MARK: - Init

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
                try? await Task.sleep(nanoseconds: 2_000_000_000)

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

    func stopPlaybackMonitoring() {
        playbackObserver?.cancel()
        playbackObserver = nil
        if let observer = musicAppLaunchObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
            musicAppLaunchObserver = nil
        }
    }

    // MARK: - Song Request Processing

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

    func clearQueue() async -> Int {
        let count = queue.clear()
        await musicController.clearPlayerQueue()
        return count
    }

    // MARK: - Private Helpers

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

    private func handleMusicAppLaunched() async {
        Log.debug("SongRequestService: Music.app launched — flushing buffered requests", category: "SongRequest")
        // Give Music.app a moment to finish launching before sending commands
        try? await Task.sleep(nanoseconds: 500_000_000)
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
