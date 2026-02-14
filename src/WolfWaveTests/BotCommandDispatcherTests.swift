//
//  BotCommandDispatcherTests.swift
//  WolfWaveTests
//
//  Created by Claude on 2/13/26.
//

import XCTest
@testable import WolfWave

final class BotCommandDispatcherTests: XCTestCase {
    var dispatcher: BotCommandDispatcher!

    override func setUp() {
        super.setUp()
        dispatcher = BotCommandDispatcher()
    }

    override func tearDown() {
        dispatcher = nil
        super.tearDown()
    }

    // MARK: - Default Command Tests

    func testDefaultSongCommandRegistered() {
        dispatcher.setCurrentSongInfo { "Artist - Song" }
        let result = dispatcher.processMessage("!song")
        XCTAssertEqual(result, "Artist - Song")
    }

    func testDefaultLastCommandRegistered() {
        dispatcher.setLastSongInfo { "Previous Artist - Song" }
        let result = dispatcher.processMessage("!last")
        XCTAssertEqual(result, "Previous Artist - Song")
    }

    // MARK: - Non-Command Messages

    func testNonCommandReturnsNil() {
        let result = dispatcher.processMessage("hello")
        XCTAssertNil(result)
    }

    func testEmptyStringReturnsNil() {
        let result = dispatcher.processMessage("")
        XCTAssertNil(result)
    }

    func testOverLengthMessageReturnsNil() {
        let longMessage = String(repeating: "a", count: 501)
        let result = dispatcher.processMessage(longMessage)
        XCTAssertNil(result)
    }

    func testExactly500CharsProcessed() {
        let message = "!song" + String(repeating: " ", count: 495)
        dispatcher.setCurrentSongInfo { "Artist - Song" }
        let result = dispatcher.processMessage(message)
        XCTAssertNotNil(result)
    }

    func testWhitespaceOnlyReturnsNil() {
        let result = dispatcher.processMessage("   ")
        XCTAssertNil(result)
    }

    // MARK: - Callback Wiring Tests

    func testSetCurrentSongInfoCallback() {
        dispatcher.setCurrentSongInfo { "Test Track" }
        let result = dispatcher.processMessage("!song")
        XCTAssertEqual(result, "Test Track")
    }

    func testSetLastSongInfoCallback() {
        dispatcher.setLastSongInfo { "Previous Track" }
        let result = dispatcher.processMessage("!last")
        XCTAssertEqual(result, "Previous Track")
    }

    func testDisableCurrentSongCommand() {
        dispatcher.setCurrentSongInfo { "Artist - Song" }
        dispatcher.setCurrentSongCommandEnabled { false }
        let result = dispatcher.processMessage("!song")
        XCTAssertNil(result)
    }

    func testDisableLastSongCommand() {
        dispatcher.setLastSongInfo { "Artist - Song" }
        dispatcher.setLastSongCommandEnabled { false }
        let result = dispatcher.processMessage("!last")
        XCTAssertNil(result)
    }

    // MARK: - Whitespace Handling

    func testLeadingWhitespaceTrimmed() {
        dispatcher.setCurrentSongInfo { "Track" }
        let result = dispatcher.processMessage("  !song")
        XCTAssertEqual(result, "Track")
    }

    func testTrailingWhitespaceTrimmed() {
        dispatcher.setCurrentSongInfo { "Track" }
        let result = dispatcher.processMessage("!song  ")
        XCTAssertEqual(result, "Track")
    }
}
