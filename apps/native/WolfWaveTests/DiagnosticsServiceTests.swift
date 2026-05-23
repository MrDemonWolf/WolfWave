//
//  DiagnosticsServiceTests.swift
//  WolfWaveTests
//
//  Created by MrDemonWolf, Inc. on 5/22/26.
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
        XCTAssertEqual(service.launchCount, 0)

        service.recordAppLaunch()
        service.recordAppLaunch()
        service.recordAppLaunch()

        XCTAssertEqual(service.launchCount, 3)
    }

    func testPayloadDirectoryIsScopedToWolfWave() {
        let path = service.payloadDirectory.path
        XCTAssertTrue(path.contains("WolfWave/Diagnostics"), "Unexpected payload path: \(path)")
    }

    func testDiagnosticSummaryStartsNil() {
        XCTAssertNil(service.diagnosticSummary)
    }
}
