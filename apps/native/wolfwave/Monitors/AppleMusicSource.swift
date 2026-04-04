//
//  AppleMusicSource.swift
//  wolfwave
//
//  Created by MrDemonWolf, Inc. on 3/28/26.
//

import Foundation
import AppKit
import ScriptingBridge

class AppleMusicSource: PlaybackSource {

    private enum Constants {
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

    private var currentCheckInterval: TimeInterval = Constants.checkInterval
    private var timer: DispatchSourceTimer?
    private var lastLoggedTrack: String?
    private var lastTrackSeenAt: Date = .distantPast
    private var lastNotificationAt: Date = .distantPast
    private var isTracking = false
    private let trackingLock = NSLock()
    private var pendingDuration: TimeInterval = 0
    private var pendingElapsed: TimeInterval = 0

    private let backgroundQueue = DispatchQueue(label: Constants.queueLabel, qos: .utility)

    func startTracking() {
        let alreadyTracking = trackingLock.withLock { () -> Bool in
            guard !isTracking else { return true }
            isTracking = true
            return false
        }
        guard !alreadyTracking else { return }
        subscribeToMusicNotifications()
        performInitialTrackCheck()
        setupFallbackTimer()
    }

    func stopTracking() {
        let wasTracking = trackingLock.withLock { () -> Bool in
            guard isTracking else { return false }
            isTracking = false
            return true
        }
        guard wasTracking else { return }
        DistributedNotificationCenter.default().removeObserver(self)
        timer?.cancel()
        timer = nil
        backgroundQueue.sync {}
    }

    func updateCheckInterval(_ interval: TimeInterval) {
        guard trackingLock.withLock({ isTracking }) else { return }
        currentCheckInterval = max(interval, 1.0)
        timer?.cancel()
        timer = nil
        setupFallbackTimer()
    }

    @objc private func musicPlayerInfoChanged(_ notification: Notification) {
        let now = Date()
        guard now.timeIntervalSince(lastNotificationAt) >= Constants.notificationDedupWindow else { return }
        lastNotificationAt = now
        Log.debug("AppleMusicSource: Music notification received", category: "Music")
        scheduleTrackCheck(reason: "notification")
    }

    private func checkCurrentTrack() {
        let isRunning = NSRunningApplication.runningApplications(withBundleIdentifier: Constants.musicBundleIdentifier).first != nil
        guard isRunning else {
            handleTrackInfo(Constants.Status.notRunning)
            return
        }
        guard let musicApp = SBApplication(bundleIdentifier: Constants.musicBundleIdentifier) else {
            notifyDelegate(status: "No track info")
            return
        }
        guard let stateObj = musicApp.value(forKey: "playerState") else {
            notifyDelegate(status: "No track info")
            return
        }
        let isPlaying: Bool
        if let stateNum = stateObj as? NSNumber {
            isPlaying = (stateNum.uint32Value == Constants.playerStatePlaying)
        } else {
            isPlaying = false
        }
        if isPlaying {
            if let track = musicApp.value(forKey: "currentTrack") as? SBObject {
                let name = track.value(forKey: "name") as? String ?? ""
                let artist = track.value(forKey: "artist") as? String ?? ""
                let album = track.value(forKey: "album") as? String ?? ""
                let duration = (track.value(forKey: "duration") as? Double) ?? 0
                let elapsed = (musicApp.value(forKey: "playerPosition") as? Double) ?? 0
                let combined = name + Constants.trackSeparator + artist + Constants.trackSeparator + album + Constants.trackSeparator + String(duration) + Constants.trackSeparator + String(elapsed)
                handleTrackInfo(combined)
            } else {
                handleTrackInfo(Constants.Status.notPlaying)
            }
        } else {
            handleTrackInfo(Constants.Status.notPlaying)
        }
    }

    private func notifyDelegate(status: String) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.delegate?.playbackSource(didUpdateStatus: status)
        }
    }

    private func notifyDelegate(track: String, artist: String, album: String, duration: TimeInterval, elapsed: TimeInterval) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.delegate?.playbackSource(didUpdateTrack: track, artist: artist, album: album, duration: duration, elapsed: elapsed)
        }
    }

    private func processTrackInfoString(_ trackInfo: String) {
        let components = trackInfo.components(separatedBy: Constants.trackSeparator)
        guard components.count >= 3 else { return }
        let trackName = components[0]
        let artist = components[1]
        let album = components[2]
        let duration = components.count > 3 ? (Double(components[3]) ?? 0) : 0
        let elapsed = components.count > 4 ? (Double(components[4]) ?? 0) : 0
        lastTrackSeenAt = Date()
        notifyDelegate(track: trackName, artist: artist, album: album, duration: duration, elapsed: elapsed)
        logTrackIfNew(trackInfo, trackName: trackName, artist: artist, album: album)
    }

    private func handleTrackInfo(_ trackInfo: String) {
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

    private func handleNotPlayingState() {
        let idleDuration = Date().timeIntervalSince(lastTrackSeenAt)
        if idleDuration < Constants.idleGraceWindow {
            scheduleTrackCheck(after: 0.5, reason: "idle-grace-recheck")
            return
        }
        notifyDelegate(status: "No track playing")
    }

    private func logTrackIfNew(_ trackInfo: String, trackName: String, artist: String, album: String) {
        let dedupKey = trackName + Constants.trackSeparator + artist + Constants.trackSeparator + album
        guard lastLoggedTrack != dedupKey else { return }
        Log.debug("AppleMusicSource: Now Playing → \(trackName) — \(artist) [\(album)]", category: "Music")
        lastLoggedTrack = dedupKey
    }

    private func subscribeToMusicNotifications() {
        DistributedNotificationCenter.default().addObserver(self, selector: #selector(musicPlayerInfoChanged), name: NSNotification.Name(Constants.notificationName), object: nil)
    }

    private func performInitialTrackCheck() {
        scheduleTrackCheck(reason: "initial")
    }

    private func setupFallbackTimer() {
        let timer = DispatchSource.makeTimerSource(queue: backgroundQueue)
        timer.schedule(deadline: .now() + currentCheckInterval, repeating: currentCheckInterval)
        timer.setEventHandler { [weak self] in
            guard let self = self, self.trackingLock.withLock({ self.isTracking }) else { return }
            self.scheduleTrackCheck(reason: "timer")
        }
        timer.activate()
        self.timer = timer
    }

    private func scheduleTrackCheck(reason: String) {
        backgroundQueue.async { [weak self] in self?.checkCurrentTrack() }
    }

    private func scheduleTrackCheck(after delay: TimeInterval, reason: String) {
        backgroundQueue.asyncAfter(deadline: .now() + delay) { [weak self] in self?.checkCurrentTrack() }
    }

    deinit { stopTracking() }
}
