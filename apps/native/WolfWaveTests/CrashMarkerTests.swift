//
//  CrashMarkerTests.swift
//  WolfWave
//
//  Created by Nathanial Henniges on 2026-08-14.
//  Copyright © 2026 MrDemonWolf, Inc. All rights reserved.
//

import Testing
import Foundation
@testable import WolfWave

/// Tests for reading the crash breadcrumb.
///
/// Pure parsing only. No test here raises a real signal or `NSException`: both
/// would kill the xctest host, which is why `CrashReporterTests` exercises the
/// marker lifecycle through the Foundation seam instead.
@Suite("CrashMarker Tests")
struct CrashMarkerTests {

    // MARK: - Current Schema

    private static let signalMarker = """
        WOLFWAVE-CRASH 1
        kind=signal
        pid=54837
        version=2.1.1
        build=1841
        signal=SIGSEGV
        epoch=1755180000
        """

    @Test("Parses a signal marker written by the handler")
    func testParsesSignalMarker() {
        guard let marker = CrashMarker.parse(Self.signalMarker) else {
            Issue.record("signal marker failed to parse")
            return
        }

        #expect(marker.kind == .signal)
        #expect(marker.signalName == "SIGSEGV")
        #expect(marker.pid == 54837)
        #expect(marker.version == "2.1.1")
        #expect(marker.build == "1841")
        #expect(marker.date == Date(timeIntervalSince1970: 1_755_180_000))
        #expect(marker.frames.isEmpty, "a signal handler cannot walk the stack safely")
    }

    @Test("Parses an exception marker with frames")
    func testParsesExceptionMarker() {
        let text = """
            WOLFWAVE-CRASH 1
            kind=exception
            pid=1234
            version=2.1.1
            build=1841
            epoch=1755180000
            name=NSInvalidArgumentException
            reason=unrecognized selector sent to instance
            frame=0   WolfWave  0x000  main + 1
            frame=1   AppKit    0x111  -[NSApplication run] + 2
            """

        guard let marker = CrashMarker.parse(text) else {
            Issue.record("exception marker failed to parse")
            return
        }

        #expect(marker.kind == .exception)
        #expect(marker.exceptionName == "NSInvalidArgumentException")
        #expect(marker.reason == "unrecognized selector sent to instance")
        #expect(marker.frames.count == 2)
        #expect(marker.frames.first?.contains("main + 1") == true)
    }

    @Test("A reason containing an equals sign keeps its full value")
    func testReasonWithEquals() {
        let text = """
            WOLFWAVE-CRASH 1
            kind=exception
            name=Whatever
            reason=count=0 was not expected
            """

        #expect(CrashMarker.parse(text)?.reason == "count=0 was not expected")
    }

    @Test("Unknown kind degrades rather than failing")
    func testUnknownKind() {
        let text = """
            WOLFWAVE-CRASH 1
            kind=meteor
            """

        #expect(CrashMarker.parse(text)?.kind == .unknown)
    }

    // MARK: - Writer / Reader Agreement
    //
    // The signal path cannot be run for real: raising a fatal signal kills the
    // xctest host. These assert that what the handler's three writes concatenate
    // to is exactly what the parser accepts, so the two cannot drift apart
    // without a failure here rather than at someone's actual crash.

    @Test("Every signal the handler traps composes into a parseable marker")
    func testSignalHandlerOutputParses() {
        for slot in 0..<crashReporterSignalLabels.count {
            let text = CrashReporter.composeSignalMarkerForTesting(slot: slot, epoch: 1_755_180_000)

            guard let marker = CrashMarker.parse(text) else {
                Issue.record("slot \(slot) produced an unparseable marker:\n\(text)")
                continue
            }
            #expect(marker.kind == .signal)
            #expect(marker.signalName?.hasPrefix("SIG") == true,
                "slot \(slot) lost its signal name: \(marker.signalName ?? "nil")")
            #expect(marker.date == Date(timeIntervalSince1970: 1_755_180_000))
            #expect(marker.pid != nil, "pid must survive the three-write composition")
            #expect(marker.version != nil)
            #expect(marker.build != nil)
        }
    }

    @Test("The composed marker has no blank or malformed lines")
    func testComposedMarkerIsWellFormed() {
        // The prefix deliberately ends mid-line (`signal=`) and the label
        // completes it. An extra newline in either would split one field into
        // two malformed ones.
        let text = CrashReporter.composeSignalMarkerForTesting(slot: 2, epoch: 1_755_180_000)
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false)

        #expect(lines.first.map(String.init) == CrashMarker.header)
        for line in lines.dropFirst() where !line.isEmpty {
            #expect(line.contains("="), "malformed marker line: '\(line)'")
        }
        #expect(text.contains("signal=SIGSEGV\n"), "prefix and label must join into one field")
    }

    // MARK: - Legacy Markers
    //
    // A user upgrading across this change can have an old-format marker on disk
    // from the very crash that prompted the upgrade. Reading it is still better
    // than showing them nothing.

    @Test("Parses a legacy bare-signal marker")
    func testLegacySignal() {
        guard let marker = CrashMarker.parse("SIGSEGV\n") else {
            Issue.record("legacy signal marker failed to parse")
            return
        }

        #expect(marker.kind == .signal)
        #expect(marker.signalName == "SIGSEGV")
        #expect(marker.date == nil, "the legacy format carried no timestamp, which is why it changed")
        #expect(marker.version == nil)
    }

    @Test("Parses a legacy exception marker")
    func testLegacyException() {
        let text = """
            EXCEPTION NSRangeException
            index 5 beyond bounds
            0   WolfWave  0x000  main + 1
            1   AppKit    0x111  run + 2
            """

        guard let marker = CrashMarker.parse(text) else {
            Issue.record("legacy exception marker failed to parse")
            return
        }

        #expect(marker.kind == .exception)
        #expect(marker.exceptionName == "NSRangeException")
        #expect(marker.reason == "index 5 beyond bounds")
        #expect(marker.frames.count == 2)
    }

    // MARK: - Empty Input

    @Test("Empty or whitespace-only markers yield nil", arguments: ["", "\n", "   \n  "])
    func testEmptyYieldsNil(_ text: String) {
        #expect(CrashMarker.parse(text) == nil)
    }

    // MARK: - Presentation

    @Test("Summary names the fault, the time, and the build")
    func testSummary() {
        guard let marker = CrashMarker.parse(Self.signalMarker) else {
            Issue.record("marker failed to parse")
            return
        }

        let summary = marker.summary
        #expect(summary.contains("SIGSEGV"))
        #expect(summary.contains("2.1.1"))
        #expect(summary.contains("1841"))
    }

    @Test("Summary of a legacy marker omits what it never recorded")
    func testLegacySummaryHasNoInventedDetail() {
        guard let marker = CrashMarker.parse("SIGBUS\n") else {
            Issue.record("marker failed to parse")
            return
        }

        #expect(marker.summary == "SIGBUS",
            "nothing should be invented for fields the legacy format never had")
    }

    @Test("Detail carries the frames for the log and the export")
    func testDetailIncludesFrames() {
        let text = """
            WOLFWAVE-CRASH 1
            kind=exception
            name=NSRangeException
            reason=out of bounds
            frame=0   WolfWave  0x000  main + 1
            """

        guard let marker = CrashMarker.parse(text) else {
            Issue.record("marker failed to parse")
            return
        }

        let detail = marker.detail
        #expect(detail.contains("NSRangeException"))
        #expect(detail.contains("out of bounds"))
        #expect(detail.contains("main + 1"), "the backtrace is the whole point of keeping the marker")
    }
}
