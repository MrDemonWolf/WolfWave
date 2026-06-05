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
/// - `NSProcessInfoPowerStateDidChange`: Low Power Mode toggle
/// - `ProcessInfo.thermalStateDidChangeNotification`: thermal throttling state
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

    /// Tokens for the block-based system observers, torn down on `deinit`.
    /// `nonisolated(unsafe)` so the (always-nonisolated) `deinit` can release
    /// them; only ever mutated from the MainActor `init`.
    nonisolated(unsafe) private var observers: [NSObjectProtocol] = []

    // MARK: - Lifecycle

    // Process-lifetime singleton. Deinit included for completeness
    deinit {
        for observer in observers {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    private init() {
        updateState()

        // The system posts `NSProcessInfoPowerStateDidChange` and
        // `thermalStateDidChangeNotification` on a background (concurrent) queue.
        // This type is MainActor-isolated (the app's default actor isolation), so a
        // selector observer would run `updateState()` off the main actor and trip
        // the Swift runtime's executor check
        // (`_checkExpectedExecutor` → `dispatch_assert_queue` → SIGTRAP). Delivering
        // on the main queue and asserting isolation keeps the handler on the main
        // actor. Mirrors the observer pattern in `AppDelegate+Services.swift`.
        let nc = NotificationCenter.default
        let names: [Notification.Name] = [
            .NSProcessInfoPowerStateDidChange,
            ProcessInfo.thermalStateDidChangeNotification,
        ]
        for name in names {
            observers.append(
                nc.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated { self?.updateState() }
                }
            )
        }
    }

    // MARK: - Private Helpers

    /// Re-evaluates Low Power Mode + thermal state, posts a notification when
    /// the reduced-power flag flips, and updates `isReducedMode`.
    private func updateState() {
        let info = ProcessInfo.processInfo
        let newValue = info.isLowPowerModeEnabled
            || info.thermalState == .serious
            || info.thermalState == .critical

        guard newValue != isReducedMode else { return }
        isReducedMode = newValue

        NotificationCenter.default.postPowerState(isReducedMode: newValue)
    }
}
