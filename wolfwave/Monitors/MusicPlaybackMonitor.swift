//
//  MusicPlaybackMonitor.swift
//  packtrack
//
//  Created by Nathanial Henniges on 1/8/26.
//

import Foundation
import AppKit

typealias MusicTracker = MusicPlaybackMonitor
typealias MusicTrackerDelegate = MusicPlaybackMonitorDelegate

protocol MusicPlaybackMonitorDelegate: AnyObject {
    func musicPlaybackMonitor(_ monitor: MusicPlaybackMonitor, didUpdateTrack track: String, artist: String, album: String)
    func musicPlaybackMonitor(_ monitor: MusicPlaybackMonitor, didUpdateStatus status: String)
}

class MusicPlaybackMonitor {
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
    
    weak var delegate: MusicPlaybackMonitorDelegate?
    private var timer: DispatchSourceTimer?
    private var lastLoggedTrack: String?
    private var lastTrackSeenAt: Date = .distantPast
    private var hasRequestedPermission = false
    private var isTracking = false
    private let backgroundQueue = DispatchQueue(
        label: Constants.queueLabel,
        qos: .userInitiated
    )

    private var isCheckInProgress = false
    private var hasPendingCheck = false
    private var lastNotificationAt = Date.distantPast
    
    func startTracking() {
        guard !isTracking else { return }
        isTracking = true
        Log.info("Starting music playback monitoring…", category: "MusicPlaybackMonitor")
        
        subscribeToMusicNotifications()
        performInitialTrackCheck()
        setupFallbackTimer()
    }
    
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
    
    private func notifyDelegate(status: String) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.delegate?.musicPlaybackMonitor(self, didUpdateStatus: status)
        }
    }
    
    private func notifyDelegate(track: String, artist: String, album: String) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.delegate?.musicPlaybackMonitor(self, didUpdateTrack: track, artist: artist, album: album)
        }
    }
    
    private func showPermissionAlert() {
        let alert = NSAlert()
        alert.messageText = "Permission Required"
        alert.informativeText = "Packtrack needs permission to access Apple Music.\n\n1. Open System Settings\n2. Go to Privacy & Security → Automation\n3. Enable 'Music' for Packtrack\n\nThen restart Packtrack."
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Open System Settings")
        alert.addButton(withTitle: "OK")
        
        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation") {
                NSWorkspace.shared.open(url)
            }
        }
    }
    
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
