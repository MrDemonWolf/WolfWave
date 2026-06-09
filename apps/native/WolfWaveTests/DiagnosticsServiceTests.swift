//
//  DiagnosticsServiceTests.swift
//  WolfWave
//
//  Created by Nathanial Henniges on 2026-05-22.
//  Copyright © 2026 MrDemonWolf, Inc. All rights reserved.
//

import XCTest

@testable import WolfWave

// MARK: - DiagnosticsServiceTests

/// Covers `DiagnosticsService` opt-in state and the anonymous launch counter.
/// Each test uses an isolated `UserDefaults` suite; the MetricKit subscription
/// itself is not exercised (it has process-wide side effects).
@MainActor
final class DiagnosticsServiceTests: XCTestCase {

    private var suiteName: String!
    private var defaults: UserDefaults!
    private var service: DiagnosticsService!

    override func setUp() {
        super.setUp()
        suiteName = "DiagnosticsServiceTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        service = DiagnosticsService(defaults: defaults)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        service = nil
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    func testDiagnosticsAreDisabledByDefault() {
        XCTAssertFalse(service.isEnabled, "Diagnostics opt-in must default to off")
    }

    func testIsEnabledReflectsStoredPreference() {
        defaults.set(true, forKey: AppConstants.UserDefaults.shareDiagnosticsEnabled)
        XCTAssertTrue(service.isEnabled)
    }

    func testRecordAppLaunchIncrementsCounter() {
        // Launch counting is gated on the diagnostics opt-in (see #338).
        defaults.set(true, forKey: AppConstants.UserDefaults.shareDiagnosticsEnabled)
        XCTAssertEqual(service.launchCount, 0)

        service.recordAppLaunch()
        service.recordAppLaunch()
        service.recordAppLaunch()

        XCTAssertEqual(service.launchCount, 3)
    }

    func testRecordAppLaunchIsNoOpWhenDisabled() {
        XCTAssertFalse(service.isEnabled)

        service.recordAppLaunch()
        service.recordAppLaunch()

        XCTAssertEqual(service.launchCount, 0, "Launches must not be counted while diagnostics are off")
    }

    func testPayloadDirectoryIsScopedToWolfWave() {
        let path = service.payloadDirectory.path
        XCTAssertTrue(path.contains("WolfWave/Diagnostics"), "Unexpected payload path: \(path)")
    }

    func testDiagnosticSummaryStartsNil() {
        XCTAssertNil(service.diagnosticSummary)
    }
}
