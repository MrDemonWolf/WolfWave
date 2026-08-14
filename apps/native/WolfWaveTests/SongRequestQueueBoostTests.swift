//
//  SongRequestQueueBoostTests.swift
//  WolfWave
//
//  Created by Nathanial Henniges on 2026-05-22.
//  Copyright © 2026 MrDemonWolf, Inc. All rights reserved.
//

import XCTest

@testable import WolfWave

@MainActor
final class SongRequestQueueBoostTests: WolfWaveTestCase {

    var queue: SongRequestQueue!

    override func setUp() async throws {
        try await super.setUp()
        // Generous limits so multi-item-by-same-user tests aren't blocked.
        DefaultsStore.store.set(50, forKey: AppConstants.UserDefaults.songRequestMaxQueueSize)
        DefaultsStore.store.set(10, forKey: AppConstants.UserDefaults.songRequestPerUserLimit)
        queue = SongRequestQueue()
    }

    override func tearDown() async throws {
        queue = nil
        resetAllSettings()
        try await super.tearDown()
    }

    func testBoostReturnsNilWhenUserHasNothingQueued() {
        _ = queue.add(makeTestRequestItem(title: "Other", artist: "X", requesterUsername: "other"))
        XCTAssertNil(queue.boost(username: "viewer"))
        // Queue unchanged.
        XCTAssertEqual(queue.items.first?.title, "Other")
    }

    func testBoostMovesUsersItemToFront() {
        _ = queue.add(makeTestRequestItem(title: "A", artist: "X", requesterUsername: "first"))
        _ = queue.add(makeTestRequestItem(title: "B", artist: "X", requesterUsername: "second"))
        _ = queue.add(makeTestRequestItem(title: "C", artist: "X", requesterUsername: "viewer"))

        let boosted = queue.boost(username: "viewer")

        XCTAssertEqual(boosted?.title, "C")
        XCTAssertEqual(queue.items.map(\.title), ["C", "A", "B"])
    }

    func testBoostPicksEarliestItemForUserWithMultiple() {
        _ = queue.add(makeTestRequestItem(title: "Other", artist: "X", requesterUsername: "other"))
        _ = queue.add(makeTestRequestItem(title: "A", artist: "X", requesterUsername: "viewer"))
        _ = queue.add(makeTestRequestItem(title: "B", artist: "X", requesterUsername: "viewer"))

        let boosted = queue.boost(username: "viewer")

        XCTAssertEqual(boosted?.title, "A", "Boost should pick the user's earliest (longest-waiting) item")
        XCTAssertEqual(queue.items.map(\.title), ["A", "Other", "B"])
    }

    func testBoostIsCaseInsensitive() {
        _ = queue.add(makeTestRequestItem(title: "First", artist: "X", requesterUsername: "OtherUser"))
        _ = queue.add(makeTestRequestItem(title: "Mine", artist: "X", requesterUsername: "Viewer"))

        let boosted = queue.boost(username: "viewer")

        XCTAssertEqual(boosted?.title, "Mine")
        XCTAssertEqual(queue.items.first?.title, "Mine")
    }
}
