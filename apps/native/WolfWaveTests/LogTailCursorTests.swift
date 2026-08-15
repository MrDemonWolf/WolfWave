//
//  LogTailCursorTests.swift
//  WolfWave
//
//  Created by Nathanial Henniges on 2026-08-14.
//  Copyright © 2026 MrDemonWolf, Inc. All rights reserved.
//

import Testing
import Foundation
@testable import WolfWave

/// Tests for the log-tailing cursor.
///
/// These pin the three failure modes the cursor exists to prevent: re-reading
/// the whole file every tick, losing a line that straddles two reads, and
/// reading past the end forever after the log is cleared or rotated.
@Suite("LogTailCursor Tests")
struct LogTailCursorTests {

    private static let priming: UInt64 = 1_000

    // MARK: - Priming

    @Test("First read primes from a bounded window, not the whole file")
    func testPrimingIsBounded() {
        var cursor = LogTailCursor()

        let range = cursor.planRead(fileSize: 5_000_000, primingBytes: Self.priming)

        #expect(range == 4_999_000..<5_000_000,
            "A 5 MB log must not be read in full just to show the last screenful")
        #expect(cursor.offset == 5_000_000)
    }

    @Test("A file smaller than the priming window is read from the start")
    func testPrimingSmallFile() {
        var cursor = LogTailCursor()

        #expect(cursor.planRead(fileSize: 120, primingBytes: Self.priming) == 0..<120)
    }

    @Test("An empty file yields nothing to read")
    func testEmptyFile() {
        var cursor = LogTailCursor()

        #expect(cursor.planRead(fileSize: 0, primingBytes: Self.priming) == nil)
        #expect(cursor.primed, "Still counts as primed, so the next append is a delta read")
    }

    // MARK: - Incremental Reads

    @Test("Subsequent reads pull only what was appended")
    func testDeltaRead() {
        var cursor = LogTailCursor()
        _ = cursor.planRead(fileSize: 500, primingBytes: Self.priming)

        #expect(cursor.planRead(fileSize: 640, primingBytes: Self.priming) == 500..<640)
        #expect(cursor.offset == 640)
    }

    @Test("An unchanged file yields nothing")
    func testNoChange() {
        var cursor = LogTailCursor()
        _ = cursor.planRead(fileSize: 500, primingBytes: Self.priming)

        #expect(cursor.planRead(fileSize: 500, primingBytes: Self.priming) == nil)
        #expect(cursor.planRead(fileSize: 500, primingBytes: Self.priming) == nil)
    }

    // MARK: - Truncation and Rotation

    @Test("A shrunken file re-primes instead of seeking past the end")
    func testTruncationReprimes() {
        var cursor = LogTailCursor()
        _ = cursor.planRead(fileSize: 900_000, primingBytes: Self.priming)

        // Clear Log, or a rotation, leaves a much smaller file. Reading from the
        // old offset would seek past EOF and return nothing forever.
        let range = cursor.planRead(fileSize: 200, primingBytes: Self.priming)

        #expect(range == 0..<200)
        #expect(cursor.offset == 200)
    }

    @Test("Truncation drops a half-line held from the previous file")
    func testTruncationClearsCarry() {
        var cursor = LogTailCursor()
        _ = cursor.planRead(fileSize: 500, primingBytes: Self.priming)
        _ = cursor.consume("complete line\npartial tail")
        #expect(!cursor.carry.isEmpty)

        _ = cursor.planRead(fileSize: 10, primingBytes: Self.priming)

        #expect(cursor.carry.isEmpty,
            "A partial line from the old file must not be glued onto the new one")
    }

    // MARK: - Line Assembly

    @Test("Complete lines are returned and the partial tail is held back")
    func testPartialLineHeldBack() {
        var cursor = LogTailCursor()

        let first = cursor.consume("alpha\nbravo\nchar")

        #expect(first == ["alpha", "bravo"])
        #expect(cursor.carry == "char")
    }

    @Test("A line split across two reads is reassembled, not dropped")
    func testSplitLineReassembled() {
        var cursor = LogTailCursor()

        // A record cut in half by a read boundary would not match the record
        // header on either side, so both halves would be discarded.
        _ = cursor.consume("2026-08-14T10:00:00.000Z  INFO   App  ")
        let second = cursor.consume("F.swift:1  hello\n")

        #expect(second == ["2026-08-14T10:00:00.000Z  INFO   App  F.swift:1  hello"])
        #expect(LogRecord.parse(second[0])?.message == "hello")
    }

    @Test("A chunk ending exactly on a newline holds nothing back")
    func testCleanBoundary() {
        var cursor = LogTailCursor()

        #expect(cursor.consume("one\ntwo\n") == ["one", "two"])
        #expect(cursor.carry.isEmpty)
    }

    @Test("A chunk with no newline yields no lines yet")
    func testNoNewlineYet() {
        var cursor = LogTailCursor()

        #expect(cursor.consume("still writing").isEmpty)
        #expect(cursor.carry == "still writing")
    }

    // MARK: - Reset

    @Test("Reset returns the cursor to its unprimed state")
    func testReset() {
        var cursor = LogTailCursor()
        _ = cursor.planRead(fileSize: 5_000, primingBytes: Self.priming)
        _ = cursor.consume("partial")

        cursor.reset()

        #expect(cursor == LogTailCursor())
    }

    // MARK: - End to End

    @Test("A realistic append sequence yields each record exactly once")
    func testAppendSequenceYieldsEachRecordOnce() {
        var cursor = LogTailCursor()
        var seen: [String] = []

        // Prime against an empty file, then append two records in three writes,
        // the middle one splitting a line.
        _ = cursor.planRead(fileSize: 0, primingBytes: Self.priming)
        seen += cursor.consume("2026-08-14T10:00:00.000Z  INFO   App  F.swift:1  first\n")
        seen += cursor.consume("2026-08-14T10:00:01.000Z  WARN   App  F.swift:2  sec")
        seen += cursor.consume("ond\n")

        let records = LogRecord.parse(contents: seen.joined(separator: "\n"))
        #expect(records.map(\.message) == ["first", "second"])
    }
}
