//
//  LastSongCommandTests.swift
//  WolfWaveTests
//
//  Created by Claude on 2/13/26.
//

import XCTest
@testable import WolfWave

final class LastSongCommandTests: XCTestCase {
    var command: LastSongCommand!

    override func setUp() {
        super.setUp()
        command = LastSongCommand()
    }

    override func tearDown() {
        command = nil
        super.tearDown()
    }

    // MARK: - Trigger Tests

    func testLastTrigger() {
        command.getLastSongInfo = { "Previous Artist - Previous Song" }
        XCTAssertNotNil(command.execute(message: "!last"))
    }

    func testLastSongTrigger() {
        command.getLastSongInfo = { "Previous Artist - Previous Song" }
        XCTAssertNotNil(command.execute(message: "!lastsong"))
    }

    func testPrevSongTrigger() {
        command.getLastSongInfo = { "Previous Artist - Previous Song" }
        XCTAssertNotNil(command.execute(message: "!prevsong"))
    }

    func testTriggerCaseInsensitiveUppercase() {
        command.getLastSongInfo = { "Artist - Song" }
        XCTAssertNotNil(command.execute(message: "!LAST"))
    }

    func testTriggerCaseInsensitiveMixed() {
        command.getLastSongInfo = { "Artist - Song" }
        XCTAssertNotNil(command.execute(message: "!LastSong"))
    }

    func testTriggerCaseInsensitivePrevSong() {
        command.getLastSongInfo = { "Artist - Song" }
        XCTAssertNotNil(command.execute(message: "!PREVSONG"))
    }

    func testNonMatchingMessageReturnsNil() {
        command.getLastSongInfo = { "Artist - Song" }
        XCTAssertNil(command.execute(message: "hello world"))
    }

    // MARK: - Callback Tests

    func testNoCallbackReturnsDefaultMessage() {
        let result = command.execute(message: "!last")
        XCTAssertEqual(result, "No previous track available")
    }

    func testWithCallbackReturnsCallbackValue() {
        command.getLastSongInfo = { "Daft Punk - One More Time" }
        let result = command.execute(message: "!last")
        XCTAssertEqual(result, "Daft Punk - One More Time")
    }

    // MARK: - Enable/Disable Tests

    func testDisabledReturnsNil() {
        command.getLastSongInfo = { "Artist - Song" }
        command.isEnabled = { false }
        XCTAssertNil(command.execute(message: "!last"))
    }

    func testEnabledReturnsResponse() {
        command.getLastSongInfo = { "Artist - Song" }
        command.isEnabled = { true }
        XCTAssertNotNil(command.execute(message: "!last"))
    }

    func testIsEnabledNotSetDefaultsToEnabled() {
        command.getLastSongInfo = { "Artist - Song" }
        XCTAssertNotNil(command.execute(message: "!last"))
    }

    // MARK: - Truncation Tests

    func testLongResponseTruncatedTo500() {
        let longString = String(repeating: "b", count: 600)
        command.getLastSongInfo = { longString }
        let result = command.execute(message: "!last")!
        XCTAssertEqual(result.count, 500)
        XCTAssertTrue(result.hasSuffix("..."))
    }

    func testExactly500CharsNotTruncated() {
        let exact = String(repeating: "b", count: 500)
        command.getLastSongInfo = { exact }
        let result = command.execute(message: "!last")!
        XCTAssertEqual(result.count, 500)
        XCTAssertFalse(result.hasSuffix("..."))
    }

    // MARK: - Edge Cases

    func testTriggerWithTrailingText() {
        command.getLastSongInfo = { "Artist - Song" }
        XCTAssertNotNil(command.execute(message: "!last extra stuff"))
    }

    func testTriggersArrayContents() {
        XCTAssertEqual(command.triggers, ["!last", "!lastsong", "!prevsong"])
    }
}
