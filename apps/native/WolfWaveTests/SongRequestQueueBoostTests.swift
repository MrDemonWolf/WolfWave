//
//  SongRequestQueueBoostTests.swift
//  WolfWaveTests
//
//  Created by MrDemonWolf, Inc. on 5/22/26.
//

import XCTest

@testable import WolfWave

@MainActor
final class SongRequestQueueBoostTests: XCTestCase {

    var queue: SongRequestQueue!

    override func setUp() {
        super.setUp()
        // Generous limits so multi-item-by-same-user tests aren't blocked.
        UserDefaults.standard.set(50, forKey: AppConstants.UserDefaults.songRequestMaxQueueSize)
        UserDefaults.standard.set(10, forKey: AppConstants.UserDefaults.songRequestPerUserLimit)
        queue = SongRequestQueue()
    }

    override func tearDown() {
        queue = nil
        UserDefaults.standard.removeObject(forKey: AppConstants.UserDefaults.songRequestMaxQueueSize)
        UserDefaults.standard.removeObject(forKey: AppConstants.UserDefaults.songRequestPerUserLimit)
        super.tearDown()
    }

    func testBoostReturnsNilWhenUserHasNothingQueued() {
        queue.add(SongRequestItem(title: "Other", artist: "X", requesterUsername: "other"))
        XCTAssertNil(queue.boost(username: "viewer"))
        // Queue unchanged.
        XCTAssertEqual(queue.items.first?.title, "Other")
    }

    func testBoostMovesUsersItemToFront() {
        queue.add(SongRequestItem(title: "A", artist: "X", requesterUsername: "first"))
        queue.add(SongRequestItem(title: "B", artist: "X", requesterUsername: "second"))
        queue.add(SongRequestItem(title: "C", artist: "X", requesterUsername: "viewer"))

        let boosted = queue.boost(username: "viewer")

        XCTAssertEqual(boosted?.title, "C")
        XCTAssertEqual(queue.items.map(\.title), ["C", "A", "B"])
    }

    func testBoostPicksMostRecentItemForUserWithMultiple() {
        queue.add(SongRequestItem(title: "A", artist: "X", requesterUsername: "viewer"))
        queue.add(SongRequestItem(title: "Other", artist: "X", requesterUsername: "other"))
        queue.add(SongRequestItem(title: "B", artist: "X", requesterUsername: "viewer"))

        let boosted = queue.boost(username: "viewer")

        XCTAssertEqual(boosted?.title, "B", "Boost should pick the user's most-recent item")
        XCTAssertEqual(queue.items.map(\.title), ["B", "A", "Other"])
    }

    func testBoostIsCaseInsensitive() {
        queue.add(SongRequestItem(title: "First", artist: "X", requesterUsername: "OtherUser"))
        queue.add(SongRequestItem(title: "Mine", artist: "X", requesterUsername: "Viewer"))

        let boosted = queue.boost(username: "viewer")

        XCTAssertEqual(boosted?.title, "Mine")
        XCTAssertEqual(queue.items.first?.title, "Mine")
    }
}
