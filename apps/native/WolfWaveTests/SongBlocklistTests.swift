//
//  SongBlocklistTests.swift
//  WolfWave
//
//  Created by Nathanial Henniges on 2026-05-23.
//  Copyright © 2026 MrDemonWolf, Inc. All rights reserved.
//

import XCTest
@testable import WolfWave

@MainActor
final class SongBlocklistTests: XCTestCase {

    // MARK: - Empty Start

    func testNewListIsEmpty() async {
        let storage = InMemoryBlocklistStorage()
        let list = SongBlocklist(storage: storage)
        let entries = await list.allEntries
        XCTAssertTrue(entries.isEmpty)
    }

    func testIsBlockedReturnsFalseOnEmptyList() async {
        let list = SongBlocklist(storage: InMemoryBlocklistStorage())
        let blocked = await list.isBlocked(title: "Anything", artist: "Anyone")
        XCTAssertFalse(blocked)
    }

    // MARK: - Add

    func testAddSongMakesItBlocked() async {
        let list = SongBlocklist(storage: InMemoryBlocklistStorage())
        await list.add(BlocklistItem(value: "Anti-Hero", type: .song))
        let blockedAnti = await list.isBlocked(title: "Anti-Hero", artist: "Taylor Swift")
        let blockedOther = await list.isBlocked(title: "Bad Blood", artist: "Taylor Swift")
        XCTAssertTrue(blockedAnti)
        XCTAssertFalse(blockedOther)
    }

    func testAddArtistBlocksAllSongsByThatArtist() async {
        let list = SongBlocklist(storage: InMemoryBlocklistStorage())
        await list.add(BlocklistItem(value: "Drake", type: .artist))
        let blockedDrake1 = await list.isBlocked(title: "One Dance", artist: "Drake")
        let blockedDrake2 = await list.isBlocked(title: "God's Plan", artist: "Drake")
        let notBlocked = await list.isBlocked(title: "One Dance", artist: "Calvin Harris")
        XCTAssertTrue(blockedDrake1)
        XCTAssertTrue(blockedDrake2)
        XCTAssertFalse(notBlocked)
    }

    func testAddIsCaseInsensitive() async {
        let list = SongBlocklist(storage: InMemoryBlocklistStorage())
        await list.add(BlocklistItem(value: "ANTI-HERO", type: .song))
        let lower = await list.isBlocked(title: "anti-hero", artist: "")
        let mixed = await list.isBlocked(title: "Anti-Hero", artist: "")
        XCTAssertTrue(lower)
        XCTAssertTrue(mixed)
    }

    func testAddSameItemTwiceDoesNotDuplicate() async {
        let list = SongBlocklist(storage: InMemoryBlocklistStorage())
        await list.add(BlocklistItem(value: "Drake", type: .artist))
        await list.add(BlocklistItem(value: "drake", type: .artist))
        let count = await list.allEntries.count
        XCTAssertEqual(count, 1)
    }

    func testSongAndArtistOfSameNameCoexist() async {
        let list = SongBlocklist(storage: InMemoryBlocklistStorage())
        await list.add(BlocklistItem(value: "Madonna", type: .song))
        await list.add(BlocklistItem(value: "Madonna", type: .artist))
        let count = await list.allEntries.count
        XCTAssertEqual(count, 2)
    }

    // MARK: - Remove

    func testRemoveByIDDropsEntry() async {
        let list = SongBlocklist(storage: InMemoryBlocklistStorage())
        let item = BlocklistItem(value: "Drake", type: .artist)
        await list.add(item)
        await list.remove(id: item.id)
        let entries = await list.allEntries
        let blocked = await list.isBlocked(title: "any", artist: "Drake")
        XCTAssertTrue(entries.isEmpty)
        XCTAssertFalse(blocked)
    }

    func testRemoveUnknownIDIsNoOp() async {
        let list = SongBlocklist(storage: InMemoryBlocklistStorage())
        await list.add(BlocklistItem(value: "Drake", type: .artist))
        await list.remove(id: UUID())
        let count = await list.allEntries.count
        XCTAssertEqual(count, 1)
    }

    func testClearAllEmptiesTheList() async {
        let list = SongBlocklist(storage: InMemoryBlocklistStorage())
        await list.add(BlocklistItem(value: "Drake", type: .artist))
        await list.add(BlocklistItem(value: "Anti-Hero", type: .song))
        await list.clearAll()
        let entries = await list.allEntries
        XCTAssertTrue(entries.isEmpty)
    }

    func testFactoryResetDrainsQueuedMutationAndRejectsLaterWrites() async throws {
        let storage = SuspendingFirstWriteBlocklistStorage()
        let list = SongBlocklist(storage: storage)
        let addTask = Task {
            await list.add(BlocklistItem(value: "Queued Artist", type: .artist))
        }
        let firstWriteStarted = await waitForSemaphore(
            storage.firstWriteStarted,
            timeout: .now() + 1
        )
        XCTAssertTrue(firstWriteStarted)

        let resetCallStarted = DispatchSemaphore(value: 0)
        let resetFinished = ThreadSafeBox(false)
        let resetTask = Task.detached {
            resetCallStarted.signal()
            await list.prepareForFactoryReset()
            resetFinished.value = true
        }
        let resetStarted = await waitForSemaphore(
            resetCallStarted,
            timeout: .now() + 1
        )
        XCTAssertTrue(resetStarted)
        await Task.yield()
        XCTAssertFalse(resetFinished.value)

        storage.releaseFirstWrite()
        _ = await addTask.value
        _ = await resetTask.value

        let clearedData = try XCTUnwrap(storage.read())
        let cleared = try JSONCoders.camelCase.decode([BlocklistItem].self, from: clearedData)
        XCTAssertTrue(cleared.isEmpty)

        let later = BlocklistItem(value: "Later Song", type: .song)
        await list.add(later)
        let laterData = try XCTUnwrap(storage.read())
        let persisted = try JSONCoders.camelCase.decode([BlocklistItem].self, from: laterData)
        XCTAssertTrue(persisted.isEmpty)
        let liveEntries = await list.allEntries
        XCTAssertTrue(liveEntries.isEmpty)
    }

    // MARK: - Persistence

    func testEntriesSurviveReload() async {
        let storage = InMemoryBlocklistStorage()
        let first = SongBlocklist(storage: storage)
        await first.add(BlocklistItem(value: "Drake", type: .artist))
        await first.add(BlocklistItem(value: "Anti-Hero", type: .song))

        let second = SongBlocklist(storage: storage)
        let count = await second.allEntries.count
        let blockedDrake = await second.isBlocked(title: "anything", artist: "Drake")
        let blockedSong = await second.isBlocked(title: "anti-hero", artist: "anyone")
        XCTAssertEqual(count, 2)
        XCTAssertTrue(blockedDrake)
        XCTAssertTrue(blockedSong)
    }

    func testCorruptStorageProducesEmptyList() async {
        let storage = InMemoryBlocklistStorage(initialData: Data("not-json".utf8))
        let list = SongBlocklist(storage: storage)
        let entries = await list.allEntries
        XCTAssertTrue(entries.isEmpty)
    }

    func testRemoveIsPersisted() async {
        let storage = InMemoryBlocklistStorage()
        let first = SongBlocklist(storage: storage)
        let item = BlocklistItem(value: "Drake", type: .artist)
        await first.add(item)
        await first.remove(id: item.id)

        let second = SongBlocklist(storage: storage)
        let entries = await second.allEntries
        XCTAssertTrue(entries.isEmpty)
    }

    func testUserDefaultsStorageUsesCentralizedResetAndBackupKey() throws {
        let suiteName = "SongBlocklistTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let payload = Data("seed".utf8)
        let storage = UserDefaultsBlocklistStorage(defaults: defaults)

        storage.write(payload)

        XCTAssertEqual(
            defaults.data(forKey: AppConstants.UserDefaults.songRequestBlocklist),
            payload
        )
        XCTAssertTrue(
            AppConstants.UserDefaults.allKeys.contains(
                AppConstants.UserDefaults.songRequestBlocklist)
        )
        XCTAssertTrue(
            AppConstants.UserDefaults.exportableKeys.contains(
                AppConstants.UserDefaults.songRequestBlocklist)
        )
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

private final class SuspendingFirstWriteBlocklistStorage: BlocklistStorage, @unchecked Sendable {
    let firstWriteStarted = DispatchSemaphore(value: 0)

    private let lock = NSLock()
    private let firstWriteRelease = DispatchSemaphore(value: 0)
    private var data: Data?
    private var writeCount = 0

    func read() -> Data? { lock.withLock { data } }

    func write(_ newData: Data) {
        let shouldSuspend = lock.withLock {
            writeCount += 1
            return writeCount == 1
        }
        if shouldSuspend {
            firstWriteStarted.signal()
            firstWriteRelease.wait()
        }
        lock.withLock { data = newData }
    }

    func releaseFirstWrite() { firstWriteRelease.signal() }
}
