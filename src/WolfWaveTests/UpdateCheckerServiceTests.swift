//
//  UpdateCheckerServiceTests.swift
//  WolfWaveTests
//
//  Created by Claude on 2/13/26.
//

import XCTest
@testable import WolfWave

final class UpdateCheckerServiceTests: XCTestCase {
    var service: UpdateCheckerService!

    override func setUp() {
        super.setUp()
        service = UpdateCheckerService()
    }

    override func tearDown() {
        service = nil
        super.tearDown()
    }

    // MARK: - Version Comparison Tests

    func testNewerMajorVersion() {
        XCTAssertTrue(service.isNewerVersion("2.0.0", than: "1.0.0"))
    }

    func testNewerMinorVersion() {
        XCTAssertTrue(service.isNewerVersion("1.1.0", than: "1.0.0"))
    }

    func testNewerPatchVersion() {
        XCTAssertTrue(service.isNewerVersion("1.0.1", than: "1.0.0"))
    }

    func testEqualVersions() {
        XCTAssertFalse(service.isNewerVersion("1.0.0", than: "1.0.0"))
    }

    func testOlderVersion() {
        XCTAssertFalse(service.isNewerVersion("1.0.0", than: "1.1.0"))
    }

    func testMajorBumpOverHighMinor() {
        XCTAssertTrue(service.isNewerVersion("2.0.0", than: "1.9.9"))
    }

    func testMissingPatchComponentEqual() {
        XCTAssertFalse(service.isNewerVersion("1.0", than: "1.0.0"))
    }

    func testMissingPatchBothSides() {
        XCTAssertFalse(service.isNewerVersion("1.0", than: "1.0"))
    }

    func testImplicitZeroPatchEqual() {
        XCTAssertFalse(service.isNewerVersion("1.0.0", than: "1.0"))
    }

    func testSmallestPatchBump() {
        XCTAssertTrue(service.isNewerVersion("0.0.1", than: "0.0.0"))
    }

    func testEmptyCandidateNotNewer() {
        XCTAssertFalse(service.isNewerVersion("", than: "1.0.0"))
    }

    func testBothEmptyNotNewer() {
        XCTAssertFalse(service.isNewerVersion("", than: ""))
    }

    func testSingleComponentNewer() {
        XCTAssertTrue(service.isNewerVersion("2", than: "1"))
    }

    func testSingleComponentEqual() {
        XCTAssertFalse(service.isNewerVersion("1", than: "1"))
    }

    func testSingleVsMultiComponentEqual() {
        XCTAssertFalse(service.isNewerVersion("1", than: "1.0.0"))
    }

    func testMultiVsSingleComponentNewer() {
        XCTAssertTrue(service.isNewerVersion("1.0.1", than: "1"))
    }

    // MARK: - Install Method Detection Tests

    func testDetectInstallMethodDefaultsDMG() {
        let method = service.detectInstallMethod()
        XCTAssertEqual(method, .dmg)
    }
}
