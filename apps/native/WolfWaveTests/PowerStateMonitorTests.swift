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

    func testIsReducedModeDefaultsToFalse() {
        // On CI/test runners without Low Power Mode, isReducedMode should be false
        let value = PowerStateMonitor.shared.isReducedMode
        XCTAssertFalse(value, "Expected isReducedMode to be false in test environment")
    }
}
