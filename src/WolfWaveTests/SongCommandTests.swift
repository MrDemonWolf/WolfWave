//
//  SongCommandTests.swift
//  WolfWaveTests
//
//  Created by MrDemonWolf, Inc. on 2/13/26.
//

import XCTest
@testable import WolfWave

final class SongCommandTests: XCTestCase {
    var command: SongCommand!

    override func setUp() {
        super.setUp()
        command = SongCommand()
    }

    override func tearDown() {
        command = nil
        super.tearDown()
    }

    // MARK: - Trigger Tests

    func testSongTrigger() {
        command.getCurrentSongInfo = { "Artist - Song" }
        XCTAssertNotNil(command.execute(message: "!song"))
    }

    func testCurrentSongTrigger() {
        command.getCurrentSongInfo = { "Artist - Song" }
        XCTAssertNotNil(command.execute(message: "!currentsong"))
    }

    func testNowPlayingTrigger() {
        command.getCurrentSongInfo = { "Artist - Song" }
        XCTAssertNotNil(command.execute(message: "!nowplaying"))
    }

    func testTriggerCaseInsensitiveUppercase() {
        command.getCurrentSongInfo = { "Artist - Song" }
        XCTAssertNotNil(command.execute(message: "!SONG"))
    }

    func testTriggerCaseInsensitiveMixed() {
        command.getCurrentSongInfo = { "Artist - Song" }
        XCTAssertNotNil(command.execute(message: "!Song"))
    }

    func testTriggerCaseInsensitiveNowPlaying() {
        command.getCurrentSongInfo = { "Artist - Song" }
        XCTAssertNotNil(command.execute(message: "!NowPlaying"))
    }

    func testNonMatchingMessageReturnsNil() {
        command.getCurrentSongInfo = { "Artist - Song" }
        XCTAssertNil(command.execute(message: "hello world"))
    }

    // MARK: - Callback Tests

    func testNoCallbackReturnsDefaultMessage() {
        let result = command.execute(message: "!song")
        XCTAssertEqual(result, "No track currently playing")
    }

    func testWithCallbackReturnsCallbackValue() {
        command.getCurrentSongInfo = { "Daft Punk - Around The World" }
        let result = command.execute(message: "!song")
        XCTAssertEqual(result, "Daft Punk - Around The World")
    }

    // MARK: - Enable/Disable Tests

    func testDisabledReturnsNil() {
        command.getCurrentSongInfo = { "Artist - Song" }
        command.isEnabled = { false }
        XCTAssertNil(command.execute(message: "!song"))
    }

    func testEnabledReturnsResponse() {
        command.getCurrentSongInfo = { "Artist - Song" }
        command.isEnabled = { true }
        XCTAssertNotNil(command.execute(message: "!song"))
    }

    func testIsEnabledNotSetDefaultsToEnabled() {
        command.getCurrentSongInfo = { "Artist - Song" }
        XCTAssertNotNil(command.execute(message: "!song"))
    }

    // MARK: - Truncation Tests

    func testLongResponseTruncatedTo500() {
        let longString = String(repeating: "a", count: 600)
        command.getCurrentSongInfo = { longString }
        let result = command.execute(message: "!song")!
        XCTAssertEqual(result.count, 500)
        XCTAssertTrue(result.hasSuffix("..."))
    }

    func testExactly500CharsNotTruncated() {
        let exact = String(repeating: "a", count: 500)
        command.getCurrentSongInfo = { exact }
        let result = command.execute(message: "!song")!
        XCTAssertEqual(result.count, 500)
        XCTAssertFalse(result.hasSuffix("..."))
    }

    // MARK: - Edge Cases

    func testTriggerWithTrailingText() {
        command.getCurrentSongInfo = { "Artist - Song" }
        let result = command.execute(message: "!song extra stuff")
        XCTAssertNotNil(result)
    }

    func testTriggersArrayContents() {
        XCTAssertEqual(command.triggers, ["!song", "!currentsong", "!nowplaying"])
    }

    func testDescriptionValue() {
        XCTAssertEqual(command.description, "Displays the currently playing track")
    }
}
