//
//  BotCommandDispatcherTests.swift
//  WolfWaveTests
//
//  Created by MrDemonWolf, Inc. on 2/13/26.
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
        let message = "!song" + String(repeating: "x", count: 495)
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

    // MARK: - Alias Cooldown Grouping Tests

    func testSongAliasesShareCooldown() {
        dispatcher.setCurrentSongInfo { "Artist - Song" }

        // Set a non-zero cooldown so the second call is blocked
        let defaults = UserDefaults.standard
        defaults.set(15.0, forKey: AppConstants.UserDefaults.songCommandGlobalCooldown)
        defaults.set(15.0, forKey: AppConstants.UserDefaults.songCommandUserCooldown)

        let first = dispatcher.processMessage("!song", userID: "user1")
        XCTAssertNotNil(first, "First !song call should succeed")

        let second = dispatcher.processMessage("!currentsong", userID: "user1")
        XCTAssertNil(second, "!currentsong should be blocked by shared cooldown with !song")

        let third = dispatcher.processMessage("!nowplaying", userID: "user1")
        XCTAssertNil(third, "!nowplaying should be blocked by shared cooldown with !song")

        // Cleanup
        defaults.removeObject(forKey: AppConstants.UserDefaults.songCommandGlobalCooldown)
        defaults.removeObject(forKey: AppConstants.UserDefaults.songCommandUserCooldown)
    }

    func testBroadcasterAlwaysBypassesCooldown() {
        dispatcher.setCurrentSongInfo { "Artist - Song" }

        let defaults = UserDefaults.standard
        defaults.set(15.0, forKey: AppConstants.UserDefaults.songCommandGlobalCooldown)
        defaults.set(15.0, forKey: AppConstants.UserDefaults.songCommandUserCooldown)

        // Broadcaster always bypasses cooldowns (isModerator: true)
        let first = dispatcher.processMessage("!song", userID: "broadcaster1", isModerator: true)
        XCTAssertNotNil(first, "First !song call should succeed")

        let second = dispatcher.processMessage("!song", userID: "broadcaster1", isModerator: true)
        XCTAssertNotNil(second, "Broadcaster should always bypass cooldown")

        // Cleanup
        defaults.removeObject(forKey: AppConstants.UserDefaults.songCommandGlobalCooldown)
        defaults.removeObject(forKey: AppConstants.UserDefaults.songCommandUserCooldown)
    }

    func testLastSongAliasesShareCooldown() {
        dispatcher.setLastSongInfo { "Previous Artist - Song" }

        let defaults = UserDefaults.standard
        defaults.set(15.0, forKey: AppConstants.UserDefaults.lastSongCommandGlobalCooldown)
        defaults.set(15.0, forKey: AppConstants.UserDefaults.lastSongCommandUserCooldown)

        let first = dispatcher.processMessage("!last", userID: "user1")
        XCTAssertNotNil(first, "First !last call should succeed")

        let second = dispatcher.processMessage("!lastsong", userID: "user1")
        XCTAssertNil(second, "!lastsong should be blocked by shared cooldown with !last")

        let third = dispatcher.processMessage("!prevsong", userID: "user1")
        XCTAssertNil(third, "!prevsong should be blocked by shared cooldown with !last")

        // Cleanup
        defaults.removeObject(forKey: AppConstants.UserDefaults.lastSongCommandGlobalCooldown)
        defaults.removeObject(forKey: AppConstants.UserDefaults.lastSongCommandUserCooldown)
    }
}
