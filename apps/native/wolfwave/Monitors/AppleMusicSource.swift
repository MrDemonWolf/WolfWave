//
//  AppleMusicSource.swift
//  wolfwave
//
//  Created by MrDemonWolf, Inc. on 3/28/26.
//

import Foundation
import AppKit
import ScriptingBridge

final class AppleMusicSource: PlaybackSource, @unchecked Sendable {

    // MARK: - Properties

    private nonisolated enum Constants {
        static let musicBundleIdentifier = "com.apple.Music"
        static let notificationName = "com.apple.Music.playerInfo"
        static let queueLabel = "com.mrdemonwolf.wolfwave.musicplaybackmonitor"
        static let checkInterval: TimeInterval = 5.0
        static let trackSeparator = " | "
        static let notificationDedupWindow: TimeInterval = 0.75
        static let idleGraceWindow: TimeInterval = 2.0
        static let playerStatePlaying: UInt32 = 1800426320

        enum Status {
            static let notRunning = "NOT_RUNNING"
            static let notPlaying = "NOT_PLAYING"
            static let errorPrefix = "ERROR:"
        }
    }

    weak var delegate: PlaybackSourceDelegate?

    // All mutable scalar state lives behind `stateLock`. Methods are
    // `nonisolated`, so the lock is the only safety guarantee — every
    // read and write goes through `stateLock.withLock`.
    private let stateLock = NSLock()
    nonisolated(unsafe) private var currentCheckInterval: TimeInterval = Constants.checkInterval
    nonisolated(unsafe) private var timer: DispatchSourceTimer?
    nonisolated(unsafe) private var lastLoggedTrack: String?
    nonisolated(unsafe) private var lastTrackSeenAt: Date = .distantPast
    nonisolated(unsafe) private var lastNotificationAt: Date = .distantPast
    nonisolated(unsafe) private var isTracking = false

    private let backgroundQueue = DispatchQueue(label: Constants.queueLabel, qos: .utility)

    // MARK: - Protocol Conformance

    func startTracking() {
        let alreadyTracking = stateLock.withLock { () -> Bool in
            guard !isTracking else { return true }
            isTracking = true
            return false
        }
        guard !alreadyTracking else { return }
        subscribeToMusicNotifications()
        performInitialTrackCheck()
        setupFallbackTimer()
    }

    nonisolated func stopTracking() {
        let wasTracking = stateLock.withLock { () -> Bool in
            guard isTracking else { return false }
            isTracking = false
            return true
        }
        guard wasTracking else { return }
        DistributedNotificationCenter.default().removeObserver(self)
        let pendingTimer = stateLock.withLock { () -> DispatchSourceTimer? in
            let existing = timer
            timer = nil
            return existing
        }
        pendingTimer?.cancel()
        backgroundQueue.sync {}
    }

    func updateCheckInterval(_ interval: TimeInterval) {
        guard stateLock.withLock({ isTracking }) else { return }
        let cancelled = stateLock.withLock { () -> DispatchSourceTimer? in
            currentCheckInterval = max(interval, 1.0)
            let existing = timer
            timer = nil
            return existing
        }
        cancelled?.cancel()
        setupFallbackTimer()
    }

    nonisolated func forceRefresh() {
        guard stateLock.withLock({ isTracking }) else { return }
        // Clear the notification dedup gate so a user-initiated refresh
        // immediately after a system notification is not dropped.
        stateLock.withLock { lastNotificationAt = .distantPast }
        scheduleTrackCheck(reason: "force-refresh")
    }

    // MARK: - Playback Monitoring

    @objc nonisolated private func musicPlayerInfoChanged(_ notification: Notification) {
        let now = Date()
        let shouldSchedule = stateLock.withLock { () -> Bool in
            guard now.timeIntervalSince(lastNotificationAt) >= Constants.notificationDedupWindow else {
                return false
            }
            lastNotificationAt = now
            return true
        }
        guard shouldSchedule else { return }
        Log.debug("AppleMusicSource: Music notification received", category: "Music")
        scheduleTrackCheck(reason: "notification")
    }

    /// Fetches the currently-playing track via ScriptingBridge.
    ///
    /// ScriptingBridge dispatches AppleEvents through the AE bridge, which
    /// requires main-thread access. We hop to `@MainActor` for the SB calls
    /// and back out for the cheap string/delegate work.
    nonisolated private func checkCurrentTrack() async {
        let isRunning = NSRunningApplication.runningApplications(
            withBundleIdentifier: Constants.musicBundleIdentifier
        ).first != nil
        guard isRunning else {
            handleTrackInfo(Constants.Status.notRunning)
            return
        }

        let trackInfo: String? = await MainActor.run {
            guard let musicApp = SBApplication(bundleIdentifier: Constants.musicBundleIdentifier) else {
                return nil
            }
            guard let stateObj = musicApp.value(forKey: "playerState") else {
                return nil
            }
            let isPlaying: Bool
            if let stateNum = stateObj as? NSNumber {
                isPlaying = (stateNum.uint32Value == Constants.playerStatePlaying)
            } else {
                isPlaying = false
            }
            guard isPlaying else { return Constants.Status.notPlaying }
            guard let track = musicApp.value(forKey: "currentTrack") as? SBObject else {
                return Constants.Status.notPlaying
            }
            let name = track.value(forKey: "name") as? String ?? ""
            let artist = track.value(forKey: "artist") as? String ?? ""
            let album = track.value(forKey: "album") as? String ?? ""
            let duration = (track.value(forKey: "duration") as? Double) ?? 0
            let elapsed = (musicApp.value(forKey: "playerPosition") as? Double) ?? 0
            let playlist = (musicApp.value(forKey: "currentPlaylist") as? SBObject)?
                .value(forKey: "name") as? String ?? ""
            return name + Constants.trackSeparator
                + artist + Constants.trackSeparator
                + album + Constants.trackSeparator
                + String(duration) + Constants.trackSeparator
                + String(elapsed) + Constants.trackSeparator
                + playlist
        }

        if let trackInfo {
            handleTrackInfo(trackInfo)
        } else {
            notifyDelegate(status: "No track info")
        }
    }

    // MARK: - Private Helpers

    nonisolated private func notifyDelegate(status: String) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.delegate?.playbackSource(didUpdateStatus: status)
        }
    }

    nonisolated private func notifyDelegate(track: String, artist: String, album: String, playlist: String, duration: TimeInterval, elapsed: TimeInterval) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.delegate?.playbackSource(didUpdateTrack: track, artist: artist, album: album, playlist: playlist, duration: duration, elapsed: elapsed)
        }
    }

    nonisolated private func processTrackInfoString(_ trackInfo: String) {
        let components = trackInfo.components(separatedBy: Constants.trackSeparator)
        guard components.count >= 3 else { return }
        let trackName = components[0]
        let artist = components[1]
        let album = components[2]
        let duration = components.count > 3 ? (Double(components[3]) ?? 0) : 0
        let elapsed = components.count > 4 ? (Double(components[4]) ?? 0) : 0
        let playlist = components.count > 5 ? components[5] : ""
        stateLock.withLock { lastTrackSeenAt = Date() }
        notifyDelegate(track: trackName, artist: artist, album: album, playlist: playlist, duration: duration, elapsed: elapsed)
        logTrackIfNew(trackInfo, trackName: trackName, artist: artist, album: album)
    }

    nonisolated private func handleTrackInfo(_ trackInfo: String) {
        if trackInfo.hasPrefix(Constants.Status.errorPrefix) {
            notifyDelegate(status: "Script error")
        } else if trackInfo == Constants.Status.notRunning {
            notifyDelegate(status: "Music not running")
        } else if trackInfo == Constants.Status.notPlaying {
            handleNotPlayingState()
        } else {
            processTrackInfoString(trackInfo)
        }
    }

    nonisolated private func handleNotPlayingState() {
        let lastSeen = stateLock.withLock { lastTrackSeenAt }
        let idleDuration = Date().timeIntervalSince(lastSeen)
        if idleDuration < Constants.idleGraceWindow {
            scheduleTrackCheck(after: 0.5, reason: "idle-grace-recheck")
            return
        }
        notifyDelegate(status: "No track playing")
    }

    nonisolated private func logTrackIfNew(_ trackInfo: String, trackName: String, artist: String, album: String) {
        let dedupKey = trackName + Constants.trackSeparator + artist + Constants.trackSeparator + album
        let isNew = stateLock.withLock { () -> Bool in
            guard lastLoggedTrack != dedupKey else { return false }
            lastLoggedTrack = dedupKey
            return true
        }
        guard isNew else { return }
        Log.debug("AppleMusicSource: Now Playing → \(trackName) — \(artist) [\(album)]", category: "Music")
    }

    nonisolated private func subscribeToMusicNotifications() {
        DistributedNotificationCenter.default().addObserver(self, selector: #selector(musicPlayerInfoChanged), name: NSNotification.Name(Constants.notificationName), object: nil)
    }

    nonisolated private func performInitialTrackCheck() {
        scheduleTrackCheck(reason: "initial")
    }

    nonisolated private func setupFallbackTimer() {
        let interval = stateLock.withLock { currentCheckInterval }
        let newTimer = DispatchSource.makeTimerSource(queue: backgroundQueue)
        newTimer.schedule(deadline: .now() + interval, repeating: interval)
        newTimer.setEventHandler { [weak self] in
            guard let self, self.stateLock.withLock({ self.isTracking }) else { return }
            self.scheduleTrackCheck(reason: "timer")
        }
        stateLock.withLock { timer = newTimer }
        newTimer.activate()
    }

    nonisolated private func scheduleTrackCheck(reason: String) {
        Task { [weak self] in
            await self?.checkCurrentTrack()
        }
    }

    nonisolated private func scheduleTrackCheck(after delay: TimeInterval, reason: String) {
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            await self?.checkCurrentTrack()
        }
    }
}
