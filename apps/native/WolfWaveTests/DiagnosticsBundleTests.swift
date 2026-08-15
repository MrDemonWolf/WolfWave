//
//  DiagnosticsBundleTests.swift
//  WolfWave
//
//  Created by Nathanial Henniges on 2026-08-14.
//  Copyright © 2026 MrDemonWolf, Inc. All rights reserved.
//

import Testing
import Foundation
@testable import WolfWave

/// Tests for the exported diagnostics bundle.
///
/// The composer is pure, so these write temp files and assert on the returned
/// string rather than driving an `NSSavePanel`.
@Suite("DiagnosticsBundle Tests")
struct DiagnosticsBundleTests {

    private func snapshot(
        crashed: Bool = false,
        summary: String? = nil
    ) -> DiagnosticSnapshot {
        DiagnosticSnapshot(
            appVersion: "2.1.1",
            build: "1841",
            osVersion: "Version 26.0",
            arch: "arm64",
            installMethod: .dmg,
            crashedLastLaunch: crashed,
            crashSummary: summary,
            diagnosticsEnabled: false,
            logSizeBytes: 2048,
            logSizeDescription: "2 KB"
        )
    }

    /// Writes `contents` to a uniquely named temp file and returns its URL.
    private func tempLog(_ name: String, _ contents: String) throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "wolfwave-bundle-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appending(path: name)
        try Data(contents.utf8).write(to: url)
        return url
    }

    // MARK: - Header

    @Test("The header identifies the build")
    func testHeaderIdentifiesBuild() {
        let text = DiagnosticsBundle.compose(snapshot: snapshot(), crash: nil, logs: [])

        // A bare log copy carried none of this, so an exported file could not be
        // attributed to a build.
        #expect(text.contains("2.1.1"))
        #expect(text.contains("1841"))
        #expect(text.contains("Version 26.0"))
        #expect(text.contains("arm64"))
        #expect(text.contains("ENVIRONMENT"))
    }

    // MARK: - Crash Section

    @Test("A crash breadcrumb is included when there was one")
    func testIncludesCrash() {
        let text = DiagnosticsBundle.compose(
            snapshot: snapshot(crashed: true, summary: "SIGSEGV at 14:03"),
            crash: "SIGSEGV at 14:03\n  frame 0",
            logs: []
        )

        #expect(text.contains("LAST CRASH"))
        #expect(text.contains("SIGSEGV"))
        #expect(text.contains("frame 0"))
    }

    @Test("No crash section when the last launch was clean")
    func testOmitsCrashWhenClean() {
        let text = DiagnosticsBundle.compose(snapshot: snapshot(), crash: nil, logs: [])

        #expect(!text.contains("LAST CRASH"))
    }

    @Test("An empty crash string is treated as no crash")
    func testEmptyCrashOmitted() {
        let text = DiagnosticsBundle.compose(snapshot: snapshot(), crash: "", logs: [])

        #expect(!text.contains("LAST CRASH"))
    }

    // MARK: - Logs

    @Test("Rotated logs are included, oldest first")
    func testIncludesRotatedLogsInOrder() throws {
        // The bug this fixes: a bare copy of the live log exports a nearly empty
        // file when rotation just fired, while the interesting lines sit in a
        // backup that never gets attached.
        let older = try tempLog("wolfwave.log.1", "OLDEST LINE")
        let live = try tempLog("wolfwave.log", "NEWEST LINE")
        defer {
            try? FileManager.default.removeItem(at: older.deletingLastPathComponent())
            try? FileManager.default.removeItem(at: live.deletingLastPathComponent())
        }

        let text = DiagnosticsBundle.compose(snapshot: snapshot(), crash: nil, logs: [older, live])

        guard let oldIndex = text.range(of: "OLDEST LINE")?.lowerBound,
              let newIndex = text.range(of: "NEWEST LINE")?.lowerBound
        else {
            Issue.record("both logs should appear in the bundle")
            return
        }
        #expect(oldIndex < newIndex, "chronological order, oldest first")
        #expect(text.contains("wolfwave.log.1"), "each section names its source file")
    }

    @Test("An unreadable log is noted rather than aborting the export")
    func testUnreadableLogTolerated() {
        let missing = FileManager.default.temporaryDirectory
            .appending(path: "wolfwave-does-not-exist-\(UUID().uuidString).log")

        let text = DiagnosticsBundle.compose(snapshot: snapshot(), crash: nil, logs: [missing])

        #expect(text.contains("(unreadable)"))
        #expect(text.contains("ENVIRONMENT"), "the rest of the bundle still composes")
    }

    @Test("No logs at all still produces a usable file")
    func testNoLogs() {
        let text = DiagnosticsBundle.compose(snapshot: snapshot(), crash: nil, logs: [])

        #expect(text.contains("(no log file)"))
        #expect(text.contains("ENVIRONMENT"))
    }

    // MARK: - Section Framing

    @Test("Section rules cannot collide with a log line")
    func testSectionRuleIsUnambiguous() {
        let text = DiagnosticsBundle.compose(snapshot: snapshot(), crash: nil, logs: [])

        // Every log record starts with a digit (the ISO timestamp), so a rule of
        // "=" characters can never be mistaken for one by a reader or a parser.
        for line in text.split(separator: "\n") where line.hasPrefix("=") {
            #expect(LogRecord.parse(String(line)) == nil)
        }
    }

    // MARK: - Filename

    @Test("Suggested filename is stamped so exports do not overwrite")
    func testSuggestedFilename() {
        let first = DiagnosticsBundle.suggestedFilename(
            date: Date(timeIntervalSince1970: 1_755_180_000))
        let later = DiagnosticsBundle.suggestedFilename(
            date: Date(timeIntervalSince1970: 1_755_190_000))

        #expect(first.hasPrefix("wolfwave-diagnostics-"))
        #expect(first.hasSuffix(".log"))
        #expect(first != later, "a second export must not silently replace the first")
    }
}
