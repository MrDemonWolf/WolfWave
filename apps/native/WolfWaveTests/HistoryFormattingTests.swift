//
//  HistoryFormattingTests.swift
//  WolfWave
//
//  Created by Nathanial Henniges on 2026-05-23.
//  Copyright © 2026 MrDemonWolf, Inc. All rights reserved.
//

import XCTest
@testable import WolfWave

@MainActor
final class HistoryFormattingTests: XCTestCase {

    // MARK: - listeningTime

    func testListeningTimeZeroSeconds() {
        XCTAssertEqual(HistoryFormat.listeningTime(0), "0s")
    }

    func testListeningTimeUnderOneMinute() {
        XCTAssertEqual(HistoryFormat.listeningTime(45), "45s")
        XCTAssertEqual(HistoryFormat.listeningTime(59), "59s")
    }

    func testListeningTimeExactlyOneMinute() {
        XCTAssertEqual(HistoryFormat.listeningTime(60), "1m")
    }

    func testListeningTimeUnderOneHour() {
        XCTAssertEqual(HistoryFormat.listeningTime(120), "2m")
        XCTAssertEqual(HistoryFormat.listeningTime(3599), "59m")
    }

    func testListeningTimeExactlyOneHour() {
        XCTAssertEqual(HistoryFormat.listeningTime(3600), "1h")
    }

    func testListeningTimeWithHoursAndMinutes() {
        XCTAssertEqual(HistoryFormat.listeningTime(3660), "1h 1m")
        XCTAssertEqual(HistoryFormat.listeningTime(22320), "6h 12m")
    }

    func testListeningTimeWholeHours() {
        XCTAssertEqual(HistoryFormat.listeningTime(7200), "2h")
        XCTAssertEqual(HistoryFormat.listeningTime(86400), "24h")
    }

    func testListeningTimeNegativeReturnsZero() {
        XCTAssertEqual(HistoryFormat.listeningTime(-100), "0s")
    }

    func testListeningTimeFractionalRoundsToNearest() {
        XCTAssertEqual(HistoryFormat.listeningTime(59.4), "59s")
        XCTAssertEqual(HistoryFormat.listeningTime(59.6), "1m")
    }

    func testListeningTimeNonFiniteDoesNotTrap() {
        // Corrupt NDJSON can produce inf/nan durations; must not crash.
        XCTAssertEqual(HistoryFormat.listeningTime(.infinity), "0s")
        XCTAssertEqual(HistoryFormat.listeningTime(-.infinity), "0s")
        XCTAssertEqual(HistoryFormat.listeningTime(.nan), "0s")
    }

    func testListeningTimeOverflowDoesNotTrap() {
        // 1e300 exceeds Int.max; converting unclamped would trap.
        XCTAssertFalse(HistoryFormat.listeningTime(1e300).isEmpty)
    }

    // MARK: - playCount

    func testPlayCountSingular() {
        XCTAssertEqual(HistoryFormat.playCount(1), "1 play")
    }

    func testPlayCountZero() {
        XCTAssertEqual(HistoryFormat.playCount(0), "0 plays")
    }

    func testPlayCountPlural() {
        XCTAssertEqual(HistoryFormat.playCount(2), "2 plays")
        XCTAssertEqual(HistoryFormat.playCount(42), "42 plays")
        XCTAssertEqual(HistoryFormat.playCount(1000), "1000 plays")
    }

    // MARK: - clock

    func testClockZero() {
        XCTAssertEqual(HistoryFormat.clock(0), "0:00")
    }

    func testClockUnderOneMinutePadsSeconds() {
        XCTAssertEqual(HistoryFormat.clock(7), "0:07")
        XCTAssertEqual(HistoryFormat.clock(59), "0:59")
    }

    func testClockMinutesAndSeconds() {
        XCTAssertEqual(HistoryFormat.clock(67), "1:07")
        XCTAssertEqual(HistoryFormat.clock(187), "3:07")
    }

    func testClockMinutesExceedSixty() {
        XCTAssertEqual(HistoryFormat.clock(3725), "62:05")
    }

    func testClockNegativeClampsToZero() {
        XCTAssertEqual(HistoryFormat.clock(-5), "0:00")
    }

    func testClockFractionalRoundsToNearest() {
        XCTAssertEqual(HistoryFormat.clock(7.4), "0:07")
        XCTAssertEqual(HistoryFormat.clock(7.6), "0:08")
    }

    func testClockNonFiniteDoesNotTrap() {
        XCTAssertEqual(HistoryFormat.clock(.infinity), "0:00")
        XCTAssertEqual(HistoryFormat.clock(.nan), "0:00")
    }

    // MARK: - relative

    func testRelativeJustNow() {
        let now = Date()
        let result = HistoryFormat.relative(now, now: now)
        // The exact string is locale/format dependent ("in 0 seconds", "now").
        // Just assert it's non-empty.
        XCTAssertFalse(result.isEmpty)
    }

    func testRelativePastIsNotEmpty() {
        let now = Date(timeIntervalSinceReferenceDate: 1_000_000)
        let past = now.addingTimeInterval(-600)  // 10 minutes ago
        let result = HistoryFormat.relative(past, now: now)
        XCTAssertFalse(result.isEmpty)
    }

    func testRelativeAcceptsCustomNow() {
        // Same date should produce a consistent string regardless of system time.
        let reference = Date(timeIntervalSinceReferenceDate: 0)
        let past = reference.addingTimeInterval(-3600)
        let result = HistoryFormat.relative(past, now: reference)
        XCTAssertFalse(result.isEmpty)
    }
}
