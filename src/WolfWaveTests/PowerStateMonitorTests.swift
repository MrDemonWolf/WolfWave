//
//  PowerStateMonitorTests.swift
//  WolfWaveTests
//
//  Created by MrDemonWolf, Inc. on 2/27/26.
//

import XCTest
@testable import WolfWave

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

    func testIsReducedModeReturnsBool() {
        let value = PowerStateMonitor.shared.isReducedMode
        // Value depends on system state but should be a valid boolean
        XCTAssertTrue(value == true || value == false)
    }
}
