//
//  SongBlocklistTests.swift
//  WolfWaveTests
//
//  Created by MrDemonWolf, Inc. on 5/23/26.
//

import XCTest
@testable import WolfWave

@MainActor
final class SongBlocklistTests: XCTestCase {

    // MARK: - Empty Start

    func testNewListIsEmpty() {
        let storage = InMemoryBlocklistStorage()
        let list = SongBlocklist(storage: storage)
        XCTAssertTrue(list.allEntries.isEmpty)
    }

    func testIsBlockedReturnsFalseOnEmptyList() {
        let list = SongBlocklist(storage: InMemoryBlocklistStorage())
        XCTAssertFalse(list.isBlocked(title: "Anything", artist: "Anyone"))
    }

    // MARK: - Add

    func testAddSongMakesItBlocked() {
        let list = SongBlocklist(storage: InMemoryBlocklistStorage())
        list.add(BlocklistItem(value: "Anti-Hero", type: .song))
        XCTAssertTrue(list.isBlocked(title: "Anti-Hero", artist: "Taylor Swift"))
        XCTAssertFalse(list.isBlocked(title: "Bad Blood", artist: "Taylor Swift"))
    }

    func testAddArtistBlocksAllSongsByThatArtist() {
        let list = SongBlocklist(storage: InMemoryBlocklistStorage())
        list.add(BlocklistItem(value: "Drake", type: .artist))
        XCTAssertTrue(list.isBlocked(title: "One Dance", artist: "Drake"))
        XCTAssertTrue(list.isBlocked(title: "God's Plan", artist: "Drake"))
        XCTAssertFalse(list.isBlocked(title: "One Dance", artist: "Calvin Harris"))
    }

    func testAddIsCaseInsensitive() {
        let list = SongBlocklist(storage: InMemoryBlocklistStorage())
        list.add(BlocklistItem(value: "ANTI-HERO", type: .song))
        XCTAssertTrue(list.isBlocked(title: "anti-hero", artist: ""))
        XCTAssertTrue(list.isBlocked(title: "Anti-Hero", artist: ""))
    }

    func testAddSameItemTwiceDoesNotDuplicate() {
        let list = SongBlocklist(storage: InMemoryBlocklistStorage())
        list.add(BlocklistItem(value: "Drake", type: .artist))
        list.add(BlocklistItem(value: "drake", type: .artist))
        XCTAssertEqual(list.allEntries.count, 1)
    }

    func testSongAndArtistOfSameNameCoexist() {
        let list = SongBlocklist(storage: InMemoryBlocklistStorage())
        list.add(BlocklistItem(value: "Madonna", type: .song))
        list.add(BlocklistItem(value: "Madonna", type: .artist))
        XCTAssertEqual(list.allEntries.count, 2)
    }

    // MARK: - Remove

    func testRemoveByIDDropsEntry() {
        let list = SongBlocklist(storage: InMemoryBlocklistStorage())
        let item = BlocklistItem(value: "Drake", type: .artist)
        list.add(item)
        list.remove(id: item.id)
        XCTAssertTrue(list.allEntries.isEmpty)
        XCTAssertFalse(list.isBlocked(title: "any", artist: "Drake"))
    }

    func testRemoveUnknownIDIsNoOp() {
        let list = SongBlocklist(storage: InMemoryBlocklistStorage())
        list.add(BlocklistItem(value: "Drake", type: .artist))
        list.remove(id: UUID())
        XCTAssertEqual(list.allEntries.count, 1)
    }

    func testClearAllEmptiesTheList() {
        let list = SongBlocklist(storage: InMemoryBlocklistStorage())
        list.add(BlocklistItem(value: "Drake", type: .artist))
        list.add(BlocklistItem(value: "Anti-Hero", type: .song))
        list.clearAll()
        XCTAssertTrue(list.allEntries.isEmpty)
    }

    // MARK: - Persistence

    func testEntriesSurviveReload() {
        let storage = InMemoryBlocklistStorage()
        let first = SongBlocklist(storage: storage)
        first.add(BlocklistItem(value: "Drake", type: .artist))
        first.add(BlocklistItem(value: "Anti-Hero", type: .song))

        let second = SongBlocklist(storage: storage)
        XCTAssertEqual(second.allEntries.count, 2)
        XCTAssertTrue(second.isBlocked(title: "anything", artist: "Drake"))
        XCTAssertTrue(second.isBlocked(title: "anti-hero", artist: "anyone"))
    }

    func testCorruptStorageProducesEmptyList() {
        let storage = InMemoryBlocklistStorage(initialData: Data("not-json".utf8))
        let list = SongBlocklist(storage: storage)
        XCTAssertTrue(list.allEntries.isEmpty)
    }

    func testRemoveIsPersisted() {
        let storage = InMemoryBlocklistStorage()
        let first = SongBlocklist(storage: storage)
        let item = BlocklistItem(value: "Drake", type: .artist)
        first.add(item)
        first.remove(id: item.id)

        let second = SongBlocklist(storage: storage)
        XCTAssertTrue(second.allEntries.isEmpty)
    }

    // MARK: - In-Memory Storage Behavior

    func testInMemoryStorageInitialDataIsReturned() {
        let payload = Data("seed".utf8)
        let storage = InMemoryBlocklistStorage(initialData: payload)
        XCTAssertEqual(storage.read(), payload)
    }

    func testInMemoryStorageWriteReplacesPayload() {
        let storage = InMemoryBlocklistStorage()
        storage.write(Data("first".utf8))
        storage.write(Data("second".utf8))
        XCTAssertEqual(storage.read(), Data("second".utf8))
    }
}
