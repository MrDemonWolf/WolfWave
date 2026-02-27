//
//  CooldownManagerTests.swift
//  WolfWaveTests
//
//  Created by MrDemonWolf, Inc. on 2/27/26.
//

import XCTest
@testable import WolfWave

final class CooldownManagerTests: XCTestCase {
    var manager: CooldownManager!

    override func setUp() {
        super.setUp()
        manager = CooldownManager()
    }

    override func tearDown() {
        manager = nil
        super.tearDown()
    }

    // MARK: - No Cooldown Tests

    func testFirstUseIsNotOnCooldown() {
        let result = manager.isOnCooldown(
            trigger: "!song", userID: "user1", isModerator: false,
            globalCooldown: 5.0, userCooldown: 10.0
        )
        XCTAssertFalse(result)
    }

    func testZeroCooldownsNeverBlock() {
        manager.recordUse(trigger: "!song", userID: "user1")
        let result = manager.isOnCooldown(
            trigger: "!song", userID: "user1", isModerator: false,
            globalCooldown: 0, userCooldown: 0
        )
        XCTAssertFalse(result)
    }

    // MARK: - Global Cooldown Tests

    func testGlobalCooldownBlocksAllUsers() {
        manager.recordUse(trigger: "!song", userID: "user1")
        let result = manager.isOnCooldown(
            trigger: "!song", userID: "user2", isModerator: false,
            globalCooldown: 60.0, userCooldown: 0
        )
        XCTAssertTrue(result)
    }

    func testGlobalCooldownDoesNotBlockDifferentTrigger() {
        manager.recordUse(trigger: "!song", userID: "user1")
        let result = manager.isOnCooldown(
            trigger: "!last", userID: "user1", isModerator: false,
            globalCooldown: 60.0, userCooldown: 0
        )
        XCTAssertFalse(result)
    }

    // MARK: - Per-User Cooldown Tests

    func testUserCooldownBlocksSameUser() {
        manager.recordUse(trigger: "!song", userID: "user1")
        let result = manager.isOnCooldown(
            trigger: "!song", userID: "user1", isModerator: false,
            globalCooldown: 0, userCooldown: 60.0
        )
        XCTAssertTrue(result)
    }

    func testUserCooldownDoesNotBlockDifferentUser() {
        manager.recordUse(trigger: "!song", userID: "user1")
        let result = manager.isOnCooldown(
            trigger: "!song", userID: "user2", isModerator: false,
            globalCooldown: 0, userCooldown: 60.0
        )
        XCTAssertFalse(result)
    }

    // MARK: - Moderator Bypass Tests

    func testModeratorBypassesGlobalCooldown() {
        manager.recordUse(trigger: "!song", userID: "user1")
        let result = manager.isOnCooldown(
            trigger: "!song", userID: "mod1", isModerator: true,
            globalCooldown: 60.0, userCooldown: 0
        )
        XCTAssertFalse(result)
    }

    func testModeratorBypassesUserCooldown() {
        manager.recordUse(trigger: "!song", userID: "mod1")
        let result = manager.isOnCooldown(
            trigger: "!song", userID: "mod1", isModerator: true,
            globalCooldown: 0, userCooldown: 60.0
        )
        XCTAssertFalse(result)
    }

    func testModeratorBypassesBothCooldowns() {
        manager.recordUse(trigger: "!song", userID: "mod1")
        let result = manager.isOnCooldown(
            trigger: "!song", userID: "mod1", isModerator: true,
            globalCooldown: 60.0, userCooldown: 60.0
        )
        XCTAssertFalse(result)
    }

    // MARK: - Reset Tests

    func testResetClearsAllCooldowns() {
        manager.recordUse(trigger: "!song", userID: "user1")
        manager.recordUse(trigger: "!last", userID: "user2")
        manager.reset()

        XCTAssertFalse(manager.isOnCooldown(
            trigger: "!song", userID: "user1", isModerator: false,
            globalCooldown: 60.0, userCooldown: 60.0
        ))
        XCTAssertFalse(manager.isOnCooldown(
            trigger: "!last", userID: "user2", isModerator: false,
            globalCooldown: 60.0, userCooldown: 60.0
        ))
    }
}
