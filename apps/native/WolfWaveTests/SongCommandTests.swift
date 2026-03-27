//
//  SongCommandTests.swift
//  WolfWaveTests
//
//  Created by MrDemonWolf, Inc. on 2/13/26.
//

import XCTest
@testable import WolfWave

final class SongCommandTests: XCTestCase {
    var command: TrackInfoCommand!

    override func setUp() {
        super.setUp()
        command = TrackInfoCommand(
            triggers: ["!song", "!currentsong", "!nowplaying"],
            description: "Displays the currently playing track",
            defaultMessage: "No track currently playing"
        )
    }

    override func tearDown() {
        command = nil
        super.tearDown()
    }

    // MARK: - Trigger Tests

    func testSongTrigger() {
        command.getTrackInfo = { "Artist - Song" }
        XCTAssertNotNil(command.execute(message: "!song"))
    }

    func testCurrentSongTrigger() {
        command.getTrackInfo = { "Artist - Song" }
        XCTAssertNotNil(command.execute(message: "!currentsong"))
    }

    func testNowPlayingTrigger() {
        command.getTrackInfo = { "Artist - Song" }
        XCTAssertNotNil(command.execute(message: "!nowplaying"))
    }

    func testTriggerCaseInsensitiveUppercase() {
        command.getTrackInfo = { "Artist - Song" }
        XCTAssertNotNil(command.execute(message: "!SONG"))
    }

    func testTriggerCaseInsensitiveMixed() {
        command.getTrackInfo = { "Artist - Song" }
        XCTAssertNotNil(command.execute(message: "!Song"))
    }

    func testTriggerCaseInsensitiveNowPlaying() {
        command.getTrackInfo = { "Artist - Song" }
        XCTAssertNotNil(command.execute(message: "!NowPlaying"))
    }

    func testNonMatchingMessageReturnsNil() {
        command.getTrackInfo = { "Artist - Song" }
        XCTAssertNil(command.execute(message: "hello world"))
    }

    // MARK: - Callback Tests

    func testNoCallbackReturnsDefaultMessage() {
        let result = command.execute(message: "!song")
        XCTAssertEqual(result, "No track currently playing")
    }

    func testWithCallbackReturnsCallbackValue() {
        command.getTrackInfo = { "Daft Punk - Around The World" }
        let result = command.execute(message: "!song")
        XCTAssertEqual(result, "Daft Punk - Around The World")
    }

    // MARK: - Enable/Disable Tests

    func testDisabledReturnsNil() {
        command.getTrackInfo = { "Artist - Song" }
        command.isEnabled = { false }
        XCTAssertNil(command.execute(message: "!song"))
    }

    func testEnabledReturnsResponse() {
        command.getTrackInfo = { "Artist - Song" }
        command.isEnabled = { true }
        XCTAssertNotNil(command.execute(message: "!song"))
    }

    func testIsEnabledNotSetDefaultsToEnabled() {
        command.getTrackInfo = { "Artist - Song" }
        XCTAssertNotNil(command.execute(message: "!song"))
    }

    // MARK: - Truncation Tests

    func testLongResponseTruncatedTo500() {
        let longString = String(repeating: "a", count: 600)
        command.getTrackInfo = { longString }
        guard let result = command.execute(message: "!song") else {
            XCTFail("Expected non-nil result")
            return
        }
        XCTAssertEqual(result.count, 500)
        XCTAssertTrue(result.hasSuffix("..."))
    }

    func testExactly500CharsNotTruncated() {
        let exact = String(repeating: "a", count: 500)
        command.getTrackInfo = { exact }
        guard let result = command.execute(message: "!song") else {
            XCTFail("Expected non-nil result")
            return
        }
        XCTAssertEqual(result.count, 500)
        XCTAssertFalse(result.hasSuffix("..."))
    }

    // MARK: - Edge Cases

    func testTriggerWithTrailingText() {
        command.getTrackInfo = { "Artist - Song" }
        let result = command.execute(message: "!song extra stuff")
        XCTAssertNotNil(result)
    }

    func testTriggersArrayContents() {
        XCTAssertEqual(command.triggers, ["!song", "!currentsong", "!nowplaying"])
    }

    func testDescriptionValue() {
        XCTAssertEqual(command.description, "Displays the currently playing track")
    }

    // MARK: - Boundary Truncation Tests

    func testCallbackReturning501CharsTruncates() {
        let text = String(repeating: "b", count: 501)
        command.getTrackInfo = { text }
        guard let result = command.execute(message: "!song") else {
            XCTFail("Expected non-nil result")
            return
        }
        XCTAssertEqual(result.count, 500)
        XCTAssertTrue(result.hasSuffix("..."))
    }

    func testDefaultCooldownValues() {
        XCTAssertEqual(command.globalCooldown, 15.0)
        XCTAssertEqual(command.userCooldown, 15.0)
    }
}
