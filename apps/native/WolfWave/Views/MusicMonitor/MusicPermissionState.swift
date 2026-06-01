//
//  MusicPermissionState.swift
//  WolfWave
//
//  Created by Nathanial Henniges on 2026-05-07.
//  Copyright © 2026 MrDemonWolf, Inc. All rights reserved.
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
        let state = resolve(status: status, lastKnown: loadPersisted())
        persistIfDefinitive(state)
        return state
    }

    /// Maps an `AEDeterminePermissionToAutomateTarget` status into a permission
    /// state. Pure (no Apple Events I/O) so the mapping — including the closed-
    /// Music fallback — is unit-testable.
    ///
    /// When Music.app isn't running, the probe returns `procNotFound` rather than
    /// the real TCC decision. The automation grant persists independent of whether
    /// Music is open, so we fall back to `lastKnown` instead of reporting
    /// `.unknown` — otherwise a closed Music app blanks the now-playing UI and
    /// re-shows the "Allow Music access" prompt for an already-granted user.
    nonisolated static func resolve(
        status: OSStatus,
        lastKnown: MusicPermissionState?
    ) -> MusicPermissionState {
        switch status {
        case noErr:
            return .granted
        case OSStatus(errAEEventNotPermitted):
            return .denied
        case OSStatus(procNotFound):
            return lastKnown ?? .unknown
        default:
            return .unknown
        }
    }

    /// Triggers the system Apple Events automation prompt for Music.app.
    ///
    /// Returns the resolved state after the prompt. If the user has previously
    /// allowed/denied, no prompt is shown and the cached decision is returned.
    static func requestAccess() async -> MusicPermissionState {
        // The system automation prompt only fires for a *running* target. With
        // Music.app closed the probe returns `procNotFound` and silently no-ops,
        // so the user never sees the grant dialog. Launch Music first (without
        // stealing focus), then prompt.
        await ensureMusicRunning()
        let state = await Task.detached(priority: .userInitiated) {
            let target = NSAppleEventDescriptor(bundleIdentifier: AppConstants.Music.bundleIdentifier)
            let status = AEDeterminePermissionToAutomateTarget(
                target.aeDesc, typeWildCard, typeWildCard, true
            )
            return resolve(status: status, lastKnown: loadPersisted())
        }.value
        persistIfDefinitive(state)
        return state
    }

    /// True when Music.app currently has a running process.
    nonisolated static var isMusicRunning: Bool {
        !NSRunningApplication
            .runningApplications(withBundleIdentifier: AppConstants.Music.bundleIdentifier)
            .isEmpty
    }

    /// Launches Music.app in the background (no focus steal) if it isn't already
    /// running, then waits briefly for the process to register so a following
    /// Apple Events probe can actually reach it. Bounded so a launch failure
    /// can't hang the caller.
    nonisolated static func ensureMusicRunning() async {
        if isMusicRunning { return }

        guard let url = NSWorkspace.shared.urlForApplication(
            withBundleIdentifier: AppConstants.Music.bundleIdentifier
        ) else { return }

        let config = NSWorkspace.OpenConfiguration()
        config.activates = false        // keep the user's current app in front
        config.addsToRecentItems = false
        _ = try? await NSWorkspace.shared.openApplication(at: url, configuration: config)

        // Poll up to ~3s for Music to come up.
        for _ in 0..<30 {
            if isMusicRunning { return }
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
    }

    /// Reads the last definitively-resolved grant from `UserDefaults`. Returns
    /// nil when never resolved, or when the stored value isn't a real decision.
    nonisolated static func loadPersisted() -> MusicPermissionState? {
        guard let raw = UserDefaults.standard.string(
            forKey: AppConstants.UserDefaults.lastResolvedMusicPermission
        ), let state = MusicPermissionState(rawValue: raw), state != .unknown else {
            return nil
        }
        return state
    }

    /// Persists `state` only when it's a definitive `.granted` / `.denied`
    /// decision, so a transient `.unknown` (e.g. closed Music with no prior
    /// read) never overwrites a real grant.
    nonisolated static func persistIfDefinitive(_ state: MusicPermissionState) {
        guard state == .granted || state == .denied else { return }
        UserDefaults.standard.set(
            state.rawValue,
            forKey: AppConstants.UserDefaults.lastResolvedMusicPermission
        )
    }

    /// Opens System Settings → Privacy & Security → Automation so the user
    /// can flip the WolfWave → Music toggle.
    static func openAutomationSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation") {
            NSWorkspace.shared.open(url)
        }
    }
}
