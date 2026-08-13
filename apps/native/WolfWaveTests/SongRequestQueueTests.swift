//
//  SongRequestQueueTests.swift
//  WolfWave
//
//  Created by Nathanial Henniges on 2026-04-15.
//  Copyright © 2026 MrDemonWolf, Inc. All rights reserved.
//

import MusicKit
import XCTest

@testable import WolfWave

@MainActor
final class SongRequestQueueTests: WolfWaveTestCase {
    var queue: SongRequestQueue!

    override func setUp() {
        super.setUp()
        queue = SongRequestQueue()
        // Reset UserDefaults for test isolation
        resetAllSettings()
    }

    override func tearDown() {
        queue = nil
        resetAllSettings()
        super.tearDown()
    }

    // MARK: - Basic Operations

    func testQueueStartsEmpty() {
        XCTAssertTrue(queue.isEmpty)
        XCTAssertEqual(queue.count, 0)
        XCTAssertFalse(queue.isFull)
        XCTAssertNil(queue.nowPlaying)
    }

    func testDequeueEmptyReturnsNil() {
        XCTAssertNil(queue.dequeue())
    }

    func testClearEmptyQueue() {
        let count = queue.clear()
        XCTAssertEqual(count, 0)
    }

    // MARK: - User Position Lookup

    func testPositionsForUnknownUser() {
        let positions = queue.positions(for: "unknownuser")
        XCTAssertTrue(positions.isEmpty)
    }

    // MARK: - Default Limits

    func testDefaultMaxQueueSize() {
        XCTAssertEqual(queue.maxQueueSize, 10)
    }

    func testDefaultPerUserLimit() {
        XCTAssertEqual(queue.perUserLimit, 2)
    }

    // MARK: - Custom Limits via UserDefaults

    func testCustomMaxQueueSize() {
        UserDefaults.standard.set(5, forKey: AppConstants.UserDefaults.songRequestMaxQueueSize)
        XCTAssertEqual(queue.maxQueueSize, 5)
    }

    func testCustomPerUserLimit() {
        UserDefaults.standard.set(3, forKey: AppConstants.UserDefaults.songRequestPerUserLimit)
        XCTAssertEqual(queue.perUserLimit, 3)
    }

    // MARK: - Clear Now Playing

    func testClearNowPlaying() {
        queue.clearNowPlaying()
        XCTAssertNil(queue.nowPlaying)
    }

    // MARK: - Move Operations

    func testMoveWithEmptyQueue() {
        // Should not crash
        queue.move(from: IndexSet(), to: 0)
        XCTAssertTrue(queue.isEmpty)
    }

    // MARK: - Remove by ID

    func testRemoveByNonExistentID() {
        let fakeID = UUID()
        queue.remove(id: fakeID)
        XCTAssertTrue(queue.isEmpty)
    }

    // MARK: - Add Operations

    func testAddSingleItem() {
        let item = makeTestRequestItem(title: "Bohemian Rhapsody", artist: "Queen", requesterUsername: "user1")
        let result = queue.add(item)
        guard case .added(let position) = result else {
            XCTFail("Expected .added, got \(result)")
            return
        }
        XCTAssertEqual(position, 1)
        XCTAssertEqual(queue.count, 1)
        XCTAssertFalse(queue.isEmpty)
    }

    func testAddMultipleItemsIncrementsPosition() {
        let item1 = makeTestRequestItem(title: "Song A", artist: "Artist A", requesterUsername: "user1")
        let item2 = makeTestRequestItem(title: "Song B", artist: "Artist B", requesterUsername: "user2")
        let r1 = queue.add(item1)
        let r2 = queue.add(item2)
        guard case .added(let pos1) = r1, case .added(let pos2) = r2 else {
            XCTFail("Expected both .added")
            return
        }
        XCTAssertEqual(pos1, 1)
        XCTAssertEqual(pos2, 2)
        XCTAssertEqual(queue.count, 2)
    }

    func testAddQueueFull() {
        UserDefaults.standard.set(2, forKey: AppConstants.UserDefaults.songRequestMaxQueueSize)
        UserDefaults.standard.set(5, forKey: AppConstants.UserDefaults.songRequestPerUserLimit)
        queue.add(makeTestRequestItem(title: "Song 1", artist: "A", requesterUsername: "user1"))
        queue.add(makeTestRequestItem(title: "Song 2", artist: "B", requesterUsername: "user2"))
        let result = queue.add(makeTestRequestItem(title: "Song 3", artist: "C", requesterUsername: "user3"))
        guard case .queueFull(let max) = result else {
            XCTFail("Expected .queueFull, got \(result)")
            return
        }
        XCTAssertEqual(max, 2)
    }

    func testAddUserLimitReached() {
        UserDefaults.standard.set(1, forKey: AppConstants.UserDefaults.songRequestPerUserLimit)
        queue.add(makeTestRequestItem(title: "Song 1", artist: "A", requesterUsername: "user1"))
        let result = queue.add(makeTestRequestItem(title: "Song 2", artist: "B", requesterUsername: "user1"))
        guard case .userLimitReached(let max) = result else {
            XCTFail("Expected .userLimitReached, got \(result)")
            return
        }
        XCTAssertEqual(max, 1)
    }

    func testAddDuplicateRejected() {
        let item1 = makeTestRequestItem(title: "Duplicate Song", artist: "Same Artist", requesterUsername: "user1")
        let item2 = makeTestRequestItem(title: "duplicate song", artist: "SAME ARTIST", requesterUsername: "USER1")
        queue.add(item1)
        let result = queue.add(item2)
        guard case .alreadyInQueue = result else {
            XCTFail("Expected .alreadyInQueue, got \(result)")
            return
        }
        XCTAssertEqual(queue.count, 1)
    }

    func testAddDifferentUserSameSongAllowed() {
        let item1 = makeTestRequestItem(title: "Same Song", artist: "Artist", requesterUsername: "user1")
        let item2 = makeTestRequestItem(title: "Same Song", artist: "Artist", requesterUsername: "user2")
        let r1 = queue.add(item1)
        let r2 = queue.add(item2)
        guard case .added = r1, case .added = r2 else {
            XCTFail("Expected both .added")
            return
        }
        XCTAssertEqual(queue.count, 2)
    }

    func testAddDuplicateOfNowPlayingRejected() {
        // High per-user limit so the duplicate check, not the user limit, decides.
        UserDefaults.standard.set(5, forKey: AppConstants.UserDefaults.songRequestPerUserLimit)
        queue.add(makeTestRequestItem(title: "Now Playing Song", artist: "Artist", requesterUsername: "user1"))
        queue.dequeue() // moves the request into the now-playing slot
        let result = queue.add(
            makeTestRequestItem(title: "NOW PLAYING SONG", artist: "artist", requesterUsername: "USER1"))
        guard case .alreadyInQueue = result else {
            XCTFail("Expected .alreadyInQueue, got \(result)")
            return
        }
        XCTAssertEqual(queue.count, 0)
    }

    func testAddNowPlayingSongByDifferentUserAllowed() {
        queue.add(makeTestRequestItem(title: "Now Playing Song", artist: "Artist", requesterUsername: "user1"))
        queue.dequeue()
        let result = queue.add(
            makeTestRequestItem(title: "Now Playing Song", artist: "Artist", requesterUsername: "user2"))
        guard case .added = result else {
            XCTFail("Expected .added, got \(result)")
            return
        }
        XCTAssertEqual(queue.count, 1)
    }

    // MARK: - Dequeue / Clear with Items

    func testDequeueSetsNowPlaying() {
        let item = makeTestRequestItem(title: "Test Song", artist: "Test Artist", requesterUsername: "user1")
        queue.add(item)
        let dequeued = queue.dequeue()
        XCTAssertNotNil(dequeued)
        XCTAssertEqual(dequeued?.title, "Test Song")
        XCTAssertEqual(queue.nowPlaying?.title, "Test Song")
        XCTAssertTrue(queue.isEmpty)
    }

    func testClearReturnsItemCount() {
        queue.add(makeTestRequestItem(title: "Song 1", artist: "A", requesterUsername: "user1"))
        queue.add(makeTestRequestItem(title: "Song 2", artist: "B", requesterUsername: "user2"))
        let removed = queue.clear()
        XCTAssertEqual(removed, 2)
        XCTAssertTrue(queue.isEmpty)
        XCTAssertNil(queue.nowPlaying)
    }

    func testClearAlsoClearsNowPlaying() {
        let item = makeTestRequestItem(title: "Test", artist: "A", requesterUsername: "user1")
        queue.add(item)
        queue.dequeue() // sets nowPlaying
        XCTAssertNotNil(queue.nowPlaying)
        queue.clear()
        XCTAssertNil(queue.nowPlaying)
    }

    // MARK: - Remove by ID

    func testRemoveExistingItem() {
        let item = makeTestRequestItem(title: "Remove Me", artist: "Artist", requesterUsername: "user1")
        queue.add(item)
        XCTAssertEqual(queue.count, 1)
        queue.remove(id: item.id)
        XCTAssertEqual(queue.count, 0)
        XCTAssertTrue(queue.isEmpty)
    }

    // MARK: - Move

    func testMoveReordersItems() {
        queue.add(makeTestRequestItem(title: "Song A", artist: "A", requesterUsername: "user1"))
        queue.add(makeTestRequestItem(title: "Song B", artist: "B", requesterUsername: "user2"))
        queue.add(makeTestRequestItem(title: "Song C", artist: "C", requesterUsername: "user3"))
        // Move Song C (index 2) to position 0
        queue.move(from: IndexSet(integer: 2), to: 0)
        XCTAssertEqual(queue.items[0].title, "Song C")
        XCTAssertEqual(queue.items[1].title, "Song A")
    }

    // MARK: - Positions

    func testPositionsForUser() {
        let user = "testuser"
        queue.add(makeTestRequestItem(title: "Song 1", artist: "A", requesterUsername: user))
        queue.add(makeTestRequestItem(title: "Song X", artist: "B", requesterUsername: "other"))
        queue.add(makeTestRequestItem(title: "Song 2", artist: "C", requesterUsername: user))
        let positions = queue.positions(for: user)
        XCTAssertEqual(positions.count, 2)
        XCTAssertEqual(positions[0].position, 1)
        XCTAssertEqual(positions[0].item.title, "Song 1")
        XCTAssertEqual(positions[1].position, 3)
        XCTAssertEqual(positions[1].item.title, "Song 2")
    }

    func testIsFull() {
        UserDefaults.standard.set(2, forKey: AppConstants.UserDefaults.songRequestMaxQueueSize)
        UserDefaults.standard.set(5, forKey: AppConstants.UserDefaults.songRequestPerUserLimit)
        XCTAssertFalse(queue.isFull)
        queue.add(makeTestRequestItem(title: "Song 1", artist: "A", requesterUsername: "user1"))
        queue.add(makeTestRequestItem(title: "Song 2", artist: "B", requesterUsername: "user2"))
        XCTAssertTrue(queue.isFull)
    }

    // MARK: - Upcoming (overlay queue ticker, WW-42)

    func testUpcomingReturnsEmptyArrayWhenQueueEmpty() {
        XCTAssertTrue(queue.upcoming().isEmpty)
    }

    func testUpcomingCapsAtLimit() {
        for i in 1...5 {
            queue.add(makeTestRequestItem(title: "Song \(i)", artist: "A", requesterUsername: "user\(i)"))
        }
        let upcoming = queue.upcoming(limit: 3)
        XCTAssertEqual(upcoming.count, 3)
        XCTAssertEqual(upcoming.map(\.title), Array(queue.items.prefix(3)).map(\.title))
    }

    func testUpcomingDefaultLimitIsThree() {
        for i in 1...5 {
            queue.add(makeTestRequestItem(title: "Song \(i)", artist: "A", requesterUsername: "user\(i)"))
        }
        XCTAssertEqual(queue.upcoming().count, AppConstants.WebSocketServer.queueTickerMaxItems)
    }

    /// `upcoming()` must reflect fair-share (round-robin) order, not raw
    /// insertion order - it's a prefix read of `items`, which is already
    /// reordered at insert time.
    func testUpcomingReflectsFairShareOrder() {
        UserDefaults.standard.set(true, forKey: AppConstants.UserDefaults.songRequestFairShare)
        queue.add(makeTestRequestItem(title: "A1", artist: "x", requesterUsername: "user1"))
        queue.add(makeTestRequestItem(title: "A2", artist: "x", requesterUsername: "user1"))
        queue.add(makeTestRequestItem(title: "B1", artist: "x", requesterUsername: "user2"))
        XCTAssertEqual(queue.upcoming().map(\.title), ["A1", "B1", "A2"])
    }

    // MARK: - Fair-Share Ordering

    /// A newcomer's first request slots ahead of a regular's second, so
    /// everyone's Nth request plays before anyone's (N+1)th.
    func testFairShareInterleavesByRound() {
        UserDefaults.standard.set(true, forKey: AppConstants.UserDefaults.songRequestFairShare)
        queue.add(makeTestRequestItem(title: "A1", artist: "x", requesterUsername: "user1"))
        queue.add(makeTestRequestItem(title: "A2", artist: "x", requesterUsername: "user1"))
        queue.add(makeTestRequestItem(title: "B1", artist: "x", requesterUsername: "user2"))
        XCTAssertEqual(queue.items.map(\.title), ["A1", "B1", "A2"])
    }

    /// With fair-share off, ordering is classic FIFO (insertion order).
    func testFifoPreservesInsertionOrder() {
        UserDefaults.standard.set(false, forKey: AppConstants.UserDefaults.songRequestFairShare)
        queue.add(makeTestRequestItem(title: "A1", artist: "x", requesterUsername: "user1"))
        queue.add(makeTestRequestItem(title: "A2", artist: "x", requesterUsername: "user1"))
        queue.add(makeTestRequestItem(title: "B1", artist: "x", requesterUsername: "user2"))
        XCTAssertEqual(queue.items.map(\.title), ["A1", "A2", "B1"])
    }

    /// FIFO order holds within a single round (two users, one request each).
    func testFairShareKeepsFifoWithinRound() {
        UserDefaults.standard.set(true, forKey: AppConstants.UserDefaults.songRequestFairShare)
        queue.add(makeTestRequestItem(title: "A1", artist: "x", requesterUsername: "user1"))
        queue.add(makeTestRequestItem(title: "B1", artist: "x", requesterUsername: "user2"))
        XCTAssertEqual(queue.items.map(\.title), ["A1", "B1"])
    }

    // MARK: - Sub/VIP Priority (within fair-share rounds)

    /// A priority request slots ahead of same-round non-priority requests, but
    /// stays behind earlier rounds. Normal requests never jump a priority one.
    func testPriorityJumpsAheadWithinRound() {
        UserDefaults.standard.set(true, forKey: AppConstants.UserDefaults.songRequestFairShare)
        queue.add(makeTestRequestItem(title: "A1", artist: "x", requesterUsername: "user1"))
        queue.add(makeTestRequestItem(title: "A2", artist: "x", requesterUsername: "user1"))
        queue.add(makeTestRequestItem(title: "SubFirst", artist: "x", requesterUsername: "sub", isPriority: true))
        // Sub's first (round 0, priority) leads round 0; user1's second stays in round 1.
        XCTAssertEqual(queue.items.map(\.title), ["SubFirst", "A1", "A2"])
    }

    /// Priority requests keep FIFO among themselves and all lead the round ahead
    /// of a non-priority request.
    func testPriorityKeepsFifoAmongPriority() {
        UserDefaults.standard.set(true, forKey: AppConstants.UserDefaults.songRequestFairShare)
        queue.add(makeTestRequestItem(title: "Sub1", artist: "x", requesterUsername: "sub1", isPriority: true))
        queue.add(makeTestRequestItem(title: "Normal", artist: "x", requesterUsername: "reg"))
        queue.add(makeTestRequestItem(title: "Sub2", artist: "x", requesterUsername: "sub2", isPriority: true))
        XCTAssertEqual(queue.items.map(\.title), ["Sub1", "Sub2", "Normal"])
    }

    /// Priority is an in-round reorder, not a FIFO override: with fair-share off
    /// the queue stays classic first-in, first-out and ignores the flag.
    func testPriorityIgnoredWhenFifo() {
        UserDefaults.standard.set(false, forKey: AppConstants.UserDefaults.songRequestFairShare)
        queue.add(makeTestRequestItem(title: "Normal", artist: "x", requesterUsername: "reg"))
        queue.add(makeTestRequestItem(title: "Sub", artist: "x", requesterUsername: "sub", isPriority: true))
        XCTAssertEqual(queue.items.map(\.title), ["Normal", "Sub"])
    }
}
