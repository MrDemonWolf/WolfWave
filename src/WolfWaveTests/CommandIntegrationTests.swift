//
//  CommandIntegrationTests.swift
//  WolfWaveTests
//
//  Created by MrDemonWolf, Inc. on 3/19/26.
//

import XCTest
@testable import WolfWave

final class CommandIntegrationTests: XCTestCase {
    var dispatcher: BotCommandDispatcher!

    /// Removes all cooldown and enable/disable keys from UserDefaults to ensure test isolation.
    private func clearCommandDefaults() {
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: AppConstants.UserDefaults.songCommandGlobalCooldown)
        defaults.removeObject(forKey: AppConstants.UserDefaults.songCommandUserCooldown)
        defaults.removeObject(forKey: AppConstants.UserDefaults.lastSongCommandGlobalCooldown)
        defaults.removeObject(forKey: AppConstants.UserDefaults.lastSongCommandUserCooldown)
        defaults.removeObject(forKey: AppConstants.UserDefaults.currentSongCommandEnabled)
        defaults.removeObject(forKey: AppConstants.UserDefaults.lastSongCommandEnabled)
    }

    override func setUp() {
        super.setUp()
        dispatcher = BotCommandDispatcher()
        clearCommandDefaults()
    }

    override func tearDown() {
        clearCommandDefaults()
        dispatcher = nil
        super.tearDown()
    }

    // MARK: - Full Flow Tests

    func testFullFlowSongCommand() {
        dispatcher.setCurrentSongInfo { "Daft Punk - Around The World" }
        let result = dispatcher.processMessage("!song", userID: "user1")
        XCTAssertEqual(result, "Daft Punk - Around The World")
    }

    func testFullFlowLastSongCommand() {
        dispatcher.setLastSongInfo { "Queen - Bohemian Rhapsody" }
        let result = dispatcher.processMessage("!last", userID: "user1")
        XCTAssertEqual(result, "Queen - Bohemian Rhapsody")
    }

    func testNoCallbackReturnsDefaultMessage() {
        let result = dispatcher.processMessage("!song", userID: "user1")
        XCTAssertEqual(result, "No track currently playing")
    }

    // MARK: - Cooldown Blocking Tests

    func testCooldownBlocksSecondRapidCall() {
        dispatcher.setCurrentSongInfo { "Artist - Song" }

        let defaults = UserDefaults.standard
        defaults.set(15.0, forKey: AppConstants.UserDefaults.songCommandGlobalCooldown)
        defaults.set(15.0, forKey: AppConstants.UserDefaults.songCommandUserCooldown)

        let first = dispatcher.processMessage("!song", userID: "user1")
        XCTAssertNotNil(first)

        let second = dispatcher.processMessage("!song", userID: "user1")
        XCTAssertNil(second, "Second rapid call should be blocked by cooldown")
    }

    // MARK: - Cross-Command Isolation Tests

    func testCrossCommandIsolation() {
        dispatcher.setCurrentSongInfo { "Artist - Song" }
        dispatcher.setLastSongInfo { "Previous - Track" }

        let defaults = UserDefaults.standard
        defaults.set(15.0, forKey: AppConstants.UserDefaults.songCommandGlobalCooldown)
        defaults.set(15.0, forKey: AppConstants.UserDefaults.songCommandUserCooldown)
        defaults.set(15.0, forKey: AppConstants.UserDefaults.lastSongCommandGlobalCooldown)
        defaults.set(15.0, forKey: AppConstants.UserDefaults.lastSongCommandUserCooldown)

        let songResult = dispatcher.processMessage("!song", userID: "user1")
        XCTAssertNotNil(songResult)

        let lastResult = dispatcher.processMessage("!last", userID: "user1")
        XCTAssertNotNil(lastResult, "!last should not be blocked by !song cooldown")
    }

    // MARK: - Enable/Disable Mid-Flow Tests

    func testEnableDisableMidFlow() {
        dispatcher.setCurrentSongInfo { "Artist - Song" }
        dispatcher.setCurrentSongCommandEnabled { true }

        let enabled = dispatcher.processMessage("!song", userID: "user1")
        XCTAssertNotNil(enabled)

        // Now disable — reset cooldowns first so cooldown doesn't interfere
        dispatcher.resetCooldowns()
        dispatcher.setCurrentSongCommandEnabled { false }

        let disabled = dispatcher.processMessage("!song", userID: "user2")
        XCTAssertNil(disabled, "Disabled command should return nil")
    }

    // MARK: - Response Truncation Through Full Pipeline

    func testResponseTruncationThroughPipeline() {
        let longString = String(repeating: "a", count: 600)
        dispatcher.setCurrentSongInfo { longString }

        let result = dispatcher.processMessage("!song", userID: "user1")
        guard let result = result else {
            XCTFail("Expected non-nil result")
            return
        }
        XCTAssertEqual(result.count, 500)
        XCTAssertTrue(result.hasSuffix("..."))
    }

    // MARK: - Multi-User Cooldown Tests

    func testMultipleUsersWithCooldowns() {
        dispatcher.setCurrentSongInfo { "Artist - Song" }

        let defaults = UserDefaults.standard
        defaults.set(0.0, forKey: AppConstants.UserDefaults.songCommandGlobalCooldown)
        defaults.set(15.0, forKey: AppConstants.UserDefaults.songCommandUserCooldown)

        let user1First = dispatcher.processMessage("!song", userID: "user1")
        XCTAssertNotNil(user1First)

        let user2First = dispatcher.processMessage("!song", userID: "user2")
        XCTAssertNotNil(user2First, "Different user should not be blocked by per-user cooldown")

        let user1Second = dispatcher.processMessage("!song", userID: "user1")
        XCTAssertNil(user1Second, "Same user should be blocked by per-user cooldown")
    }

    // MARK: - Broadcaster Bypass Tests

    func testBroadcasterBypassThroughPipeline() {
        dispatcher.setCurrentSongInfo { "Artist - Song" }

        let defaults = UserDefaults.standard
        defaults.set(15.0, forKey: AppConstants.UserDefaults.songCommandGlobalCooldown)
        defaults.set(15.0, forKey: AppConstants.UserDefaults.songCommandUserCooldown)

        let first = dispatcher.processMessage("!song", userID: "broadcaster1", isModerator: true)
        XCTAssertNotNil(first)

        let second = dispatcher.processMessage("!song", userID: "broadcaster1", isModerator: true)
        XCTAssertNotNil(second, "Broadcaster should bypass cooldowns")
    }

    // MARK: - Reset Cooldowns Tests

    func testResetCooldownsClearsAllState() {
        dispatcher.setCurrentSongInfo { "Artist - Song" }

        let defaults = UserDefaults.standard
        defaults.set(15.0, forKey: AppConstants.UserDefaults.songCommandGlobalCooldown)
        defaults.set(15.0, forKey: AppConstants.UserDefaults.songCommandUserCooldown)

        let first = dispatcher.processMessage("!song", userID: "user1")
        XCTAssertNotNil(first)

        let blocked = dispatcher.processMessage("!song", userID: "user1")
        XCTAssertNil(blocked)

        dispatcher.resetCooldowns()

        let afterReset = dispatcher.processMessage("!song", userID: "user1")
        XCTAssertNotNil(afterReset, "After reset, command should work again")
    }

    // MARK: - Zero Cooldown Tests

    func testZeroCooldownNeverBlocks() {
        dispatcher.setCurrentSongInfo { "Artist - Song" }

        let defaults = UserDefaults.standard
        defaults.set(0.0, forKey: AppConstants.UserDefaults.songCommandGlobalCooldown)
        defaults.set(0.0, forKey: AppConstants.UserDefaults.songCommandUserCooldown)

        let first = dispatcher.processMessage("!song", userID: "user1")
        XCTAssertNotNil(first)

        let second = dispatcher.processMessage("!song", userID: "user1")
        XCTAssertNotNil(second, "Zero cooldown should never block")
    }

    // MARK: - Alias Through Full Pipeline Tests

    func testAllSongAliasesWorkThroughPipeline() {
        dispatcher.setCurrentSongInfo { "Artist - Song" }

        let defaults = UserDefaults.standard
        defaults.set(0.0, forKey: AppConstants.UserDefaults.songCommandGlobalCooldown)
        defaults.set(0.0, forKey: AppConstants.UserDefaults.songCommandUserCooldown)

        XCTAssertNotNil(dispatcher.processMessage("!song", userID: "u1"))
        XCTAssertNotNil(dispatcher.processMessage("!currentsong", userID: "u2"))
        XCTAssertNotNil(dispatcher.processMessage("!nowplaying", userID: "u3"))
    }

    func testAllLastAliasesWorkThroughPipeline() {
        dispatcher.setLastSongInfo { "Previous - Track" }

        let defaults = UserDefaults.standard
        defaults.set(0.0, forKey: AppConstants.UserDefaults.lastSongCommandGlobalCooldown)
        defaults.set(0.0, forKey: AppConstants.UserDefaults.lastSongCommandUserCooldown)

        XCTAssertNotNil(dispatcher.processMessage("!last", userID: "u1"))
        XCTAssertNotNil(dispatcher.processMessage("!lastsong", userID: "u2"))
        XCTAssertNotNil(dispatcher.processMessage("!prevsong", userID: "u3"))
    }

    // MARK: - Non-Command Message Short Circuit

    func testNonCommandMessageShortCircuits() {
        dispatcher.setCurrentSongInfo { "Artist - Song" }
        XCTAssertNil(dispatcher.processMessage("hello world", userID: "user1"))
        XCTAssertNil(dispatcher.processMessage("", userID: "user1"))
        XCTAssertNil(dispatcher.processMessage("   ", userID: "user1"))
    }
}
