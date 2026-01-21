//
//  MusicPlaybackMonitor.swift
//  wolfwave
//
//  Created by MrDemonWolf, Inc. on 1/17/26.
//

import Foundation
import AppKit
import ScriptingBridge

typealias MusicTracker = MusicPlaybackMonitor
typealias MusicTrackerDelegate = MusicPlaybackMonitorDelegate

/// Delegate protocol for receiving music playback updates.
protocol MusicPlaybackMonitorDelegate: AnyObject {
    /// Called when a new track starts playing.
    func musicPlaybackMonitor(_ monitor: MusicPlaybackMonitor, didUpdateTrack track: String, artist: String, album: String)
    
    /// Called when the playback status changes (not running, not playing, etc.).
    func musicPlaybackMonitor(_ monitor: MusicPlaybackMonitor, didUpdateStatus status: String)
}

/// Monitors Apple Music playback using ScriptingBridge and distributed notifications.
///
/// Uses ScriptingBridge to communicate with Music.app directly without spawning osascript.
/// Subscribes to distributed notifications for real-time updates.
/// Delegate callbacks are delivered on the main thread.
///
/// Usage:
/// ```swift
/// let monitor = MusicPlaybackMonitor()
/// monitor.delegate = self
/// monitor.startTracking()
/// ```
///
/// Requirements:
/// - Entitlements: `com.apple.security.automation.apple-events`
/// - Info.plist: `NSAppleEventsUsageDescription`
class MusicPlaybackMonitor {
    
    private enum Constants {
        static let musicBundleIdentifier = "com.apple.Music"
        static let notificationName = "com.apple.Music.playerInfo"
        static let queueLabel = "com.mrdemonwolf.wolfwave.musicplaybackmonitor"
        static let checkInterval: TimeInterval = 1.0
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
    
    weak var delegate: MusicPlaybackMonitorDelegate?
    
    private var timer: DispatchSourceTimer?
    private var lastLoggedTrack: String?
    private var lastTrackSeenAt: Date = .distantPast
    private var lastNotificationAt: Date = .distantPast
    private var isTracking = false
    
    private let backgroundQueue = DispatchQueue(
        label: Constants.queueLabel,
        qos: .userInitiated
    )
    
    func startTracking() {
        guard !isTracking else { return }
        isTracking = true
        
        subscribeToMusicNotifications()
        performInitialTrackCheck()
        setupFallbackTimer()
    }
    
    func stopTracking() {
        guard isTracking else {
            return
        }
        DistributedNotificationCenter.default().removeObserver(self)
        timer?.cancel()
        timer = nil
        isTracking = false
    }
    
    @objc private func musicPlayerInfoChanged(_ notification: Notification) {
        let now = Date()
        guard now.timeIntervalSince(lastNotificationAt) >= Constants.notificationDedupWindow else {
            return
        }
        lastNotificationAt = now
        Log.debug("Music notification received", category: "MusicPlaybackMonitor")
        scheduleTrackCheck(reason: "notification")
    }
    
    private func checkCurrentTrack() {
        let isRunning = NSRunningApplication
            .runningApplications(withBundleIdentifier: Constants.musicBundleIdentifier)
            .first != nil
        
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

        // Step 4: Check if currently playing
        // playerState returns a FourCharCode: 'kPSP' (0x6b505350 = 1800426320) = playing
        let isPlaying: Bool
        if let stateNum = stateObj as? NSNumber {
            isPlaying = (stateNum.uint32Value == Constants.playerStatePlaying)
        } else {
            isPlaying = false
        }
        
        // Step 5: If playing, retrieve track information
        if isPlaying {
            if let track = musicApp.value(forKey: "currentTrack") as? SBObject {
                let name = track.value(forKey: "name") as? String ?? ""
                let artist = track.value(forKey: "artist") as? String ?? ""
                let album = track.value(forKey: "album") as? String ?? ""
                
                let combined = name + Constants.trackSeparator + artist + Constants.trackSeparator + album
                handleTrackInfo(combined)
            } else {
                handleTrackInfo(Constants.Status.notPlaying)
            }
        } else {
            handleTrackInfo(Constants.Status.notPlaying)
        }
    }
    
    // MARK: - Delegate Notifications
    
    /// Notifies the delegate of a status change on the main thread.
    private func notifyDelegate(status: String) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.delegate?.musicPlaybackMonitor(self, didUpdateStatus: status)
        }
    }
    
    /// Notifies the delegate of a track change on the main thread.
    private func notifyDelegate(track: String, artist: String, album: String) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.delegate?.musicPlaybackMonitor(self, didUpdateTrack: track, artist: artist, album: album)
        }
    }
    
    // MARK: - Track Info Processing
    
    /// Processes track info string received from Music.app and notifies the delegate.
    private func processTrackInfoString(_ trackInfo: String) {
        let components = trackInfo.components(separatedBy: Constants.trackSeparator)
        guard components.count == 3 else {
            return
        }
        
        let (trackName, artist, album) = (components[0], components[1], components[2])
        lastTrackSeenAt = Date()
        notifyDelegate(track: trackName, artist: artist, album: album)
        logTrackIfNew(trackInfo, trackName: trackName, artist: artist, album: album)
    }
    
    /// Handles track info string and routes to appropriate handler based on status.
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
    
    /// Handles the "not playing" state with grace period to avoid transient stops.
    private func handleNotPlayingState() {
        let idleDuration = Date().timeIntervalSince(lastTrackSeenAt)
        if idleDuration < Constants.idleGraceWindow {
            scheduleTrackCheck(after: 0.5, reason: "idle-grace-recheck")
            return
        }
        notifyDelegate(status: "No track playing")
    }
    
    /// Logs track information if it's different from the last logged track.
    private func logTrackIfNew(_ trackInfo: String, trackName: String, artist: String, album: String) {
        guard lastLoggedTrack != trackInfo else { return }
        Log.info("Now Playing → \(trackName) — \(artist) [\(album)]", category: "Music")
        lastLoggedTrack = trackInfo
    }
    
    // MARK: - Setup & Scheduling
    
    // MARK: - Setup & Scheduling
    
    /// Subscribes to distributed notifications from Music.app.
    private func subscribeToMusicNotifications() {
        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(musicPlayerInfoChanged),
            name: NSNotification.Name(Constants.notificationName),
            object: nil
        )
    }
    
    /// Performs an initial track check when monitoring starts.
    private func performInitialTrackCheck() {
        scheduleTrackCheck(reason: "initial")
    }
    
    /// Sets up a fallback timer that periodically checks track status.
    ///
    /// The timer acts as a fallback in case distributed notifications are missed.
    /// It fires every `checkInterval` seconds on the background queue.
    private func setupFallbackTimer() {
        let timer = DispatchSource.makeTimerSource(queue: backgroundQueue)
        timer.schedule(deadline: .now() + Constants.checkInterval, repeating: Constants.checkInterval)
        timer.setEventHandler { [weak self] in
            self?.scheduleTrackCheck(reason: "timer")
        }
        timer.activate()
        self.timer = timer
    }

    /// Schedules an immediate track check on the background queue.
    /// - Parameter reason: A descriptive reason for logging purposes (e.g., "notification", "timer").
    private func scheduleTrackCheck(reason: String) {
        backgroundQueue.async { [weak self] in
            self?.checkCurrentTrack()
        }
    }

    /// Schedules a delayed track check on the background queue.
    /// - Parameters:
    ///   - delay: The delay in seconds before executing the check.
    ///   - reason: A descriptive reason for logging purposes (e.g., "idle-grace-recheck").
    private func scheduleTrackCheck(after delay: TimeInterval, reason: String) {
        backgroundQueue.asyncAfter(deadline: .now() + delay) { [weak self] in
            self?.checkCurrentTrack()
        }
    }
    
    // MARK: - Lifecycle
    
    /// Automatically stops tracking when the monitor is deallocated.
    deinit {
        stopTracking()
    }
}
