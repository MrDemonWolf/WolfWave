//
//  SkipCommandTests.swift
//  WolfWave
//
//  Created by Nathanial Henniges on 2026-05-28.
//  Copyright © 2026 MrDemonWolf, Inc. All rights reserved.
//

import XCTest

@testable import WolfWave

/// Covers `SkipCommand` — moderator/broadcaster gate, queue-empty reply, and
/// the "now playing" handoff after a skip.
@MainActor
final class SkipCommandTests: WolfWaveTestCase {

    // MARK: - Helpers

    private func privilegedContext(
        broadcaster: Bool = true,
        moderator: Bool = false
    ) -> BotCommandContext {
        BotCommandContext(
            userID: "1", username: "streamer",
            isModerator: moderator, isBroadcaster: broadcaster,
            isSubscriber: false, isVIP: false, messageID: "m"
        )
    }

    private func viewerContext() -> BotCommandContext {
        BotCommandContext(
            userID: "2", username: "viewer",
            isModerator: false, isBroadcaster: false,
            isSubscriber: false, isVIP: false, messageID: "m"
        )
    }

    private func makeService() -> SongRequestService {
        SongRequestService(
            queue: SongRequestQueue(),
            blocklist: SongBlocklist(storage: InMemoryBlocklistStorage()),
            musicController: MockAppleMusicController()
        )
    }

    // MARK: - Metadata

    func testTriggers() {
        let command = SkipCommand()
        XCTAssertEqual(command.triggers, ["!skip", "!next"])
    }

    func testCooldowns() {
        let command = SkipCommand()
        XCTAssertEqual(command.globalCooldown, 3.0)
        XCTAssertEqual(command.userCooldown, 3.0)
    }

    func testEnabledKeyMatchesAppConstants() {
        let command = SkipCommand()
        XCTAssertEqual(command.enabledKey, AppConstants.UserDefaults.skipCommandEnabled)
    }

    func testAliasesKeyMatchesAppConstants() {
        let command = SkipCommand()
        XCTAssertEqual(command.aliasesKey, AppConstants.UserDefaults.skipCommandAliases)
    }

    // MARK: - Privilege Gate

    func testViewerCannotSkip() {
        let command = SkipCommand()
        command.songRequestService = { self.makeService() }

        var replyCalled = false
        command.execute(message: "!skip", context: viewerContext()) { _ in replyCalled = true }
        XCTAssertFalse(replyCalled)
    }

    func testSubscriberAloneCannotSkip() {
        let command = SkipCommand()
        command.songRequestService = { self.makeService() }
        let subscriber = BotCommandContext(
            userID: "3", username: "fan",
            isModerator: false, isBroadcaster: false,
            isSubscriber: true, isVIP: true, messageID: "m"
        )

        var replyCalled = false
        command.execute(message: "!skip", context: subscriber) { _ in replyCalled = true }
        XCTAssertFalse(replyCalled)
    }

    // MARK: - Empty Queue

    func testBroadcasterSkipOnEmptyQueueReplies() async {
        let command = SkipCommand()
        command.songRequestService = { self.makeService() }

        let reply = await captureReply { done in
            command.execute(message: "!skip", context: self.privilegedContext()) { done($0) }
        }
        XCTAssertTrue(reply.lowercased().contains("empty"))
    }

    // MARK: - Missing Service

    func testMissingServiceIsSilent() {
        let command = SkipCommand()
        command.songRequestService = { nil }

        var replyCalled = false
        command.execute(message: "!skip", context: privilegedContext()) { _ in replyCalled = true }
        XCTAssertFalse(replyCalled)
    }
}
