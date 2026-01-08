//
//  MusicTracker.swift
//  packtrack
//
//  Created by Nathanial Henniges on 1/8/26.
//

import Foundation
import AppKit

/// Delegate protocol for receiving updates about music playback status.
///
/// Implement this protocol to receive callbacks when the currently playing track changes
/// or when the playback status changes (e.g., music stopped, permission needed).
protocol MusicTrackerDelegate: AnyObject {
    /// Called when a new track starts playing.
    ///
    /// - Parameters:
    ///   - tracker: The MusicTracker instance that detected the change
    ///   - track: The name of the currently playing track
    ///   - artist: The artist of the currently playing track
    ///   - album: The album of the currently playing track
    func musicTracker(_ tracker: MusicTracker, didUpdateTrack track: String, artist: String, album: String)
    
    /// Called when the playback status changes (e.g., no track playing, permission needed).
    ///
    /// - Parameters:
    ///   - tracker: The MusicTracker instance that detected the status change
    ///   - status: A human-readable status message
    func musicTracker(_ tracker: MusicTracker, didUpdateStatus status: String)
}

/// Monitors Apple Music playback and reports currently playing tracks.
///
/// This class uses AppleScript to query the Music app and receives notifications
/// when playback changes. It runs checks on a background queue to avoid blocking the UI.
class MusicTracker {
    /// The delegate that will receive music tracking updates
    weak var delegate: MusicTrackerDelegate?
    
    /// Timer for periodic track checks (fallback if notifications miss updates)
    private var timer: Timer?
    
    /// Stores the last track info to avoid duplicate console logs
    private var lastLoggedTrack: String?
    
    /// Flag to ensure we only show the permission alert once per session
    private var hasRequestedPermission = false
    
    /// Background queue for executing AppleScript commands without blocking the UI
    private let backgroundQueue = DispatchQueue(label: "com.mrdemonwolf.packtrack.musictracker", qos: .background)
    
    /// Starts monitoring Apple Music for playback changes.
    ///
    /// This method subscribes to Music.app distributed notifications and sets up a timer
    /// as a fallback mechanism. All track checks run on a background queue.
    func startTracking() {
        print("Starting music tracking...")
        
        // Subscribe to Music.app notifications
        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(musicPlayerInfoChanged),
            name: NSNotification.Name("com.apple.Music.playerInfo"),
            object: nil
        )
        
        // Check immediately on background queue
        backgroundQueue.async { [weak self] in
            self?.checkCurrentTrack()
        }
        
        // Set up timer as fallback (check every 30 seconds in case notifications miss)
        backgroundQueue.async { [weak self] in
            self?.timer = Timer.scheduledTimer(withTimeInterval: 30.0, repeats: true) { [weak self] _ in
                self?.checkCurrentTrack()
            }
            
            // Keep the run loop alive for the timer
            RunLoop.current.run()
        }
    }
    
    /// Handles distributed notifications from Music.app when playback state changes.
    ///
    /// This method is called automatically when Music.app posts a playerInfo notification.
    /// It triggers an immediate track check on the background queue.
    ///
    /// - Parameter notification: The notification from Music.app (contains playback info)
    @objc private func musicPlayerInfoChanged(_ notification: Notification) {
        // Music.app sent a notification that something changed
        print("Music notification received")
        backgroundQueue.async { [weak self] in
            self?.checkCurrentTrack()
        }
    }
    
    /// Stops monitoring Apple Music and cleans up resources.
    ///
    /// This method removes notification observers and invalidates the polling timer.
    func stopTracking() {
        DistributedNotificationCenter.default().removeObserver(self)
        timer?.invalidate()
        timer = nil
    }
    
    /// Queries Apple Music using AppleScript to get the currently playing track.
    ///
    /// This method executes an AppleScript that checks if Music.app is running and playing,
    /// then retrieves the current track information. It handles various states like
    /// app not running, not playing, or permission errors.
    private func checkCurrentTrack() {
        // AppleScript that checks if Music is running AND playing
        let script = """
        tell application "Music"
            try
                if it is running then
                    if player state is playing then
                        set trackName to name of current track
                        set trackArtist to artist of current track
                        set trackAlbum to album of current track
                        return trackName & " | " & trackArtist & " | " & trackAlbum
                    else
                        return "NOT_PLAYING"
                    end if
                else
                    return "NOT_RUNNING"
                end if
            on error errMsg
                return "ERROR: " & errMsg
            end try
        end tell
        """
        
        var error: NSDictionary?
        guard let scriptObject = NSAppleScript(source: script) else {
            print("Failed to create AppleScript")
            return
        }
        
        let output = scriptObject.executeAndReturnError(&error)
        
        if let error = error {
            let errorCode = error["NSAppleScriptErrorNumber"] as? Int ?? 0
            
            if errorCode == -1743 && !hasRequestedPermission {
                // Not authorized - show alert to user
                hasRequestedPermission = true
                DispatchQueue.main.async { [weak self] in
                    self?.showPermissionAlert()
                }
            }
            
            notifyDelegate(status: "Needs permission")
            return
        }
        
        guard let trackInfo = output.stringValue else {
            notifyDelegate(status: "No track info")
            return
        }
        
        if trackInfo.hasPrefix("ERROR:") {
            print("Script error: \(trackInfo)")
            notifyDelegate(status: "Script error")
            return
        }
        
        if trackInfo == "NOT_RUNNING" {
            notifyDelegate(status: "Music not running")
            return
        }
        
        if trackInfo == "NOT_PLAYING" {
            notifyDelegate(status: "No track playing")
            return
        }
        
        processTrackInfo(trackInfo)
    }
    
    /// Notifies the delegate of a status change on the main queue.
    ///
    /// - Parameter status: A status message describing the current state
    private func notifyDelegate(status: String) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.delegate?.musicTracker(self, didUpdateStatus: status)
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
            self.delegate?.musicTracker(self, didUpdateTrack: track, artist: artist, album: album)
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
        let components = trackInfo.components(separatedBy: " | ")
        guard components.count == 3 else {
            print("Invalid track info format: \(trackInfo)")
            return
        }
        
        let trackName = components[0]
        let artist = components[1]
        let album = components[2]
        
        notifyDelegate(track: trackName, artist: artist, album: album)
        
        // Console log if different from last track
        if lastLoggedTrack != trackInfo {
            print("✓ Now Playing: \(trackName) - \(artist) (Album: \(album))")
            lastLoggedTrack = trackInfo
        }
    }
    
    deinit {
        stopTracking()
    }
}
