//
//  MusicPlaybackMonitorTests.swift
//  WolfWaveTests
//
//  Created by MrDemonWolf, Inc. on 2/27/26.
//

import XCTest
@testable import WolfWave

final class MusicPlaybackMonitorTests: XCTestCase {
    var monitor: MusicPlaybackMonitor!

    override func setUp() {
        super.setUp()
        monitor = MusicPlaybackMonitor()
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
}
