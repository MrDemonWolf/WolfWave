//
//  MusicPlaybackMonitor.swift
//  packtrack
//
//  Created by Nathanial Henniges on 1/8/26.
//

import Foundation
import AppKit

// Backward compatibility after renaming from MusicTracker
typealias MusicTracker = MusicPlaybackMonitor
typealias MusicTrackerDelegate = MusicPlaybackMonitorDelegate

/// Delegate protocol for receiving updates about music playback status.
///
/// Implement this protocol to receive callbacks when the currently playing track changes
/// or when the playback status changes (e.g., music stopped, permission needed).
protocol MusicPlaybackMonitorDelegate: AnyObject {
    /// Called when a new track starts playing.
    ///
    /// - Parameters:
    ///   - monitor: The MusicPlaybackMonitor instance that detected the change
    ///   - track: The name of the currently playing track
    ///   - artist: The artist of the currently playing track
    ///   - album: The album of the currently playing track
    func musicPlaybackMonitor(_ monitor: MusicPlaybackMonitor, didUpdateTrack track: String, artist: String, album: String)
    
    /// Called when the playback status changes (e.g., no track playing, permission needed).
    ///
    /// - Parameters:
    ///   - monitor: The MusicPlaybackMonitor instance that detected the status change
    ///   - status: A human-readable status message
    func musicPlaybackMonitor(_ monitor: MusicPlaybackMonitor, didUpdateStatus status: String)
}

/// Monitors Apple Music playback and reports currently playing tracks.
///
/// This class uses AppleScript to query the Music app and receives notifications
/// when playback changes. It runs checks on a background queue to avoid blocking the UI.
class MusicPlaybackMonitor {
    // MARK: - Constants
    
    fileprivate enum Constants {
        static let notificationName = "com.apple.Music.playerInfo"
        static let queueLabel = "com.mrdemonwolf.packtrack.musicplaybackmonitor"
        static let checkInterval: TimeInterval = 30.0
        static let trackSeparator = " | "
        static let permissionErrorCode = -1743
        static let notificationDedupWindow: TimeInterval = 0.75
        static let idleGraceWindow: TimeInterval = 2.0
        
        enum Status {
            static let notRunning = "NOT_RUNNING"
            static let notPlaying = "NOT_PLAYING"
            static let errorPrefix = "ERROR:"
        }
    }
    
    // MARK: - Properties
    
    /// The delegate that will receive music tracking updates
    weak var delegate: MusicPlaybackMonitorDelegate?
    
    /// Timer for periodic track checks (fallback if notifications miss updates)
    private var timer: DispatchSourceTimer?
    
    /// Stores the last track info to avoid duplicate console logs
    private var lastLoggedTrack: String?

    /// Timestamp for last successful track detection, used to smooth transient idle states
    private var lastTrackSeenAt: Date = .distantPast
    
    /// Flag to ensure we only show the permission alert once per session
    private var hasRequestedPermission = false

    /// Indicates whether tracking is currently active to avoid duplicate observers/timers
    private var isTracking = false
    
    /// Background queue for executing AppleScript commands without blocking the UI
    private let backgroundQueue = DispatchQueue(
        label: Constants.queueLabel,
        qos: .userInitiated
    )

    /// Prevents overlapping checks; allows one pending rerun to capture latest state
    private var isCheckInProgress = false
    private var hasPendingCheck = false

    /// Dedupes rapid-fire distributed notifications
    private var lastNotificationAt = Date.distantPast
    
    // MARK: - Public Methods
    
    /// Starts monitoring Apple Music for playback changes.
    ///
    /// This method subscribes to Music.app distributed notifications and sets up a timer
    /// as a fallback mechanism. All track checks run on a background queue.
    func startTracking() {
        guard !isTracking else { return }
        isTracking = true
        Log.info("Starting music playback monitoring…", category: "MusicPlaybackMonitor")
        
        subscribeToMusicNotifications()
        performInitialTrackCheck()
        setupFallbackTimer()
    }
    
    /// Handles distributed notifications from Music.app when playback state changes.
    ///
    /// This method is called automatically when Music.app posts a playerInfo notification.
    /// It triggers an immediate track check on the background queue.
    ///
    /// - Parameter notification: The notification from Music.app (contains playback info)
    @objc private func musicPlayerInfoChanged(_ notification: Notification) {
        let now = Date()
        guard now.timeIntervalSince(lastNotificationAt) >= Constants.notificationDedupWindow else {
            Log.debug("Skipping duplicate music notification", category: "MusicPlaybackMonitor")
            return
        }
        lastNotificationAt = now
        // Music.app sent a notification that something changed
        Log.debug("Music notification received", category: "MusicPlaybackMonitor")
        scheduleTrackCheck(reason: "notification")
    }
    
    /// Stops monitoring Apple Music and cleans up resources.
    ///
    /// This method removes notification observers and invalidates the polling timer.
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
    
    /// Queries Apple Music using AppleScript to get the currently playing track.
    ///
    /// This method executes an AppleScript that checks if Music.app is running and playing,
    /// then retrieves the current track information. It handles various states like
    /// app not running, not playing, or permission errors.
    private func checkCurrentTrack() {
        let script = createMusicQueryScript()
        
        guard let scriptObject = NSAppleScript(source: script) else {
            Log.error("Failed to create AppleScript", category: "MusicPlaybackMonitor")
            return
        }
        
        var error: NSDictionary?
        let output = scriptObject.executeAndReturnError(&error)
        
        if let error = error {
            handleScriptError(error)
            return
        }
        
        guard let trackInfo = output.stringValue else {
            Log.warn("No track info returned from AppleScript", category: "MusicPlaybackMonitor")
            notifyDelegate(status: "No track info")
            return
        }
        
        handleTrackInfo(trackInfo)
    }
    
    /// Notifies the delegate of a status change on the main queue.
    ///
    /// - Parameter status: A status message describing the current state
    private func notifyDelegate(status: String) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.delegate?.musicPlaybackMonitor(self, didUpdateStatus: status)
        }
    }
    
    /// Notifies the delegate of a track change on the main queue.
    ///
    /// - Parameters:
    ///   - track: The track name
    ///   - artist: The artist name
    ///   - album: The album name
    private func notifyDelegate(track: String, artist: String, album: String) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.delegate?.musicPlaybackMonitor(self, didUpdateTrack: track, artist: artist, album: album)
        }
    }
    
    /// Displays an alert to the user explaining how to grant Music.app automation permission.
    ///
    /// This alert provides step-by-step instructions and offers to open System Settings directly.
    /// It's shown only once per session when AppleScript access is denied.
    private func showPermissionAlert() {
        let alert = NSAlert()
        alert.messageText = "Permission Required"
        alert.informativeText = "Packtrack needs permission to access Apple Music.\n\n1. Open System Settings\n2. Go to Privacy & Security → Automation\n3. Enable 'Music' for Packtrack\n\nThen restart Packtrack."
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Open System Settings")
        alert.addButton(withTitle: "OK")
        
        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            // Open System Settings to Privacy
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation") {
                NSWorkspace.shared.open(url)
            }
        }
    }
    
    /// Parses track information string and notifies the delegate.
    ///
    /// The track info is expected to be in the format: "trackName | artist | album"
    /// This method also logs new tracks to the console (avoiding duplicates).
    ///
    /// - Parameter trackInfo: A pipe-separated string containing track, artist, and album
    private func processTrackInfo(_ trackInfo: String) {
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
    
    // MARK: - Private Helpers
    
    private func subscribeToMusicNotifications() {
        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(musicPlayerInfoChanged),
            name: NSNotification.Name(Constants.notificationName),
            object: nil
        )
    }
    
    private func performInitialTrackCheck() {
        scheduleTrackCheck(reason: "initial")
    }
    
    private func setupFallbackTimer() {
        let timer = DispatchSource.makeTimerSource(queue: backgroundQueue)
        timer.schedule(deadline: .now() + Constants.checkInterval, repeating: Constants.checkInterval)
        timer.setEventHandler { [weak self] in
            self?.scheduleTrackCheck(reason: "timer")
        }
        timer.activate()
        self.timer = timer
    }

    private func scheduleTrackCheck(reason: String) {
        backgroundQueue.async { [weak self] in
            guard let self else { return }
            if self.isCheckInProgress {
                self.hasPendingCheck = true
                Log.debug("Queueing track check while another is running (reason: \(reason))", category: "MusicPlaybackMonitor")
                return
            }

            self.isCheckInProgress = true
            self.hasPendingCheck = false

            while true {
                self.checkCurrentTrack()
                let rerun = self.hasPendingCheck
                self.hasPendingCheck = false
                if rerun {
                    Log.debug("Running pending track check", category: "MusicPlaybackMonitor")
                    continue
                }
                break
            }

            self.isCheckInProgress = false
        }
    }

    private func scheduleTrackCheck(after delay: TimeInterval, reason: String) {
        backgroundQueue.asyncAfter(deadline: .now() + delay) { [weak self] in
            self?.scheduleTrackCheck(reason: reason)
        }
    }
    
    private func createMusicQueryScript() -> String {
        return """
        tell application "Music"
            try
                if it is running then
                    if player state is playing then
                        set trackName to name of current track
                        set trackArtist to artist of current track
                        set trackAlbum to album of current track
                        return trackName & "\(Constants.trackSeparator)" & trackArtist & "\(Constants.trackSeparator)" & trackAlbum
                    else
                        return "\(Constants.Status.notPlaying)"
                    end if
                else
                    return "\(Constants.Status.notRunning)"
                end if
            on error errMsg
                return "\(Constants.Status.errorPrefix)" & errMsg
            end try
        end tell
        """
    }
    
    private func handleScriptError(_ error: NSDictionary) {
        let errorCode = error["NSAppleScriptErrorNumber"] as? Int ?? 0
        
        if errorCode == Constants.permissionErrorCode && !hasRequestedPermission {
            hasRequestedPermission = true
            DispatchQueue.main.async { [weak self] in
                self?.showPermissionAlert()
            }
        }
        Log.warn("AppleScript permission or execution error (code: \(errorCode))", category: "MusicPlaybackMonitor")
        notifyDelegate(status: "Needs permission")
    }
    
    private func handleTrackInfo(_ trackInfo: String) {
        if trackInfo.hasPrefix(Constants.Status.errorPrefix) {
            Log.error("Script error: \(trackInfo)", category: "MusicPlaybackMonitor")
            notifyDelegate(status: "Script error")
        } else if trackInfo == Constants.Status.notRunning {
            Log.info("Music app is not running", category: "MusicPlaybackMonitor")
            notifyDelegate(status: "Music not running")
        } else if trackInfo == Constants.Status.notPlaying {
            let idleDuration = Date().timeIntervalSince(lastTrackSeenAt)
            if idleDuration < Constants.idleGraceWindow {
                Log.debug("Ignoring transient idle (\(idleDuration)s since last track)", category: "MusicPlaybackMonitor")
                scheduleTrackCheck(after: 0.5, reason: "idle-grace-recheck")
                return
            }
            Log.debug("Music app is idle (not playing)", category: "MusicPlaybackMonitor")
            notifyDelegate(status: "No track playing")
        } else {
            processTrackInfo(trackInfo)
        }
    }
    
    private func logTrackIfNew(_ trackInfo: String, trackName: String, artist: String, album: String) {
        guard lastLoggedTrack != trackInfo else { return }
        Log.info("Now Playing → \(trackName) — \(artist) [\(album)]", category: "MusicPlaybackMonitor")
        lastLoggedTrack = trackInfo
    }
    
    deinit {
        stopTracking()
    }
}
