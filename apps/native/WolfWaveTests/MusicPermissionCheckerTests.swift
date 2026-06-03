//
//  MusicPermissionCheckerTests.swift
//  WolfWave
//
//  Created by Nathanial Henniges on 2026-06-01.
//  Copyright © 2026 MrDemonWolf, Inc. All rights reserved.
//

import Carbon
import XCTest
@testable import WolfWave

/// Covers `MusicPermissionChecker.resolve`: the pure mapping from an
/// `AEDeterminePermissionToAutomateTarget` status to a `MusicPermissionState`,
/// including the closed-Music (`procNotFound`) fallback to the last known grant.
final class MusicPermissionCheckerTests: XCTestCase {

    private let key = AppConstants.UserDefaults.lastResolvedMusicPermission

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: key)
        super.tearDown()
    }

    // MARK: - Definitive decisions

    func testNoErrIsGranted() {
        XCTAssertEqual(MusicPermissionChecker.resolve(status: noErr, lastKnown: nil), .granted)
    }

    func testEventNotPermittedIsDenied() {
        let status = OSStatus(errAEEventNotPermitted)
        XCTAssertEqual(MusicPermissionChecker.resolve(status: status, lastKnown: .granted), .denied)
    }

    func testUnknownStatusIsUnknown() {
        // An arbitrary non-mapped error stays unknown (not silently granted).
        XCTAssertEqual(MusicPermissionChecker.resolve(status: -12345, lastKnown: nil), .unknown)
    }

    // MARK: - Closed Music (procNotFound) fallback

    func testProcNotFoundFallsBackToGranted() {
        let status = OSStatus(procNotFound)
        XCTAssertEqual(MusicPermissionChecker.resolve(status: status, lastKnown: .granted), .granted)
    }

    func testProcNotFoundFallsBackToDenied() {
        let status = OSStatus(procNotFound)
        XCTAssertEqual(MusicPermissionChecker.resolve(status: status, lastKnown: .denied), .denied)
    }

    func testProcNotFoundWithNoPriorReadIsUnknown() {
        let status = OSStatus(procNotFound)
        XCTAssertEqual(MusicPermissionChecker.resolve(status: status, lastKnown: nil), .unknown)
    }

    // MARK: - Durable persistence

    func testPersistStoresDefinitiveDecisions() {
        UserDefaults.standard.removeObject(forKey: key)
        MusicPermissionChecker.persistIfDefinitive(.granted)
        XCTAssertEqual(MusicPermissionChecker.loadPersisted(), .granted)

        MusicPermissionChecker.persistIfDefinitive(.denied)
        XCTAssertEqual(MusicPermissionChecker.loadPersisted(), .denied)
    }

    func testPersistIgnoresUnknown() {
        MusicPermissionChecker.persistIfDefinitive(.granted)
        // Unknown must not overwrite a real grant.
        MusicPermissionChecker.persistIfDefinitive(.unknown)
        XCTAssertEqual(MusicPermissionChecker.loadPersisted(), .granted)
    }

    func testLoadPersistedNilWhenNeverResolved() {
        UserDefaults.standard.removeObject(forKey: key)
        XCTAssertNil(MusicPermissionChecker.loadPersisted())
    }
}
