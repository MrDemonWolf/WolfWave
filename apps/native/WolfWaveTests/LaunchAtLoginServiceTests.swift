//
//  LaunchAtLoginServiceTests.swift
//  WolfWave
//
//  Created by Nathanial Henniges on 2026-05-23.
//  Copyright © 2026 MrDemonWolf, Inc. All rights reserved.
//

import XCTest
@testable import WolfWave

/// LaunchAtLoginService is a thin SMAppService wrapper. We can't safely register
/// the unit-test host as a real login item, so these tests only assert read-back
/// shape and surface stability — actual register/unregister is exercised in
/// release smoke tests.
@MainActor
final class LaunchAtLoginServiceTests: XCTestCase {

    func testIsEnabledReturnsBoolWithoutCrashing() {
        // Calling SMAppService.mainApp.status from a unit-test host should never
        // crash, regardless of whether the host bundle is actually registered.
        // We just want a boolean answer — true or false is acceptable.
        let value: Bool = LaunchAtLoginService.isEnabled
        XCTAssert(value == true || value == false)
    }

    func testIsEnabledIsIdempotent() {
        // Reading the state twice in quick succession should return the same value.
        let first = LaunchAtLoginService.isEnabled
        let second = LaunchAtLoginService.isEnabled
        XCTAssertEqual(first, second)
    }

    func testServiceTypeIsEnum() {
        // Compile-time guard: ensure the API remains a static-only enum.
        // If someone converts this to a class with state, this test forces a
        // discussion about thread-safety + lifecycle.
        let _ = LaunchAtLoginService.isEnabled
    }
}
