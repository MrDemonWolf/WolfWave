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
