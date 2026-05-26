//
//  AppleMusicSourceTests.swift
//  WolfWave
//
//  Created by Nathanial Henniges on 2026-02-27.
//  Copyright © 2026 MrDemonWolf, Inc. All rights reserved.
//

import XCTest
@testable import WolfWave

@MainActor
final class AppleMusicSourceTests: XCTestCase {
    var monitor: AppleMusicSource!

    override func setUp() {
        super.setUp()
        monitor = AppleMusicSource()
    }

    override func tearDown() {
        monitor.stopTracking()
        monitor = nil
        super.tearDown()
    }

    // MARK: - Initialization Tests

    func testMonitorInitialization() {
        XCTAssertNotNil(monitor)
    }

    func testDelegateIsNilByDefault() {
        XCTAssertNil(monitor.delegate)
    }

    // MARK: - Start/Stop Tests

    func testStartTrackingDoesNotCrash() {
        monitor.startTracking()
        // If Music.app is not running, we should get a status update
    }

    func testStopTrackingDoesNotCrash() {
        monitor.startTracking()
        monitor.stopTracking()
    }

    func testDoubleStartDoesNotCrash() {
        monitor.startTracking()
        monitor.startTracking()
        monitor.stopTracking()
    }

    func testDoubleStopDoesNotCrash() {
        monitor.startTracking()
        monitor.stopTracking()
        monitor.stopTracking()
    }

    // MARK: - Update Interval Tests

    func testUpdateCheckIntervalBeforeStartDoesNotCrash() {
        monitor.updateCheckInterval(10.0)
    }

    func testUpdateCheckIntervalWhileTrackingDoesNotCrash() {
        monitor.startTracking()
        monitor.updateCheckInterval(10.0)
        monitor.stopTracking()
    }

    // MARK: - Force Refresh Tests

    func testForceRefreshBeforeStartIsNoOp() {
        // Should not crash; no delegate set, no tracking active.
        monitor.forceRefresh()
    }

    func testForceRefreshWhileTrackingDoesNotCrash() {
        monitor.startTracking()
        monitor.forceRefresh()
        monitor.stopTracking()
    }

    func testForceRefreshAfterStopIsNoOp() {
        monitor.startTracking()
        monitor.stopTracking()
        monitor.forceRefresh()
    }

    // MARK: - extractPlayerState (tolerant FourCharCode parser)

    private static let kPSP: UInt32 = 1800426320  // 'kPSP' — playing
    private static let kPSp: UInt32 = 1800426352  // 'kPSp' — paused

    func testExtractPlayerStateFromNSNumber() {
        let raw: NSNumber = NSNumber(value: Self.kPSP)
        XCTAssertEqual(AppleMusicSource.extractPlayerState(raw), Self.kPSP)
    }

    func testExtractPlayerStateFromInt() {
        let raw: Int = Int(Self.kPSp)
        XCTAssertEqual(AppleMusicSource.extractPlayerState(raw), Self.kPSp)
    }

    func testExtractPlayerStateFromUInt32() {
        let raw: UInt32 = Self.kPSP
        XCTAssertEqual(AppleMusicSource.extractPlayerState(raw), Self.kPSP)
    }

    func testExtractPlayerStateFromFourCharString() {
        XCTAssertEqual(AppleMusicSource.extractPlayerState("kPSP"), Self.kPSP)
        XCTAssertEqual(AppleMusicSource.extractPlayerState("kPSp"), Self.kPSp)
    }

    func testExtractPlayerStateFromAppleEventDescriptor() {
        let desc = NSAppleEventDescriptor(typeCode: Self.kPSP)
        XCTAssertEqual(AppleMusicSource.extractPlayerState(desc), Self.kPSP)
    }

    func testExtractPlayerStateRejectsWrongLengthString() {
        XCTAssertNil(AppleMusicSource.extractPlayerState("kPS"))
        XCTAssertNil(AppleMusicSource.extractPlayerState("kPSPextra"))
    }

    func testExtractPlayerStateRejectsUnknownType() {
        struct Bogus {}
        XCTAssertNil(AppleMusicSource.extractPlayerState(Bogus()))
        XCTAssertNil(AppleMusicSource.extractPlayerState([1, 2, 3]))
    }
}
