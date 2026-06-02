//
//  LoggerClearTests.swift
//  WolfWave
//
//  Created by Nathanial Henniges on 2026-05-15.
//  Copyright © 2026 MrDemonWolf, Inc. All rights reserved.
//

import Testing
@testable import WolfWave

// Declared as a nested sub-suite of `LoggerTests` so it inherits that suite's
// `.serialized` trait. `Log` is a process-global singleton with a single
// on-disk file; `clearLogFile()` truncates that file. Running these clear
// tests in parallel with `LoggerTests`' file-readback tests let the truncation
// race a concurrent read and made `testLogFileContent` flaky in CI. Sharing the
// serialized parent guarantees clearing and reading never overlap.
extension LoggerTests {

    @MainActor
    @Suite("Logger Clear Tests")
    struct ClearTests {

        @Test("Log file size is non-negative")
        func logFileSizeIsNonNegative() {
            #expect(Log.logFileSize() >= 0)
        }

        @Test("Log line count is non-negative")
        func logLineCountIsNonNegative() {
            #expect(Log.logLineCount() >= 0)
        }

        @Test("Clearing the log truncates the file and writes a header")
        func clearLogFileTruncatesAndWritesHeader() {
            // Write some content first.
            Log.info("Pre-clear marker", category: "Test")
            Log.info("Another line", category: "Test")
            // Drain the async file queue before measuring.
            Log.flush()

            let sizeBefore = Log.logFileSize()
            Log.clearLogFile()
            let sizeAfter = Log.logFileSize()

            // After clear, file should be much smaller (just the header line).
            #expect(sizeAfter < sizeBefore + 1)
            #expect(sizeAfter > 0, "header line should be written")

            // Line count after clear should be exactly 1 (the header).
            #expect(Log.logLineCount() == 1)
        }
    }
}
