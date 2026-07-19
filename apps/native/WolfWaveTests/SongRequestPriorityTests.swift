//
//  SongRequestPriorityTests.swift
//  WolfWave
//
//  Created by Nathanial Henniges on 2026-07-18.
//  Copyright © 2026 MrDemonWolf, Inc. All rights reserved.
//

import XCTest

@testable import WolfWave

/// Covers the Sub/VIP request-priority perk: mode resolution, who qualifies, and
/// the `!sr` cooldown-bypass hook the dispatcher honors.
@MainActor
final class SongRequestPriorityTests: WolfWaveTestCase {

    override func setUp() {
        super.setUp()
        resetAllSettings()
    }

    override func tearDown() {
        resetAllSettings()
        super.tearDown()
    }

    private func context(sub: Bool = false, vip: Bool = false, mod: Bool = false, broadcaster: Bool = false) -> BotCommandContext {
        BotCommandContext(
            userID: "1", username: "viewer",
            isModerator: mod, isBroadcaster: broadcaster,
            isSubscriber: sub, isVIP: vip, messageID: "m"
        )
    }

    // MARK: - Mode

    func testDefaultModeIsOff() {
        XCTAssertEqual(SongRequestPriority.mode(), .off)
    }

    func testModeReadsPreference() {
        UserDefaults.standard.set(SongRequestPriorityMode.queueJump.rawValue,
                                  forKey: AppConstants.UserDefaults.songRequestPriorityMode)
        XCTAssertEqual(SongRequestPriority.mode(), .queueJump)
    }

    func testCooldownSkipTiers() {
        XCTAssertFalse(SongRequestPriorityMode.off.skipsCooldown)
        XCTAssertTrue(SongRequestPriorityMode.cooldownSkip.skipsCooldown)
        XCTAssertTrue(SongRequestPriorityMode.queueJump.skipsCooldown)
    }

    func testQueueJumpTiers() {
        XCTAssertFalse(SongRequestPriorityMode.off.jumpsQueue)
        XCTAssertFalse(SongRequestPriorityMode.cooldownSkip.jumpsQueue)
        XCTAssertTrue(SongRequestPriorityMode.queueJump.jumpsQueue)
    }

    // MARK: - Qualification

    func testPlainViewerDoesNotQualify() {
        XCTAssertFalse(SongRequestPriority.qualifies(context()))
    }

    func testSubVipModBroadcasterQualify() {
        XCTAssertTrue(SongRequestPriority.qualifies(context(sub: true)))
        XCTAssertTrue(SongRequestPriority.qualifies(context(vip: true)))
        XCTAssertTrue(SongRequestPriority.qualifies(context(mod: true)))
        XCTAssertTrue(SongRequestPriority.qualifies(context(broadcaster: true)))
    }

    // MARK: - Command cooldown bypass

    func testCommandBypassesCooldownForSubWhenEnabled() {
        UserDefaults.standard.set(SongRequestPriorityMode.cooldownSkip.rawValue,
                                  forKey: AppConstants.UserDefaults.songRequestPriorityMode)
        XCTAssertTrue(SongRequestCommand().bypassesCooldown(context: context(sub: true)))
    }

    func testCommandDoesNotBypassForPlainViewer() {
        UserDefaults.standard.set(SongRequestPriorityMode.queueJump.rawValue,
                                  forKey: AppConstants.UserDefaults.songRequestPriorityMode)
        XCTAssertFalse(SongRequestCommand().bypassesCooldown(context: context()))
    }

    func testCommandDoesNotBypassWhenModeOff() {
        XCTAssertFalse(SongRequestCommand().bypassesCooldown(context: context(sub: true)))
    }

    func testCommandDoesNotBypassWithoutContext() {
        UserDefaults.standard.set(SongRequestPriorityMode.queueJump.rawValue,
                                  forKey: AppConstants.UserDefaults.songRequestPriorityMode)
        XCTAssertFalse(SongRequestCommand().bypassesCooldown(context: nil))
    }
}
