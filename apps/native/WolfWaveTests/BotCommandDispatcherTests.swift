//
//  BotCommandDispatcherTests.swift
//  WolfWave
//
//  Created by Nathanial Henniges on 2026-02-13.
//  Copyright © 2026 MrDemonWolf, Inc. All rights reserved.
//

import XCTest
@testable import WolfWave

@MainActor
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
        // "!song" + space + filler = 500 chars. Routing matches on the first
        // whitespace token, so the trailing filler must be separated by a space
        // to register as a real command invocation.
        let message = "!song " + String(repeating: "x", count: 494)
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

    func testAsyncCommandIsAwaitedAndReturned() async {
        let command = AwaitedTestCommand()
        dispatcher.register(command)
        let context = BotCommandContext(
            userID: "viewer-1",
            username: "Viewer",
            isModerator: false,
            isBroadcaster: false,
            isSubscriber: false,
            isVIP: false,
            messageID: "message-1")

        let result = await dispatcher.processMessageAsync(
            "!awaited",
            userID: context.userID,
            context: context)

        XCTAssertTrue(command.didExecute)
        XCTAssertEqual(result, "awaited response")
    }

    func testDeniedServiceCommandDoesNotConsumeCooldown() async {
        let command = PrivilegedCooldownTestCommand()
        dispatcher.register(command)
        let viewer = BotCommandContext(
            userID: "viewer-1",
            username: "Viewer",
            isModerator: false,
            isBroadcaster: false,
            isSubscriber: false,
            isVIP: false,
            messageID: "message-1")
        let broadcaster = BotCommandContext(
            userID: "broadcaster-1",
            username: "Broadcaster",
            isModerator: false,
            isBroadcaster: true,
            isSubscriber: false,
            isVIP: false,
            messageID: "message-2")

        let denied = await dispatcher.processMessageAsync(
            "!privileged-cooldown",
            userID: viewer.userID,
            context: viewer)
        let allowed = await dispatcher.processMessageAsync(
            "!privileged-cooldown",
            userID: broadcaster.userID,
            context: broadcaster)

        XCTAssertNil(denied)
        XCTAssertEqual(allowed, "privileged response")
        XCTAssertEqual(command.executionCount, 1)
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
        let defaults = DefaultsStore.store
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

        let defaults = DefaultsStore.store
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

        let defaults = DefaultsStore.store
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

@MainActor
private final class AwaitedTestCommand: @MainActor AsyncBotCommand {
    let triggers = ["!awaited"]
    let description = "Test structured async dispatch"
    let globalCooldown: TimeInterval = 0
    let userCooldown: TimeInterval = 0
    private(set) var didExecute = false

    func execute(message: String, context: BotCommandContext) async -> String? {
        await Task.yield()
        didExecute = true
        return "awaited response"
    }
}

@MainActor
private final class PrivilegedCooldownTestCommand: @MainActor ServiceBoundCommand {
    let triggers = ["!privileged-cooldown"]
    let description = "Test privileged cooldown reservation"
    let globalCooldown: TimeInterval = 60
    let userCooldown: TimeInterval = 60
    var songRequestService: (() -> SongRequestService?)?
    private(set) var executionCount = 0

    func execute(message: String, context: BotCommandContext) async -> String? {
        // Mirrors the production commands' execute-time privilege defense.
        guard context.isPrivileged else { return nil }
        executionCount += 1
        return "privileged response"
    }
}
