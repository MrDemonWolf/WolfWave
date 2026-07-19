//
//  MyQueueCommandTests.swift
//  WolfWave
//
//  Created by Nathanial Henniges on 2026-05-28.
//  Copyright © 2026 MrDemonWolf, Inc. All rights reserved.
//

import XCTest

@testable import WolfWave

/// Covers `MyQueueCommand`. Per-user queue lookup including the
/// "no requests" reply and positional formatting.
@MainActor
final class MyQueueCommandTests: WolfWaveTestCase {

    // MARK: - Helpers

    private func context(username: String) -> BotCommandContext {
        BotCommandContext(
            userID: "1", username: username,
            isModerator: false, isBroadcaster: false,
            isSubscriber: false, isVIP: false, messageID: "m"
        )
    }

    private func makeQueueWith(users: [String]) -> SongRequestQueue {
        // Pin FIFO so positions are deterministic; this suite tests MyQueueCommand
        // reply formatting, not fair-share reordering.
        UserDefaults.standard.set(false, forKey: AppConstants.UserDefaults.songRequestFairShare)
        let queue = SongRequestQueue()
        for (index, user) in users.enumerated() {
            _ = queue.add(SongRequestItem(
                title: "Song \(index + 1)",
                artist: "Artist \(index + 1)",
                requesterUsername: user
            ))
        }
        return queue
    }

    // MARK: - Metadata

    func testTriggers() {
        XCTAssertEqual(MyQueueCommand().triggers, ["!myqueue", "!mysongs"])
    }

    func testEnabledKeyMatchesAppConstants() {
        XCTAssertEqual(
            MyQueueCommand().enabledKey,
            AppConstants.UserDefaults.myQueueCommandEnabled
        )
    }

    // MARK: - Replies

    func testNoRequestsReply() async {
        let command = MyQueueCommand()
        command.getQueue = { self.makeQueueWith(users: ["other_user"]) }

        let reply = await captureReply { done in
            command.execute(message: "!myqueue", context: self.context(username: "viewer")) { done($0) }
        }
        XCTAssertTrue(reply.lowercased().contains("don't have any"))
        XCTAssertTrue(reply.contains("!sr"))
    }

    func testReplyListsCallerSongsWithPositions() async {
        let command = MyQueueCommand()
        command.getQueue = {
            self.makeQueueWith(users: ["alpha", "bravo", "alpha", "charlie"])
        }

        let reply = await captureReply { done in
            command.execute(message: "!myqueue", context: self.context(username: "alpha")) { done($0) }
        }

        XCTAssertTrue(reply.contains("#1"))
        XCTAssertTrue(reply.contains("#3"))
        XCTAssertTrue(reply.contains("Song 1"))
        XCTAssertTrue(reply.contains("Song 3"))
        XCTAssertFalse(reply.contains("Song 2"))
        XCTAssertFalse(reply.contains("Song 4"))
    }

    func testMissingQueueIsSilent() {
        let command = MyQueueCommand()
        command.getQueue = { nil }

        var replyCalled = false
        command.execute(message: "!myqueue", context: context(username: "alpha")) { _ in replyCalled = true }
        XCTAssertFalse(replyCalled)
    }
}
