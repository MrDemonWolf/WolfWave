//
//  TwitchRedemptionResolutionOutboxTests.swift
//  WolfWave
//
//  Created by Nathanial Henniges on 2026-08-11.
//  Copyright © 2026 MrDemonWolf, Inc. All rights reserved.
//

import Foundation
import XCTest

@testable import WolfWave

final class TwitchRedemptionResolutionOutboxTests: XCTestCase {
    func testIntakePersistsAndDeduplicatesAcrossRelaunchUntilOutcomeKnown() throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }

        let firstStore = TwitchRedemptionResolutionOutbox(fileURL: fixture.file)
        let first = try firstStore.enqueueIntake(
            broadcasterID: "broadcaster",
            rewardID: "reward",
            redemptionID: "redemption",
            now: Date(timeIntervalSince1970: 100)
        )
        XCTAssertTrue(first.inserted)
        XCTAssertTrue(first.item.isIntake)

        // Models relaunch before processing and relaunch after an in-memory
        // queue mutation but before its result was durably recorded. Both must
        // retain one unknown intake that startup can conservatively refund.
        let relaunched = TwitchRedemptionResolutionOutbox(fileURL: fixture.file)
        XCTAssertEqual(relaunched.pendingItems(), [first.item])
        let duplicate = try relaunched.enqueueIntake(
            broadcasterID: "broadcaster",
            rewardID: "reward",
            redemptionID: "redemption",
            now: Date(timeIntervalSince1970: 200)
        )
        XCTAssertFalse(duplicate.inserted)
        XCTAssertEqual(duplicate.item, first.item)

        let fulfilled = try relaunched.updateResolution(first.item.id, to: .fulfilled)
        XCTAssertEqual(fulfilled.resolution, .fulfilled)
        // Once known, duplicate delivery cannot reverse the queue outcome.
        let conflicting = try relaunched.updateResolution(first.item.id, to: .canceled)
        XCTAssertEqual(conflicting.resolution, .fulfilled)

        let knownRelaunch = TwitchRedemptionResolutionOutbox(fileURL: fixture.file)
        XCTAssertEqual(knownRelaunch.pendingItems(), [fulfilled])
    }

    func testFailedOutcomeWriteLeavesDurableIntakeForStartupRefund() throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        let failWrites = ThreadSafeBox(false)
        let store = TwitchRedemptionResolutionOutbox(
            fileURL: fixture.file,
            atomicWriter: { data, url in
                if failWrites.value { throw CocoaError(.fileWriteUnknown) }
                try data.write(to: url, options: .atomic)
            }
        )
        let intake = try store.enqueueIntake(
            broadcasterID: "broadcaster",
            rewardID: "reward",
            redemptionID: "redemption"
        ).item

        failWrites.value = true
        XCTAssertThrowsError(try store.updateResolution(intake.id, to: .fulfilled))
        XCTAssertTrue(store.intakeStorageIsUnavailable())
        XCTAssertEqual(store.pendingItems(), [intake])
        XCTAssertEqual(
            TwitchRedemptionResolutionOutbox(fileURL: fixture.file).pendingItems(),
            [intake]
        )

        failWrites.value = false
        let canceled = try store.updateResolution(intake.id, to: .canceled)
        XCTAssertTrue(store.intakeStorageIsUnavailable())
        XCTAssertNoThrow(try store.verifyIntakeStorage())
        XCTAssertFalse(store.intakeStorageIsUnavailable())
        XCTAssertEqual(canceled.resolution, .canceled)
        XCTAssertEqual(
            TwitchRedemptionResolutionOutbox(fileURL: fixture.file).pendingItems(),
            [canceled]
        )
    }

    func testStorageProbeUsesInjectedAtomicWriterAndCanRecover() throws {
        enum InjectedFailure: Error {
            case write
        }

        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        let failWrites = ThreadSafeBox(true)
        let writes = ThreadSafeBox(0)
        let store = TwitchRedemptionResolutionOutbox(
            fileURL: fixture.file,
            atomicWriter: { data, url in
                writes.mutate { $0 += 1 }
                if failWrites.value { throw InjectedFailure.write }
                try data.write(to: url, options: .atomic)
            }
        )

        XCTAssertThrowsError(try store.verifyIntakeStorage())
        XCTAssertEqual(writes.value, 1)
        XCTAssertTrue(store.intakeStorageIsUnavailable())
        XCTAssertTrue(store.pendingItems().isEmpty)

        failWrites.value = false
        XCTAssertNoThrow(try store.verifyIntakeStorage())
        XCTAssertEqual(writes.value, 2)
        XCTAssertFalse(store.intakeStorageIsUnavailable())
        XCTAssertTrue(FileManager.default.fileExists(atPath: fixture.file.path))
    }

    func testFailedAcknowledgementWriteTripsCircuitBreakerAndKeepsItem() throws {
        enum InjectedFailure: Error {
            case write
        }

        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        let failWrites = ThreadSafeBox(false)
        let store = TwitchRedemptionResolutionOutbox(
            fileURL: fixture.file,
            atomicWriter: { data, url in
                if failWrites.value { throw InjectedFailure.write }
                try data.write(to: url, options: .atomic)
            }
        )
        let item = try store.enqueue(
            broadcasterID: "broadcaster",
            rewardID: "reward",
            redemptionID: "redemption",
            resolution: .canceled)

        failWrites.value = true
        XCTAssertThrowsError(try store.remove(item.id))
        XCTAssertTrue(store.intakeStorageIsUnavailable())
        XCTAssertEqual(store.pendingItems(), [item])

        failWrites.value = false
        XCTAssertNoThrow(try store.verifyIntakeStorage())
        XCTAssertFalse(store.intakeStorageIsUnavailable())
    }

    func testPersistsDeduplicatesAndAcknowledgesAcrossInstances() throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }

        let firstStore = TwitchRedemptionResolutionOutbox(fileURL: fixture.file)
        let first = try firstStore.enqueue(
            broadcasterID: "broadcaster",
            rewardID: "reward",
            redemptionID: "redemption",
            resolution: .fulfilled,
            now: Date(timeIntervalSince1970: 100)
        )
        let duplicate = try firstStore.enqueue(
            broadcasterID: "broadcaster",
            rewardID: "reward",
            redemptionID: "redemption",
            resolution: .canceled,
            now: Date(timeIntervalSince1970: 200)
        )
        XCTAssertEqual(duplicate.id, first.id)
        XCTAssertEqual(duplicate.resolution, .fulfilled)

        let relaunched = TwitchRedemptionResolutionOutbox(fileURL: fixture.file)
        XCTAssertEqual(relaunched.pendingItems(), [first])
        try relaunched.remove(first.id)

        let drained = TwitchRedemptionResolutionOutbox(fileURL: fixture.file)
        XCTAssertTrue(drained.pendingItems().isEmpty)
    }

    func testCorruptStoreIsQuarantinedAndFreshQueueStillWorks() throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        try Data("not-json".utf8).write(to: fixture.file, options: .atomic)

        let store = TwitchRedemptionResolutionOutbox(fileURL: fixture.file)
        XCTAssertTrue(store.hasOpaqueRecoveryRisk())
        let item = try store.enqueue(
            broadcasterID: "broadcaster",
            rewardID: "reward",
            redemptionID: "new-redemption",
            resolution: .canceled
        )
        XCTAssertEqual(store.pendingItems(), [item])
        try store.remove(item.id)
        XCTAssertTrue(store.pendingItems().isEmpty)

        let names = try FileManager.default.contentsOfDirectory(
            atPath: fixture.directory.path)
        let quarantine = try XCTUnwrap(names.first {
            $0.hasPrefix(fixture.file.lastPathComponent + ".corrupt-")
        })
        let preserved = try Data(
            contentsOf: fixture.directory.appending(path: quarantine))
        XCTAssertEqual(preserved, Data("not-json".utf8))

        let relaunched = TwitchRedemptionResolutionOutbox(fileURL: fixture.file)
        XCTAssertTrue(relaunched.hasOpaqueRecoveryRisk())

        try relaunched.clearOpaqueRecoveryRiskAfterReconciliation()
        XCTAssertFalse(relaunched.hasOpaqueRecoveryRisk())
        let recovered = TwitchRedemptionResolutionOutbox(fileURL: fixture.file)
        XCTAssertFalse(recovered.hasOpaqueRecoveryRisk())
    }

    func testQuarantineFailureBlocksStorageProbeAndFutureIntake() throws {
        enum InjectedFailure: Error {
            case quarantine
        }

        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        let original = Data("not-json".utf8)
        try original.write(to: fixture.file, options: .atomic)
        let store = TwitchRedemptionResolutionOutbox(
            fileURL: fixture.file,
            quarantineMover: { _, _ in throw InjectedFailure.quarantine }
        )

        XCTAssertThrowsError(try store.verifyIntakeStorage()) { error in
            guard case TwitchRedemptionResolutionOutbox.StoreError.unreadableExistingStore = error
            else {
                return XCTFail("Unexpected error: \(error)")
            }
        }
        XCTAssertTrue(store.intakeStorageIsUnavailable())
        XCTAssertTrue(store.hasOpaqueRecoveryRisk())
        XCTAssertThrowsError(try store.enqueueIntake(
            broadcasterID: "broadcaster",
            rewardID: "reward",
            redemptionID: "redemption"
        ))
        XCTAssertTrue(store.pendingItems().isEmpty)
        XCTAssertEqual(try Data(contentsOf: fixture.file), original)
    }

    func testUnknownResolutionIsQuarantinedInsteadOfPoisoningReplay() throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        let unknown = TwitchRedemptionResolutionOutbox.Item(
            id: UUID(),
            broadcasterID: "broadcaster",
            rewardID: "reward",
            redemptionID: "old-redemption",
            resolutionRawValue: "UNKNOWN_FUTURE_VALUE",
            createdAt: Date()
        )
        try JSONEncoder().encode([unknown]).write(to: fixture.file, options: .atomic)

        let store = TwitchRedemptionResolutionOutbox(fileURL: fixture.file)
        XCTAssertTrue(store.pendingItems().isEmpty)
        _ = try store.enqueue(
            broadcasterID: "broadcaster",
            rewardID: "reward",
            redemptionID: "new-redemption",
            resolution: .fulfilled
        )
        XCTAssertEqual(store.pendingItems().count, 1)
    }

    func testMixedInvalidStoreRestoresValidItemsToLiveQueue() throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        let valid = TwitchRedemptionResolutionOutbox.Item(
            id: UUID(),
            broadcasterID: "broadcaster",
            rewardID: "reward",
            redemptionID: "valid-redemption",
            resolutionRawValue: TwitchChannelPointsService.Resolution.fulfilled.rawValue,
            createdAt: Date(timeIntervalSince1970: 1)
        )
        let invalid = TwitchRedemptionResolutionOutbox.Item(
            id: UUID(),
            broadcasterID: "",
            rewardID: "reward",
            redemptionID: "invalid-redemption",
            resolutionRawValue: "UNKNOWN",
            createdAt: Date(timeIntervalSince1970: 2)
        )
        try JSONEncoder().encode([valid, invalid]).write(
            to: fixture.file,
            options: .atomic
        )

        let store = TwitchRedemptionResolutionOutbox(fileURL: fixture.file)
        XCTAssertEqual(store.pendingItems(), [valid])
        XCTAssertTrue(store.hasOpaqueRecoveryRisk())
        let relaunched = TwitchRedemptionResolutionOutbox(fileURL: fixture.file)
        XCTAssertEqual(relaunched.pendingItems(), [valid])
        XCTAssertTrue(relaunched.hasOpaqueRecoveryRisk())

        let names = try FileManager.default.contentsOfDirectory(
            atPath: fixture.directory.path)
        XCTAssertTrue(names.contains {
            $0.hasPrefix(fixture.file.lastPathComponent + ".corrupt-")
        })
    }

    func testMixedInvalidStoreKeepsOriginalLiveWhenSalvageWriteFails() throws {
        enum InjectedFailure: Error {
            case write
        }

        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        let valid = TwitchRedemptionResolutionOutbox.Item(
            id: UUID(),
            broadcasterID: "broadcaster",
            rewardID: "reward",
            redemptionID: "valid-redemption",
            resolutionRawValue: TwitchChannelPointsService.Resolution.fulfilled.rawValue,
            createdAt: Date(timeIntervalSince1970: 1)
        )
        let invalid = TwitchRedemptionResolutionOutbox.Item(
            id: UUID(),
            broadcasterID: "",
            rewardID: "reward",
            redemptionID: "invalid-redemption",
            resolutionRawValue: "UNKNOWN",
            createdAt: Date(timeIntervalSince1970: 2)
        )
        let original = try JSONEncoder().encode([valid, invalid])
        try original.write(to: fixture.file, options: .atomic)

        let failedRecovery = TwitchRedemptionResolutionOutbox(
            fileURL: fixture.file,
            atomicWriter: { _, _ in throw InjectedFailure.write }
        )

        XCTAssertEqual(failedRecovery.pendingItems(), [valid])
        XCTAssertEqual(try Data(contentsOf: fixture.file), original)

        let relaunched = TwitchRedemptionResolutionOutbox(fileURL: fixture.file)
        XCTAssertEqual(relaunched.pendingItems(), [valid])
    }

    func testBitsIntakeReplaysAcrossRelaunchThenTerminalSuppressesExactOwner()
        throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        let now = Date(timeIntervalSince1970: 1_000)
        let clock = ThreadSafeBox(now)
        let store = TwitchRedemptionResolutionOutbox(
            fileURL: fixture.file,
            nowProvider: { clock.value })

        let first = try store.enqueueBits(
            messageID: "paid-message",
            broadcasterID: "broadcaster-a",
            userName: "viewer",
            bits: 100,
            boostEnabled: false,
            query: "a song")
        XCTAssertTrue(first.inserted)
        let firstItem = try XCTUnwrap(first.item)
        let duplicate = try store.enqueueBits(
            messageID: "paid-message",
            broadcasterID: "broadcaster-a",
            userName: "viewer",
            bits: 100,
            boostEnabled: false,
            query: "a song")
        XCTAssertFalse(duplicate.inserted)
        XCTAssertEqual(duplicate.item, firstItem)

        let relaunched = TwitchRedemptionResolutionOutbox(
            fileURL: fixture.file,
            nowProvider: { clock.value })
        XCTAssertEqual(relaunched.pendingBitsItems(), [firstItem])
        let replay = try relaunched.enqueueBits(
            messageID: "paid-message",
            broadcasterID: "broadcaster-a",
            userName: "viewer",
            bits: 100,
            boostEnabled: false,
            query: "a song")
        XCTAssertFalse(replay.inserted)
        XCTAssertEqual(replay.item, firstItem)

        try relaunched.acknowledgeBits(firstItem.id)
        let completed = TwitchRedemptionResolutionOutbox(
            fileURL: fixture.file,
            nowProvider: { clock.value })
        XCTAssertTrue(completed.pendingBitsItems().isEmpty)
        XCTAssertNil(
            try completed.enqueueBits(
                messageID: "paid-message",
                broadcasterID: "broadcaster-a",
                userName: "viewer",
                bits: 100,
                boostEnabled: false,
                query: "a song").item)
        XCTAssertNotNil(
            try completed.enqueueBits(
                messageID: "paid-message",
                broadcasterID: "broadcaster-b",
                userName: "viewer",
                bits: 100,
                boostEnabled: false,
                query: "a song").item)
    }

    func testFailedBitsEnqueuePublishesNeitherMemoryNorDiskItem() throws {
        enum InjectedFailure: Error {
            case write
        }

        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        let store = TwitchRedemptionResolutionOutbox(
            fileURL: fixture.file,
            atomicWriter: { _, _ in throw InjectedFailure.write })

        XCTAssertThrowsError(
            try store.enqueueBits(
                messageID: "paid-message",
                broadcasterID: "broadcaster",
                userName: "viewer",
                bits: 100,
                boostEnabled: false,
                query: "a song"))
        XCTAssertTrue(store.pendingBitsItems().isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.file.path))
        XCTAssertTrue(
            TwitchRedemptionResolutionOutbox(fileURL: fixture.file)
                .pendingBitsItems().isEmpty)
    }

    func testFailedBitsAcknowledgementKeepsReplayableItemAndNoTombstone()
        throws {
        enum InjectedFailure: Error {
            case write
        }

        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        let failWrites = ThreadSafeBox(false)
        let store = TwitchRedemptionResolutionOutbox(
            fileURL: fixture.file,
            atomicWriter: { data, url in
                if failWrites.value { throw InjectedFailure.write }
                try data.write(to: url, options: .atomic)
            })
        let item = try XCTUnwrap(
            store.enqueueBits(
                messageID: "paid-message",
                broadcasterID: "broadcaster",
                userName: "viewer",
                bits: 100,
                boostEnabled: false,
                query: "a song").item)
        let beforeAcknowledgement = try Data(contentsOf: fixture.file)

        failWrites.value = true
        XCTAssertThrowsError(try store.acknowledgeBits(item.id))
        XCTAssertEqual(store.pendingBitsItems(), [item])
        XCTAssertEqual(try Data(contentsOf: fixture.file), beforeAcknowledgement)
        XCTAssertEqual(
            try store.enqueueBits(
                messageID: "paid-message",
                broadcasterID: "broadcaster",
                userName: "viewer",
                bits: 100,
                boostEnabled: false,
                query: "a song").item,
            item)

        let relaunched = TwitchRedemptionResolutionOutbox(fileURL: fixture.file)
        XCTAssertEqual(relaunched.pendingBitsItems(), [item])
        XCTAssertEqual(
            try relaunched.enqueueBits(
                messageID: "paid-message",
                broadcasterID: "broadcaster",
                userName: "viewer",
                bits: 100,
                boostEnabled: false,
                query: "a song").item,
            item)
    }

    func testBitsTombstonesOutliveTransportCapacityAndPruneAfterHorizon()
        throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        let initialNow = Date(timeIntervalSince1970: 2_000)
        let clock = ThreadSafeBox(initialNow)
        let store = TwitchRedemptionResolutionOutbox(
            fileURL: fixture.file,
            nowProvider: { clock.value })

        func complete(_ messageID: String) throws {
            let result = try store.enqueueBits(
                messageID: messageID,
                broadcasterID: "broadcaster",
                userName: "viewer",
                bits: 100,
                boostEnabled: false,
                query: "a song")
            try store.acknowledgeBits(try XCTUnwrap(result.item).id)
        }

        try complete("oldest-paid-message")
        // The general EventSub cache holds 500 IDs. None of these paid IDs may
        // evict another before the timestamp acceptance horizon expires.
        for index in 0..<500 {
            try complete("busy-message-\(index)")
        }
        XCTAssertNil(
            try store.enqueueBits(
                messageID: "oldest-paid-message",
                broadcasterID: "broadcaster",
                userName: "viewer",
                bits: 100,
                boostEnabled: false,
                query: "a song").item)

        clock.value = initialNow.addingTimeInterval(
            TwitchRedemptionResolutionOutbox.paidEventTombstoneRetention + 1)
        let acceptedAgain = try store.enqueueBits(
            messageID: "oldest-paid-message",
            broadcasterID: "broadcaster",
            userName: "viewer",
            bits: 100,
            boostEnabled: false,
            query: "a song")
        XCTAssertTrue(acceptedAgain.inserted)
        XCTAssertNotNil(acceptedAgain.item)

        let relaunched = TwitchRedemptionResolutionOutbox(
            fileURL: fixture.file,
            nowProvider: { clock.value })
        XCTAssertEqual(
            relaunched.pendingBitsItems().map(\.messageID),
            ["oldest-paid-message"])
    }

    func testAcknowledgementTombstoneIsAtomicExactAndPrunedAfterHorizon()
        throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        let initialNow = Date(timeIntervalSince1970: 3_000)
        let clock = ThreadSafeBox(initialNow)
        let store = TwitchRedemptionResolutionOutbox(
            fileURL: fixture.file,
            nowProvider: { clock.value })
        let item = try store.enqueue(
            broadcasterID: "broadcaster-a",
            rewardID: "reward-a",
            redemptionID: "redemption-a",
            resolution: .fulfilled,
            now: initialNow)

        try store.acknowledge(item.id, at: initialNow)
        XCTAssertTrue(store.pendingItems().isEmpty)
        XCTAssertTrue(
            store.hasAcknowledgedRedemption(
                broadcasterID: "broadcaster-a",
                rewardID: "reward-a",
                redemptionID: "redemption-a"))
        XCTAssertFalse(
            store.hasAcknowledgedRedemption(
                broadcasterID: "broadcaster-b",
                rewardID: "reward-a",
                redemptionID: "redemption-a"))
        XCTAssertFalse(
            store.hasAcknowledgedRedemption(
                broadcasterID: "broadcaster-a",
                rewardID: "reward-b",
                redemptionID: "redemption-a"))

        let relaunched = TwitchRedemptionResolutionOutbox(
            fileURL: fixture.file,
            nowProvider: { clock.value })
        XCTAssertTrue(
            relaunched.hasAcknowledgedRedemption(
                broadcasterID: "broadcaster-a",
                rewardID: "reward-a",
                redemptionID: "redemption-a"))

        clock.value = initialNow.addingTimeInterval(
            TwitchRedemptionResolutionOutbox.paidEventTombstoneRetention + 1)
        XCTAssertFalse(
            relaunched.hasAcknowledgedRedemption(
                broadcasterID: "broadcaster-a",
                rewardID: "reward-a",
                redemptionID: "redemption-a"))
        try relaunched.verifyIntakeStorage()
        XCTAssertFalse(
            TwitchRedemptionResolutionOutbox(
                fileURL: fixture.file,
                nowProvider: { clock.value })
                .hasAcknowledgedRedemption(
                    broadcasterID: "broadcaster-a",
                    rewardID: "reward-a",
                    redemptionID: "redemption-a"))
    }

    func testDuplicateBusinessKeyIsQuarantinedInsteadOfReplayedTwice()
        throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        let first = TwitchRedemptionResolutionOutbox.Item(
            id: UUID(),
            broadcasterID: "broadcaster",
            rewardID: "reward",
            redemptionID: "redemption",
            resolutionRawValue:
                TwitchChannelPointsService.Resolution.fulfilled.rawValue,
            createdAt: Date(timeIntervalSince1970: 1))
        let duplicate = TwitchRedemptionResolutionOutbox.Item(
            id: UUID(),
            broadcasterID: "broadcaster",
            rewardID: "reward",
            redemptionID: "redemption",
            resolutionRawValue:
                TwitchChannelPointsService.Resolution.canceled.rawValue,
            createdAt: Date(timeIntervalSince1970: 2))
        try JSONEncoder().encode([first, duplicate]).write(
            to: fixture.file,
            options: .atomic)

        let store = TwitchRedemptionResolutionOutbox(fileURL: fixture.file)

        XCTAssertTrue(store.pendingItems().isEmpty)
        XCTAssertTrue(store.hasOpaqueRecoveryRisk())
    }

    func testDuplicateItemUUIDIsQuarantinedInsteadOfCollidingWorkers()
        throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        let duplicateID = UUID()
        let first = TwitchRedemptionResolutionOutbox.Item(
            id: duplicateID,
            broadcasterID: "broadcaster",
            rewardID: "reward",
            redemptionID: "redemption-a",
            resolutionRawValue:
                TwitchChannelPointsService.Resolution.fulfilled.rawValue,
            createdAt: Date(timeIntervalSince1970: 1))
        let duplicate = TwitchRedemptionResolutionOutbox.Item(
            id: duplicateID,
            broadcasterID: "broadcaster",
            rewardID: "reward",
            redemptionID: "redemption-b",
            resolutionRawValue:
                TwitchChannelPointsService.Resolution.canceled.rawValue,
            createdAt: Date(timeIntervalSince1970: 2))
        try JSONEncoder().encode([first, duplicate]).write(
            to: fixture.file,
            options: .atomic)

        let store = TwitchRedemptionResolutionOutbox(fileURL: fixture.file)

        XCTAssertTrue(store.pendingItems().isEmpty)
        XCTAssertTrue(store.hasOpaqueRecoveryRisk())
    }

    func testLegacyItemArrayMigratesWithoutLosingPendingWork() throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        let item = TwitchRedemptionResolutionOutbox.Item(
            id: UUID(),
            broadcasterID: "broadcaster",
            rewardID: "reward",
            redemptionID: "redemption",
            resolutionRawValue:
                TwitchChannelPointsService.Resolution.canceled.rawValue,
            createdAt: Date())
        try JSONEncoder().encode([item]).write(
            to: fixture.file,
            options: .atomic)

        let migrated = TwitchRedemptionResolutionOutbox(fileURL: fixture.file)
        XCTAssertEqual(migrated.pendingItems(), [item])
        XCTAssertFalse(migrated.hasOpaqueRecoveryRisk())
        XCTAssertEqual(
            TwitchRedemptionResolutionOutbox(fileURL: fixture.file)
                .pendingItems(),
            [item])
    }

    func testOnlyTransientResolutionStatusesRetry() {
        for status in [408, 425, 429, 500, 503, 599] {
            XCTAssertTrue(TwitchChatService.shouldRetryRedemptionResolution(status: status))
        }
        for status in [200, 400, 401, 403, 404, 409, 600] {
            XCTAssertFalse(TwitchChatService.shouldRetryRedemptionResolution(status: status))
        }
    }

    private func makeFixture() throws -> (directory: URL, file: URL) {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "wolfwave-redemption-outbox-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        return (
            directory,
            directory.appending(path: "outbox.json")
        )
    }
}
