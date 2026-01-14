//
//  MusicPlaybackMonitor.swift
//  wolfwave
//
//  Created by MrDemonWolf, Inc. on 1/13/26.
//

import Foundation
import AppKit
import ScriptingBridge

// MARK: - Type Aliases

typealias MusicTracker = MusicPlaybackMonitor
typealias MusicTrackerDelegate = MusicPlaybackMonitorDelegate

// MARK: - Delegate Protocol

/// Delegate protocol for receiving music playback updates from the monitor.
protocol MusicPlaybackMonitorDelegate: AnyObject {
    /// Called when a new track starts playing.
    /// - Parameters:
    ///   - monitor: The music playback monitor instance.
    ///   - track: The track name.
    ///   - artist: The artist name.
    ///   - album: The album name.
    func musicPlaybackMonitor(_ monitor: MusicPlaybackMonitor, didUpdateTrack track: String, artist: String, album: String)
    
    /// Called when the playback status changes (not running, not playing, etc.).
    /// - Parameters:
    ///   - monitor: The music playback monitor instance.
    ///   - status: A human-readable status message.
    func musicPlaybackMonitor(_ monitor: MusicPlaybackMonitor, didUpdateStatus status: String)
}

// MARK: - Music Playback Monitor

/// Monitors Apple Music playback using ScriptingBridge and distributed notifications.
///
/// This class provides real-time monitoring of Apple Music playback without spawning
/// `osascript` processes, avoiding XProtect warnings. It uses ScriptingBridge (Apple Events)
/// to communicate directly with Music.app and subscribes to distributed notifications for
/// immediate playback changes.
///
/// Delegate notifications:
/// - The monitor guarantees that delegate callbacks are delivered on the main thread.
///   Consumers can safely update UI from the delegate methods.
///
/// Usage example:
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
    
    // MARK: - Constants
    
    private enum Constants {
        /// Apple Music's distributed notification name for player info changes
        static let musicBundleIdentifier = "com.apple.Music"
        static let notificationName = "com.apple.Music.playerInfo"
        static let queueLabel = "com.mrdemonwolf.wolfwave.musicplaybackmonitor"
        
        /// Polling interval for fallback timer (in seconds)
        static let checkInterval: TimeInterval = 1.0
        
        /// Separator used when combining track info into a single string
        static let trackSeparator = " | "
        
        /// Minimum time between processing duplicate notifications (in seconds)
        static let notificationDedupWindow: TimeInterval = 0.75
        
        /// Grace period before reporting "not playing" status (in seconds)
        static let idleGraceWindow: TimeInterval = 2.0
        
        /// ScriptingBridge FourCharCode for Music.app player state "playing"
        /// Value: 'kPSP' = 0x6b505350 = 1800426320
        static let playerStatePlaying: UInt32 = 1800426320
        
        enum Status {
            static let notRunning = "NOT_RUNNING"
            static let notPlaying = "NOT_PLAYING"
            static let errorPrefix = "ERROR:"
        }
    }
    
    // MARK: - Properties
    
    // MARK: - Properties
    
    /// Delegate to receive track and status updates
    weak var delegate: MusicPlaybackMonitorDelegate?
    
    /// Fallback timer for periodic track checks
    private var timer: DispatchSourceTimer?
    
    /// Cache of the last logged track to avoid duplicate log entries
    private var lastLoggedTrack: String?
    
    /// Timestamp of when we last saw a valid track playing
    private var lastTrackSeenAt: Date = .distantPast
    
    /// Timestamp of when we last processed a notification to deduplicate rapid-fire events
    private var lastNotificationAt: Date = .distantPast
    
    /// Whether monitoring is currently active
    private var isTracking = false
    
    /// Background queue for asynchronous track checks
    private let backgroundQueue = DispatchQueue(
        label: Constants.queueLabel,
        qos: .userInitiated
    )
    
    // MARK: - Public Methods
    
    /// Starts monitoring Apple Music playback.
    ///
    /// Subscribes to distributed notifications from Music.app and sets up a fallback
    /// polling timer. Safe to call multiple times - subsequent calls are ignored if
    /// already tracking.
    func startTracking() {
        guard !isTracking else { return }
        isTracking = true
        Log.info("Starting music playback monitoring via ScriptingBridge", category: "MusicPlaybackMonitor")
        
        subscribeToMusicNotifications()
        performInitialTrackCheck()
        setupFallbackTimer()
    }
    
    /// Stops monitoring Apple Music playback and cleans up resources.
    ///
    /// Unsubscribes from notifications and cancels the polling timer. Safe to call
    /// multiple times - subsequent calls are ignored if not tracking.
    func stopTracking() {
        guard isTracking else {
            Log.debug("stopTracking called while already stopped", category: "MusicPlaybackMonitor")
            return
        }
        DistributedNotificationCenter.default().removeObserver(self)
        timer?.cancel()
        timer = nil
        isTracking = false
        Log.info("Stopped music playback monitoring", category: "MusicPlaybackMonitor")
    }
    
    // MARK: - Notification Handling
    
    /// Handles distributed notifications from Music.app when player info changes.
    @objc private func musicPlayerInfoChanged(_ notification: Notification) {
        let now = Date()
        guard now.timeIntervalSince(lastNotificationAt) >= Constants.notificationDedupWindow else {
            Log.debug("Skipping duplicate music notification", category: "MusicPlaybackMonitor")
            return
        }
        lastNotificationAt = now
        Log.debug("Music notification received", category: "MusicPlaybackMonitor")
        scheduleTrackCheck(reason: "notification")
    }
    
    // MARK: - Track Checking
    
    // MARK: - Track Checking
    
    /// Queries Apple Music via ScriptingBridge to get the currently playing track.
    ///
    /// This method uses ScriptingBridge (Apple Events) instead of spawning `osascript`
    /// processes, which avoids XProtect warnings. It checks if Music.app is running,
    /// queries the player state, and retrieves track information if playing.
    ///
    /// **How it works:**
    /// 1. Checks if Music.app is running via NSRunningApplication
    /// 2. Creates an SBApplication connection to Music.app
    /// 3. Reads the `playerState` property via KVC (returns FourCharCode enum)
    /// 4. If playing (0x6b505350 = 'kPSP'), reads currentTrack properties
    private func checkCurrentTrack() {
        // Step 1: Check if Music.app is running
        let isRunning = NSRunningApplication
            .runningApplications(withBundleIdentifier: Constants.musicBundleIdentifier)
            .first != nil
        
        guard isRunning else {
            handleTrackInfo(Constants.Status.notRunning)
            return
        }

        // Step 2: Create ScriptingBridge connection to Music.app
        guard let musicApp = SBApplication(bundleIdentifier: Constants.musicBundleIdentifier) else {
            Log.error("Failed to create SBApplication for Music", category: "MusicPlaybackMonitor")
            notifyDelegate(status: "No track info")
            return
        }

        // Step 3: Read player state using Key-Value Coding
        guard let stateObj = musicApp.value(forKey: "playerState") else {
            Log.warn("Unable to read playerState via ScriptingBridge", category: "MusicPlaybackMonitor")
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
            Log.warn("Invalid track info format: \(trackInfo)", category: "MusicPlaybackMonitor")
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
            Log.error("Script error: \(trackInfo)", category: "MusicPlaybackMonitor")
            notifyDelegate(status: "Script error")
        } else if trackInfo == Constants.Status.notRunning {
            Log.info("Music app is not running", category: "MusicPlaybackMonitor")
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
            Log.debug("Ignoring transient idle (\(String(format: "%.1f", idleDuration))s since last track)", category: "MusicPlaybackMonitor")
            scheduleTrackCheck(after: 0.5, reason: "idle-grace-recheck")
            return
        }
        Log.debug("Music app is idle (not playing)", category: "MusicPlaybackMonitor")
        notifyDelegate(status: "No track playing")
    }
    
    /// Logs track information if it's different from the last logged track.
    private func logTrackIfNew(_ trackInfo: String, trackName: String, artist: String, album: String) {
        guard lastLoggedTrack != trackInfo else { return }
        Log.info("Now Playing → \(trackName) — \(artist) [\(album)]", category: "MusicPlaybackMonitor")
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
