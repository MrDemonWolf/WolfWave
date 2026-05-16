//
//  LoggerClearTests.swift
//  WolfWaveTests
//
//  Created by MrDemonWolf, Inc. on 5/15/26.
//

import XCTest
@testable import WolfWave

final class LoggerClearTests: XCTestCase {

    func testLogFileSizeIsNonNegative() {
        let size = Log.logFileSize()
        XCTAssertGreaterThanOrEqual(size, 0)
    }

    func testLogLineCountIsNonNegative() {
        let count = Log.logLineCount()
        XCTAssertGreaterThanOrEqual(count, 0)
    }

    func testClearLogFileTruncatesAndWritesHeader() {
        // Write some content first
        Log.info("Pre-clear marker", category: "Test")
        Log.info("Another line", category: "Test")
        // Allow async file writes to flush
        Thread.sleep(forTimeInterval: 0.2)

        let sizeBefore = Log.logFileSize()
        Log.clearLogFile()
        let sizeAfter = Log.logFileSize()

        // After clear, file should be much smaller (just the header line)
        XCTAssertLessThan(sizeAfter, sizeBefore + 1)
        XCTAssertGreaterThan(sizeAfter, 0, "header line should be written")

        // Line count after clear should be exactly 1 (the header).
        let lines = Log.logLineCount()
        XCTAssertEqual(lines, 1)
    }
}
