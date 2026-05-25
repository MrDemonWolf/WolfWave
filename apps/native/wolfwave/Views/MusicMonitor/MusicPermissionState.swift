//
//  MusicPermissionState.swift
//  wolfwave
//

import AppKit
import Foundation

/// Apple Events automation permission state for the Music app.
///
/// `MusicPlaybackMonitor` infers this on first track query — when the system
/// returns `errAEEventNotPermitted` the user has denied automation, and we
/// surface a banner + instruction sheet via `PermissionDeniedView`.
enum MusicPermissionState: String, Sendable {
    case unknown
    case granted
    case denied
}

/// Lightweight, read-only helpers for checking + opening the System Settings
/// Automation pane. Used by the Music permission denied flow (Screen J in
/// the redesign).
enum MusicPermissionChecker {

    /// Asks the system whether the calling process is allowed to send Apple
    /// Events to Music.app. Does not prompt; returns the cached decision.
    ///
    /// `nonisolated` so callers can dispatch this tens-of-millisecond Apple
    /// Events probe to a background `Task.detached` and keep the main thread
    /// free for UI work.
    nonisolated static func currentState() -> MusicPermissionState {
        let target = NSAppleEventDescriptor(bundleIdentifier: AppConstants.Music.bundleIdentifier)
        let status = AEDeterminePermissionToAutomateTarget(
            target.aeDesc, typeWildCard, typeWildCard, false
        )
        switch status {
        case noErr:
            return .granted
        case OSStatus(errAEEventNotPermitted):
            return .denied
        default:
            return .unknown
        }
    }

    /// Triggers the system Apple Events automation prompt for Music.app.
    ///
    /// Returns the resolved state after the prompt. If the user has previously
    /// allowed/denied, no prompt is shown and the cached decision is returned.
    static func requestAccess() -> MusicPermissionState {
        let target = NSAppleEventDescriptor(bundleIdentifier: AppConstants.Music.bundleIdentifier)
        let status = AEDeterminePermissionToAutomateTarget(
            target.aeDesc, typeWildCard, typeWildCard, true
        )
        switch status {
        case noErr:
            return .granted
        case OSStatus(errAEEventNotPermitted):
            return .denied
        default:
            return .unknown
        }
    }

    /// Opens System Settings → Privacy & Security → Automation so the user
    /// can flip the WolfWave → Music toggle.
    static func openAutomationSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation") {
            NSWorkspace.shared.open(url)
        }
    }
}
