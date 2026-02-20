//
//  PowerStateMonitor.swift
//  wolfwave
//
//  Created by MrDemonWolf, Inc. on 2/20/26.
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
    static let shared = PowerStateMonitor()

    /// Whether the system is in a reduced-power state (Low Power Mode or serious/critical thermal pressure).
    private(set) var isReducedMode: Bool = false

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

    @objc private func handleChange() {
        updateState()
    }

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
