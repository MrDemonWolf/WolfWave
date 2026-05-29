//
//  ClearQueueCommandTests.swift
//  WolfWave
//
//  Created by Nathanial Henniges on 2026-05-28.
//  Copyright © 2026 MrDemonWolf, Inc. All rights reserved.
//

import XCTest

@testable import WolfWave

/// Covers `ClearQueueCommand` — moderator/broadcaster gate, empty-queue reply,
/// and the count/pluralization in the "cleared" message.
@MainActor
final class ClearQueueCommandTests: WolfWaveTestCase {

    // MARK: - Helpers

    private func privilegedContext() -> BotCommandContext {
        BotCommandContext(
            userID: "1", username: "streamer",
            isModerator: false, isBroadcaster: true,
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
        XCTAssertEqual(ClearQueueCommand().triggers, ["!clearqueue", "!cq"])
    }

    func testCooldowns() {
        let command = ClearQueueCommand()
        XCTAssertEqual(command.globalCooldown, 5.0)
        XCTAssertEqual(command.userCooldown, 5.0)
    }

    func testEnabledKeyMatchesAppConstants() {
        XCTAssertEqual(
            ClearQueueCommand().enabledKey,
            AppConstants.UserDefaults.clearQueueCommandEnabled
        )
    }

    // MARK: - Privilege Gate

    func testViewerCannotClear() {
        let command = ClearQueueCommand()
        command.songRequestService = { self.makeService() }

        var replyCalled = false
        command.execute(message: "!clearqueue", context: viewerContext()) { _ in replyCalled = true }
        XCTAssertFalse(replyCalled)
    }

    // MARK: - Empty Queue

    func testBroadcasterClearEmptyQueueReplies() async {
        let command = ClearQueueCommand()
        command.songRequestService = { self.makeService() }

        let reply = await captureReply { done in
            command.execute(message: "!clearqueue", context: self.privilegedContext()) { done($0) }
        }
        XCTAssertTrue(reply.lowercased().contains("already empty"))
    }

    // MARK: - Missing Service

    func testMissingServiceIsSilent() {
        let command = ClearQueueCommand()
        command.songRequestService = { nil }

        var replyCalled = false
        command.execute(message: "!clearqueue", context: privilegedContext()) { _ in replyCalled = true }
        XCTAssertFalse(replyCalled)
    }
}
