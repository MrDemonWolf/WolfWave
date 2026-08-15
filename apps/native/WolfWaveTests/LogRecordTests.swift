//
//  LogRecordTests.swift
//  WolfWave
//
//  Created by Nathanial Henniges on 2026-08-14.
//  Copyright © 2026 MrDemonWolf, Inc. All rights reserved.
//

import Testing
import Foundation
@testable import WolfWave

/// Tests for the log-line parser.
///
/// `LogRecord` is the contract between what ``Log`` writes and everything that
/// reads it (the Debug tab viewer, the diagnostics export, external tooling).
/// These tests are pure: they touch no file and no process-global state, so
/// they are safe to run alongside any other suite.
///
/// Round-trip cases deliberately go through `Log.formatFileLineForTesting`
/// rather than hand-written strings, so the writer and the reader cannot drift
/// apart without a failure here.
@Suite("LogRecord Tests")
struct LogRecordTests {

    // MARK: - Round Trips

    @Test("Every level round-trips writer → parser", arguments: LogLevel.allCases)
    func testLevelRoundTrip(_ level: LogLevel) {
        let line = Log.formatFileLineForTesting("hello", level: level, category: "App")

        guard let record = LogRecord.parse(line) else {
            Issue.record("Failed to parse: \(line)")
            return
        }
        #expect(record.level == level)
        #expect(record.message == "hello")
    }

    @Test("Every category round-trips writer → parser", arguments: LogCategory.allCases)
    func testCategoryRoundTrip(_ category: LogCategory) {
        let line = Log.formatFileLineForTesting("hello", category: category.rawValue)

        #expect(LogRecord.parse(line)?.category == category.rawValue)
    }

    @Test("Timestamp round-trips to within a millisecond")
    func testTimestampRoundTrip() {
        let before = Date()
        let line = Log.formatFileLineForTesting("stamped")

        guard let record = LogRecord.parse(line) else {
            Issue.record("Failed to parse: \(line)")
            return
        }

        // The format carries milliseconds, so allow one millisecond of
        // truncation either way plus a generous window for slow CI.
        let delta = record.timestamp.timeIntervalSince(before)
        #expect(delta >= -0.002, "Parsed timestamp precedes the write: \(delta)")
        #expect(delta < 5, "Parsed timestamp is implausibly late: \(delta)")
    }

    @Test("Source location survives parsing")
    func testLocationParsed() {
        let line = Log.formatFileLineForTesting("hello")

        #expect(LogRecord.parse(line)?.location == "Test.swift:0")
    }

    // MARK: - Structured Fields

    @Test("Parses a simple key=value tail")
    func testSimpleFields() {
        let line = Log.formatFileLineForTesting(
            "Reconnect failed",
            level: .error,
            category: "Twitch",
            fields: ["attempt": 3, "code": 4003]
        )

        guard let record = LogRecord.parse(line) else {
            Issue.record("Failed to parse: \(line)")
            return
        }
        #expect(record.message == "Reconnect failed")
        #expect(record.fields == [
            LogRecord.Field(key: "attempt", value: "3"),
            LogRecord.Field(key: "code", value: "4003")
        ])
    }

    @Test("Parses quoted values containing spaces")
    func testQuotedValueWithSpaces() {
        let line = Log.formatFileLineForTesting(
            "Closed",
            fields: ["reason": "transport closed by peer"]
        )

        guard let record = LogRecord.parse(line) else {
            Issue.record("Failed to parse: \(line)")
            return
        }
        #expect(record.message == "Closed")
        #expect(record.fields == [
            LogRecord.Field(key: "reason", value: "transport closed by peer")
        ])
    }

    @Test("Parses quoted values containing an equals sign")
    func testQuotedValueWithEquals() {
        let line = Log.formatFileLineForTesting("Query", fields: ["url": "?a=1&b=2"])

        #expect(LogRecord.parse(line)?.fields == [
            LogRecord.Field(key: "url", value: "?a=1&b=2")
        ])
    }

    @Test("Parses quoted values containing an escaped quote")
    func testQuotedValueWithQuote() {
        let line = Log.formatFileLineForTesting("Parsed", fields: ["raw": #"say "hi""#])

        #expect(LogRecord.parse(line)?.fields == [
            LogRecord.Field(key: "raw", value: #"say "hi""#)
        ])
    }

    @Test("A message with no fields parses with an empty field list")
    func testNoFields() {
        let line = Log.formatFileLineForTesting("Just a message here")

        guard let record = LogRecord.parse(line) else {
            Issue.record("Failed to parse: \(line)")
            return
        }
        #expect(record.message == "Just a message here")
        #expect(record.fields.isEmpty)
    }

    @Test("Field order is preserved")
    func testFieldOrderPreserved() {
        let line = Log.formatFileLineForTesting(
            "Ordered",
            fields: ["zebra": 1, "alpha": 2, "middle": 3]
        )

        #expect(LogRecord.parse(line)?.fields.map(\.key) == ["zebra", "alpha", "middle"])
    }

    @Test("Message keeps its own internal double spaces")
    func testMessageInternalSpacing() {
        let line = Log.formatFileLineForTesting("spaced  out  message", fields: ["n": 1])

        #expect(LogRecord.parse(line)?.message == "spaced  out  message")
    }

    // MARK: - Malformed Input

    @Test("Malformed lines return nil rather than a partial record", arguments: [
        "",
        "   ",
        "not a log line at all",
        "2026-08-14 14:03:22  INFO  App  F.swift:1  wrong stamp shape",
        "14:03:22.481  INFO  App  F.swift:1  old time-only format",
        "2026-08-14T14:03:22.481-05:00  NOPE  App  F.swift:1  bad level",
        "2026-08-14T14:03:22.481-05:00  INFO  App",
        "🐛 DEBUG  [App] 14:03:22.481  F.swift:1  the old emoji format"
    ])
    func testMalformedLinesReturnNil(_ line: String) {
        #expect(LogRecord.parse(line) == nil, "Should not parse: \(line)")
    }

    @Test("A UTC offset of Z parses")
    func testZuluOffset() {
        let line = "2026-08-14T14:03:22.481Z  INFO   App           F.swift:1   hello"

        #expect(LogRecord.parse(line)?.message == "hello")
    }

    // MARK: - Continuation Folding

    @Test("Continuation lines fold into the preceding record")
    func testContinuationFolding() {
        let contents = """
        2026-08-14T14:03:22.481Z  ERROR  App           F.swift:1   Exception thrown
          frame one
          frame two
        2026-08-14T14:03:23.000Z  INFO   App           F.swift:2   Next record
        """

        let records = LogRecord.parse(contents: contents)

        #expect(records.count == 2)
        #expect(records.first?.message == "Exception thrown\nframe one\nframe two")
        #expect(records.last?.message == "Next record")
    }

    @Test("A trailing continuation still folds")
    func testTrailingContinuation() {
        let contents = """
        2026-08-14T14:03:22.481Z  ERROR  App           F.swift:1   Boom
          detail line
        """

        #expect(LogRecord.parse(contents: contents).first?.message == "Boom\ndetail line")
    }

    @Test("Leading noise before the first record is dropped, not guessed at")
    func testLeadingNoiseDropped() {
        // What a truncated tail read looks like: the head of the buffer lands
        // mid-record. Emitting a partial record there would invent data.
        let contents = """
          orphaned continuation from a record we never saw
        2026-08-14T14:03:23.000Z  INFO   App           F.swift:2   First real record
        """

        let records = LogRecord.parse(contents: contents)

        #expect(records.count == 1)
        #expect(records.first?.message == "First real record")
    }

    @Test("Blank lines are ignored")
    func testBlankLinesIgnored() {
        let contents = """
        2026-08-14T14:03:22.481Z  INFO   App           F.swift:1   One

        2026-08-14T14:03:23.000Z  INFO   App           F.swift:2   Two
        """

        #expect(LogRecord.parse(contents: contents).map(\.message) == ["One", "Two"])
    }

    @Test("Parsed records carry sequential identity for list rendering")
    func testSequentialIdentity() {
        let contents = """
        2026-08-14T14:03:22.481Z  INFO   App           F.swift:1   One
        2026-08-14T14:03:23.000Z  INFO   App           F.swift:2   Two
        2026-08-14T14:03:24.000Z  INFO   App           F.swift:3   Three
        """

        #expect(LogRecord.parse(contents: contents).map(\.id) == [0, 1, 2])
    }

    @Test("Empty contents yields no records")
    func testEmptyContents() {
        #expect(LogRecord.parse(contents: "").isEmpty)
    }

    // MARK: - Realistic Sample

    @Test("Parses a realistic multi-record log excerpt")
    func testRealisticExcerpt() {
        let contents = """
        2026-08-14T14:03:22.481-05:00  INFO   App           Logger.swift:0    \
        WolfWave session start session=a3f9c1 version=2.1.0 build=1841 os=26.0.0 arch=arm64
        2026-08-14T14:03:24.102-05:00  ERROR  Twitch        TwitchChatService.swift:812  \
        EventSub reconnect failed attempt=3 code=4003
        2026-08-14T14:03:24.109-05:00  WARN   Music         AppleMusicSource.swift:661   \
        Unknown player state, trusting track raw="kPSX"
        """

        let records = LogRecord.parse(contents: contents)

        #expect(records.count == 3)

        #expect(records[0].category == "App")
        #expect(records[0].fields.first(where: { $0.key == "session" })?.value == "a3f9c1")
        #expect(records[0].fields.first(where: { $0.key == "arch" })?.value == "arm64")

        #expect(records[1].level == .error)
        #expect(records[1].category == "Twitch")
        #expect(records[1].location == "TwitchChatService.swift:812")
        #expect(records[1].message == "EventSub reconnect failed")
        #expect(records[1].fields.first(where: { $0.key == "code" })?.value == "4003")

        #expect(records[2].level == .warn)
        #expect(records[2].message == "Unknown player state, trusting track")
        #expect(records[2].fields == [LogRecord.Field(key: "raw", value: "kPSX")])
    }
}
