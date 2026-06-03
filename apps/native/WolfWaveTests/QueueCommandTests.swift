//
//  QueueCommandTests.swift
//  WolfWave
//
//  Created by Nathanial Henniges on 2026-05-28.
//  Copyright © 2026 MrDemonWolf, Inc. All rights reserved.
//

import XCTest

@testable import WolfWave

/// Covers `QueueCommand`: empty-queue reply, queue summary, the 5-item cap,
/// and the "...and N more" suffix.
@MainActor
final class QueueCommandTests: WolfWaveTestCase {

    // MARK: - Helpers

    private func makeQueue(itemCount: Int) -> SongRequestQueue {
        let queue = SongRequestQueue()
        for i in 0..<itemCount {
            let item = SongRequestItem(
                title: "Song \(i + 1)",
                artist: "Artist \(i + 1)",
                requesterUsername: "user\(i + 1)"
            )
            _ = queue.add(item)
        }
        return queue
    }

    // MARK: - Metadata

    func testTriggers() {
        XCTAssertEqual(QueueCommand().triggers, ["!queue", "!songlist", "!requests"])
    }

    func testCooldowns() {
        let command = QueueCommand()
        XCTAssertEqual(command.globalCooldown, 10.0)
        XCTAssertEqual(command.userCooldown, 15.0)
    }

    func testEnabledKeyMatchesAppConstants() {
        XCTAssertEqual(
            QueueCommand().enabledKey,
            AppConstants.UserDefaults.queueCommandEnabled
        )
    }

    // MARK: - Replies

    func testEmptyQueueReply() {
        let command = QueueCommand()
        command.getQueue = { SongRequestQueue() }

        let reply = command.execute(message: "!queue")
        XCTAssertNotNil(reply)
        XCTAssertTrue(reply!.lowercased().contains("empty"))
        XCTAssertTrue(reply!.contains("!sr"))
    }

    func testMissingQueueReturnsNil() {
        let command = QueueCommand()
        command.getQueue = { nil }
        XCTAssertNil(command.execute(message: "!queue"))
    }

    func testSmallQueueListsAllItems() {
        let command = QueueCommand()
        command.getQueue = { self.makeQueue(itemCount: 3) }

        let reply = command.execute(message: "!queue") ?? ""
        XCTAssertTrue(reply.contains("Song 1"))
        XCTAssertTrue(reply.contains("Song 2"))
        XCTAssertTrue(reply.contains("Song 3"))
        XCTAssertFalse(reply.contains("more"))
    }

    func testLargeQueueCapsAtFiveAndAppendsMoreSuffix() {
        let command = QueueCommand()
        command.getQueue = { self.makeQueue(itemCount: 8) }

        let reply = command.execute(message: "!queue") ?? ""
        XCTAssertTrue(reply.contains("Song 1"))
        XCTAssertTrue(reply.contains("Song 5"))
        XCTAssertFalse(reply.contains("Song 6"))
        XCTAssertTrue(reply.contains("...and 3 more"))
    }
}
