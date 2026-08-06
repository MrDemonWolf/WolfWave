//
//  PowerStateMonitorTests.swift
//  WolfWave
//
//  Created by Nathanial Henniges on 2026-02-27.
//  Copyright © 2026 MrDemonWolf, Inc. All rights reserved.
//

import XCTest
@testable import WolfWave

@MainActor
final class PowerStateMonitorTests: XCTestCase {

    // MARK: - Initial State Tests

    func testSharedInstanceExists() {
        let monitor = PowerStateMonitor.shared
        XCTAssertNotNil(monitor)
    }

    func testSharedInstanceIsSingleton() {
        let a = PowerStateMonitor.shared
        let b = PowerStateMonitor.shared
        XCTAssertTrue(a === b)
    }

    // MARK: - State Property Tests

    func testIsReducedModePropertyAccessible() {
        // isReducedMode should be readable without crashing
        let _ = PowerStateMonitor.shared.isReducedMode
    }

    func testIsReducedModeMatchesCurrentPowerState() {
        let info = ProcessInfo.processInfo
        let expected = info.isLowPowerModeEnabled
            || info.thermalState == .serious
            || info.thermalState == .critical
        XCTAssertEqual(PowerStateMonitor.shared.isReducedMode, expected)
    }

    func testPowerStateNotificationPayloadRoundTrips() {
        let notification = Notification(
            name: .powerStateChanged,
            userInfo: [NotificationKeys.isReducedMode: true]
        )
        XCTAssertEqual(notification.isReducedModeFlag, true)
    }
}
