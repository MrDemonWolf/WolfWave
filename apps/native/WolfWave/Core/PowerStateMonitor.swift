//
//  PowerStateMonitor.swift
//  WolfWave
//
//  Created by Nathanial Henniges on 2026-02-20.
//  Copyright © 2026 MrDemonWolf, Inc. All rights reserved.
//

import Foundation

/// Observes system power state (Low Power Mode and thermal pressure) and notifies
/// services to throttle non-essential work when the Mac is under resource pressure.
///
/// Monitors two system signals:
/// - `NSProcessInfoPowerStateDidChange` — Low Power Mode toggle
/// - `ProcessInfo.thermalStateDidChangeNotification` — thermal throttling state
///
/// When either condition indicates resource pressure, `isReducedMode` becomes `true`
/// and a `powerStateChanged` notification is posted so services can widen their
/// polling intervals.
///
/// Usage:
/// ```swift
/// _ = PowerStateMonitor.shared  // Initialize on launch
/// // Observe AppConstants.Notifications.powerStateChanged for changes
/// ```
final class PowerStateMonitor {

    // MARK: - Properties

    static let shared = PowerStateMonitor()

    /// Whether the system is in a reduced-power state (Low Power Mode or serious/critical thermal pressure).
    private(set) var isReducedMode: Bool = false

    // MARK: - Lifecycle

    // Process-lifetime singleton — deinit included for completeness
    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    private init() {
        updateState()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleChange),
            name: .NSProcessInfoPowerStateDidChange,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleChange),
            name: ProcessInfo.thermalStateDidChangeNotification,
            object: nil
        )
    }

    // MARK: - Private Helpers

    /// Selector entry point for `NotificationCenter` observers. Forwards to
    /// `updateState()` so the same logic services launch and change events.
    @objc private func handleChange() {
        updateState()
    }

    /// Re-evaluates Low Power Mode + thermal state, posts a notification when
    /// the reduced-power flag flips, and updates `isInReducedPowerMode`.
    private func updateState() {
        let info = ProcessInfo.processInfo
        let newValue = info.isLowPowerModeEnabled
            || info.thermalState == .serious
            || info.thermalState == .critical

        guard newValue != isReducedMode else { return }
        isReducedMode = newValue

        NotificationCenter.default.post(
            name: NSNotification.Name(AppConstants.Notifications.powerStateChanged),
            object: nil,
            userInfo: ["isReducedMode": newValue]
        )
    }
}
