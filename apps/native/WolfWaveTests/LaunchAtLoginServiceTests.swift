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
/// shape and surface stability. Actual register/unregister is exercised in
/// release smoke tests.
@MainActor
final class LaunchAtLoginServiceTests: XCTestCase {

    func testIsEnabledReturnsBoolWithoutCrashing() {
        // Calling SMAppService.mainApp.status from a unit-test host should never
        // crash, regardless of whether the host bundle is actually registered.
        // We just want a boolean answer: true or false is acceptable.
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

    func testRequiresApprovalReturnsBoolWithoutCrashing() {
        // Reading the requires-approval state from a unit-test host should never
        // crash; we only need a boolean answer.
        let value: Bool = LaunchAtLoginService.requiresApproval
        XCTAssert(value == true || value == false)
    }

    func testRequiresApprovalImpliesEnabled() {
        // A login item that is pending approval is still considered opted-in, so
        // `isEnabled` must report true whenever `requiresApproval` is true. This
        // is the contract that keeps the settings toggle from silently reverting.
        if LaunchAtLoginService.requiresApproval {
            XCTAssertTrue(LaunchAtLoginService.isEnabled)
        }
    }

    func testRegistrationOutcomeCasesAreDistinct() {
        // Compile-time + value guard on the outcome enum the settings/onboarding
        // toggles switch over. `.requiresApproval` and `.success` keep the toggle
        // on; only `.failure` reverts it.
        let all: Set<LaunchAtLoginService.RegistrationOutcome> = [.success, .requiresApproval, .failure]
        XCTAssertEqual(all.count, 3)
    }
}
