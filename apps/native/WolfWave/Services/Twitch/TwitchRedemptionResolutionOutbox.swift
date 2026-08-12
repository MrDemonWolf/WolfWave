//
//  TwitchRedemptionResolutionOutbox.swift
//  WolfWave
//
//  Created by Nathanial Henniges on 2026-08-12.
//  Copyright © 2026 MrDemonWolf, Inc. All rights reserved.
//

import Foundation

/// Atomic disk-backed state for paid Twitch event intake and completion.
///
/// Channel-point work is retained through its terminal Helix acknowledgement;
/// Bits work is persisted before queue mutation and replaced atomically by an
/// exact EventSub tombstone afterward. Exact channel-point business tombstones
/// and Bits message tombstones close late-redelivery, reconnect, and relaunch
/// windows without relying on the bounded transport dedup cache.
nonisolated final class TwitchRedemptionResolutionOutbox: @unchecked Sendable {
    struct Item: Codable, Equatable, Identifiable, Sendable {
        static let intakeRawValue = "WOLFWAVE_INTAKE"

        let id: UUID
        let broadcasterID: String
        let rewardID: String
        let redemptionID: String
        let resolutionRawValue: String
        let createdAt: Date

        var resolution: TwitchChannelPointsService.Resolution? {
            TwitchChannelPointsService.Resolution(rawValue: resolutionRawValue)
        }

        /// Persisted before song lookup or queue mutation. If the process exits
        /// while this phase remains, replay refunds because the in-memory song
        /// request outcome cannot be reconstructed safely.
        var isIntake: Bool { resolutionRawValue == Self.intakeRawValue }

        var isValid: Bool {
            !broadcasterID.isEmpty
                && !rewardID.isEmpty
                && !redemptionID.isEmpty
                && (isIntake || resolution != nil)
        }
    }

    struct BitsItem: Codable, Equatable, Identifiable, Sendable {
        let id: UUID
        let messageID: String
        let broadcasterID: String
        let userName: String
        let bits: Int
        let boostEnabled: Bool
        let query: String
        let createdAt: Date

        var isValid: Bool {
            !messageID.isEmpty
                && !broadcasterID.isEmpty
                && !userName.isEmpty
                && bits > 0
        }
    }

    enum PaidEventKind: String, Codable, Equatable, Hashable, Sendable {
        case channelPointRedemption
        case bitsUse
    }

    struct PaidEventTombstone: Codable, Equatable, Sendable {
        let messageID: String
        let broadcasterID: String
        let kind: PaidEventKind
        let acceptedAt: Date

        var isValid: Bool {
            !messageID.isEmpty && !broadcasterID.isEmpty
        }
    }

    struct AcknowledgedRedemptionTombstone: Codable, Equatable, Sendable {
        let broadcasterID: String
        let rewardID: String
        let redemptionID: String
        let acknowledgedAt: Date

        var isValid: Bool {
            !broadcasterID.isEmpty
                && !rewardID.isEmpty
                && !redemptionID.isEmpty
        }
    }

    /// Twitch accepts frames from 10 minutes ago and allows 30 seconds of
    /// forward clock skew. Paid-event tombstones therefore remain durable for
    /// that complete local acceptance horizon without a count cap that busy
    /// channels could evict early.
    static let paidEventTombstoneRetention: TimeInterval = 10 * 60 + 30

    private struct PersistedState: Codable {
        static let currentVersion = 1

        let version: Int
        let items: [Item]
        let bitsItems: [BitsItem]
        let paidEventTombstones: [PaidEventTombstone]
        let acknowledgedRedemptionTombstones:
            [AcknowledgedRedemptionTombstone]
    }

    private struct RedemptionKey: Hashable {
        let broadcasterID: String
        let rewardID: String
        let redemptionID: String
    }

    private struct PaidEventKey: Hashable {
        let messageID: String
        let broadcasterID: String
        let kind: PaidEventKind
    }

    private enum DecodeError: Error {
        case unsupportedVersion
        case duplicateRedemption
    }

    enum StoreError: Error {
        case invalidItem
        case missingItem
        case unreadableExistingStore
        case unresolvedRecoveryRisk
    }

    static let shared = TwitchRedemptionResolutionOutbox()

    private let lock = NSLock()
    private let fileURL: URL
    private let fileManager: FileManager
    private let atomicWriter: (Data, URL) throws -> Void
    private let quarantineMover: (URL, URL) throws -> Void
    private let quarantineCopier: (URL, URL) throws -> Void
    private let nowProvider: @Sendable () -> Date
    private var items: [Item]
    private var bitsItems: [BitsItem]
    private var paidEventTombstones: [PaidEventTombstone]
    private var acknowledgedRedemptionTombstones:
        [AcknowledgedRedemptionTombstone]
    private var existingStoreIsUnreadable = false
    private var intakeStorageHasFailed = false
    private var opaqueRecoveryRisk = false

    init(
        fileURL: URL = AppContainer.directory("State")
            .appending(path: "twitch-redemption-resolution-outbox.json"),
        fileManager: FileManager = .default,
        atomicWriter: @escaping (Data, URL) throws -> Void = { data, url in
            try data.write(to: url, options: .atomic)
        },
        quarantineMover: ((URL, URL) throws -> Void)? = nil,
        quarantineCopier: ((URL, URL) throws -> Void)? = nil,
        nowProvider: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.fileURL = fileURL
        self.fileManager = fileManager
        self.atomicWriter = atomicWriter
        self.quarantineMover = quarantineMover ?? { source, destination in
            try fileManager.moveItem(at: source, to: destination)
        }
        self.quarantineCopier = quarantineCopier ?? { source, destination in
            try fileManager.copyItem(at: source, to: destination)
        }
        self.nowProvider = nowProvider
        self.items = []
        self.bitsItems = []
        self.paidEventTombstones = []
        self.acknowledgedRedemptionTombstones = []
        let quarantinePrefix = fileURL.lastPathComponent + ".corrupt-"
        self.opaqueRecoveryRisk = (
            try? fileManager.contentsOfDirectory(
                atPath: fileURL.deletingLastPathComponent().path)
        )?.contains {
            $0.hasPrefix(quarantinePrefix)
        } ?? false
        guard fileManager.fileExists(atPath: fileURL.path) else {
            return
        }

        var decodedItems: [Item] = []
        var decodedBitsItems: [BitsItem] = []
        var decodedPaidEventTombstones: [PaidEventTombstone] = []
        var decodedAcknowledgedTombstones:
            [AcknowledgedRedemptionTombstone] = []
        var needsFormatMigration = false
        do {
            let data = try Data(contentsOf: fileURL)
            let decoder = JSONDecoder()
            if let state = try? decoder.decode(
                PersistedState.self,
                from: data
            ) {
                guard state.version == PersistedState.currentVersion else {
                    throw DecodeError.unsupportedVersion
                }
                decodedItems = state.items
                decodedBitsItems = state.bitsItems
                decodedPaidEventTombstones = state.paidEventTombstones
                decodedAcknowledgedTombstones =
                    state.acknowledgedRedemptionTombstones
            } else {
                // Version-zero files stored only the pending item array.
                decodedItems = try decoder.decode([Item].self, from: data)
                needsFormatMigration = true
            }

            var itemIDs = Set<Item.ID>()
            var businessKeys = Set<RedemptionKey>()
            for item in decodedItems {
                guard itemIDs.insert(item.id).inserted else {
                    throw DecodeError.duplicateRedemption
                }
                let key = RedemptionKey(
                    broadcasterID: item.broadcasterID,
                    rewardID: item.rewardID,
                    redemptionID: item.redemptionID)
                guard businessKeys.insert(key).inserted else {
                    throw DecodeError.duplicateRedemption
                }
            }
            var bitsItemIDs = Set<BitsItem.ID>()
            var bitsKeys = Set<PaidEventKey>()
            for item in decodedBitsItems {
                let key = PaidEventKey(
                    messageID: item.messageID,
                    broadcasterID: item.broadcasterID,
                    kind: .bitsUse)
                guard bitsItemIDs.insert(item.id).inserted,
                      bitsKeys.insert(key).inserted else {
                    throw DecodeError.duplicateRedemption
                }
            }
        } catch {
            do {
                let quarantineURL = try quarantineExistingStore()
                opaqueRecoveryRisk = true
                Log.error(
                    "Twitch redemption outbox was quarantined at \(quarantineURL.lastPathComponent): \(error.localizedDescription)",
                    category: "Twitch"
                )
            } catch let quarantineError {
                // If recovery bytes cannot be preserved, refuse to overwrite
                // them. This rare filesystem failure remains visible in logs.
                self.existingStoreIsUnreadable = true
                Log.error(
                    "Twitch redemption outbox quarantine failed: \(quarantineError.localizedDescription)",
                    category: "Twitch"
                )
            }
            return
        }

        let validItems = decodedItems.filter(\.isValid)
        let validBitsItems = decodedBitsItems.filter(\.isValid)
        let now = nowProvider()
        let validPaidEventTombstones = Self.normalizedPaidEventTombstones(
            decodedPaidEventTombstones,
            now: now)
        let validAcknowledgedTombstones =
            Self.normalizedAcknowledgedRedemptionTombstones(
                decodedAcknowledgedTombstones,
                now: now)
        let containsInvalidData =
            validItems.count != decodedItems.count
                || validBitsItems.count != decodedBitsItems.count
                || decodedPaidEventTombstones.contains { !$0.isValid }
                || decodedAcknowledgedTombstones.contains { !$0.isValid }

        self.items = validItems
        self.bitsItems = validBitsItems
        self.paidEventTombstones = validPaidEventTombstones
        self.acknowledgedRedemptionTombstones =
            validAcknowledgedTombstones

        if containsInvalidData {
            do {
                // Copy before replacing the live file. If the atomic rewrite
                // fails, the original remains available for another salvage.
                let quarantineURL = try copyExistingStoreToQuarantine()
                opaqueRecoveryRisk = true
                do {
                    try persist(
                        validItems,
                        bitsItems: validBitsItems,
                        paidEventTombstones: validPaidEventTombstones,
                        acknowledgedRedemptionTombstones:
                            validAcknowledgedTombstones)
                } catch {
                    Log.error(
                        "Twitch redemption outbox valid subset could not be restored: \(error.localizedDescription)",
                        category: "Twitch"
                    )
                }
                Log.error(
                    "Twitch redemption outbox contained invalid records; original quarantined at \(quarantineURL.lastPathComponent)",
                    category: "Twitch"
                )
            } catch {
                existingStoreIsUnreadable = true
                Log.error(
                    "Twitch redemption outbox quarantine failed: \(error.localizedDescription)",
                    category: "Twitch"
                )
            }
            return
        }

        let needsRewrite =
            needsFormatMigration
                || validPaidEventTombstones != decodedPaidEventTombstones
                || validAcknowledgedTombstones
                    != decodedAcknowledgedTombstones
        guard needsRewrite else { return }
        do {
            try persist(
                validItems,
                bitsItems: validBitsItems,
                paidEventTombstones: validPaidEventTombstones,
                acknowledgedRedemptionTombstones:
                    validAcknowledgedTombstones)
        } catch {
            Log.error(
                "Twitch redemption outbox maintenance write failed: \(error.localizedDescription)",
                category: "Twitch")
        }
    }

    /// Returns a stable oldest-first snapshot for replay.
    func pendingItems() -> [Item] {
        lock.withLock { items.sorted { $0.createdAt < $1.createdAt } }
    }

    /// Returns stable oldest-first replayable Bits events, optionally scoped to
    /// one broadcaster during account teardown.
    func pendingBitsItems(
        broadcasterID: String? = nil
    ) -> [BitsItem] {
        lock.withLock {
            bitsItems
                .filter {
                    broadcasterID == nil
                        || $0.broadcasterID == broadcasterID
                }
                .sorted { $0.createdAt < $1.createdAt }
        }
    }

    /// Persists the complete Bits action before touching the volatile request
    /// queue. A terminal tombstone suppresses only work already acknowledged;
    /// a pending duplicate resumes the same durable item.
    func enqueueBits(
        messageID: String,
        broadcasterID: String,
        userName: String,
        bits: Int,
        boostEnabled: Bool,
        query: String
    ) throws -> (item: BitsItem?, inserted: Bool) {
        guard !messageID.isEmpty,
              !broadcasterID.isEmpty,
              !userName.isEmpty,
              bits > 0 else {
            throw StoreError.invalidItem
        }

        return try lock.withLock {
            guard !existingStoreIsUnreadable else {
                throw StoreError.unreadableExistingStore
            }
            let now = nowProvider()
            let normalizedPaid = Self.normalizedPaidEventTombstones(
                paidEventTombstones,
                now: now)
            let normalizedAcknowledged =
                Self.normalizedAcknowledgedRedemptionTombstones(
                    acknowledgedRedemptionTombstones,
                    now: now)
            let key = PaidEventKey(
                messageID: messageID,
                broadcasterID: broadcasterID,
                kind: .bitsUse)
            if normalizedPaid.contains(where: {
                PaidEventKey(
                    messageID: $0.messageID,
                    broadcasterID: $0.broadcasterID,
                    kind: $0.kind) == key
            }) {
                paidEventTombstones = normalizedPaid
                acknowledgedRedemptionTombstones =
                    normalizedAcknowledged
                return (nil, false)
            }
            if let existing = bitsItems.first(where: {
                $0.messageID == messageID
                    && $0.broadcasterID == broadcasterID
            }) {
                paidEventTombstones = normalizedPaid
                acknowledgedRedemptionTombstones =
                    normalizedAcknowledged
                return (existing, false)
            }

            let item = BitsItem(
                id: UUID(),
                messageID: messageID,
                broadcasterID: broadcasterID,
                userName: userName,
                bits: bits,
                boostEnabled: boostEnabled,
                query: query,
                createdAt: now)
            let replacementBitsItems = bitsItems + [item]
            try persist(
                items,
                bitsItems: replacementBitsItems,
                paidEventTombstones: normalizedPaid,
                acknowledgedRedemptionTombstones:
                    normalizedAcknowledged)
            bitsItems = replacementBitsItems
            paidEventTombstones = normalizedPaid
            acknowledgedRedemptionTombstones =
                normalizedAcknowledged
            return (item, true)
        }
    }

    /// Commits completion by atomically replacing replayable Bits intake with a
    /// TTL-bound transport tombstone. A missing item is already complete.
    func acknowledgeBits(
        _ id: BitsItem.ID,
        at date: Date? = nil
    ) throws {
        try lock.withLock {
            guard !existingStoreIsUnreadable else {
                throw StoreError.unreadableExistingStore
            }
            guard let item = bitsItems.first(where: { $0.id == id }) else {
                return
            }
            let now = date ?? nowProvider()
            let key = PaidEventKey(
                messageID: item.messageID,
                broadcasterID: item.broadcasterID,
                kind: .bitsUse)
            let replacementBitsItems = bitsItems.filter { $0.id != id }
            var replacementPaid = Self.normalizedPaidEventTombstones(
                paidEventTombstones,
                now: now)
                .filter {
                    PaidEventKey(
                        messageID: $0.messageID,
                        broadcasterID: $0.broadcasterID,
                        kind: $0.kind) != key
                }
            replacementPaid.append(
                PaidEventTombstone(
                    messageID: item.messageID,
                    broadcasterID: item.broadcasterID,
                    kind: .bitsUse,
                    acceptedAt: now))
            replacementPaid = Self.normalizedPaidEventTombstones(
                replacementPaid,
                now: now)
            let normalizedAcknowledged =
                Self.normalizedAcknowledgedRedemptionTombstones(
                    acknowledgedRedemptionTombstones,
                    now: now)
            try persist(
                items,
                bitsItems: replacementBitsItems,
                paidEventTombstones: replacementPaid,
                acknowledgedRedemptionTombstones:
                    normalizedAcknowledged)
            bitsItems = replacementBitsItems
            paidEventTombstones = replacementPaid
            acknowledgedRedemptionTombstones =
                normalizedAcknowledged
        }
    }

    /// True only for the exact business transaction that already reached a
    /// terminal Helix acknowledgement. This remains separate from transport
    /// message IDs so another account or reward is never suppressed.
    func hasAcknowledgedRedemption(
        broadcasterID: String,
        rewardID: String,
        redemptionID: String
    ) -> Bool {
        guard !broadcasterID.isEmpty,
              !rewardID.isEmpty,
              !redemptionID.isEmpty else {
            return false
        }
        return lock.withLock {
            let normalized =
                Self.normalizedAcknowledgedRedemptionTombstones(
                    acknowledgedRedemptionTombstones,
                    now: nowProvider())
            acknowledgedRedemptionTombstones = normalized
            let key = RedemptionKey(
                broadcasterID: broadcasterID,
                rewardID: rewardID,
                redemptionID: redemptionID)
            return normalized.contains {
                RedemptionKey(
                    broadcasterID: $0.broadcasterID,
                    rewardID: $0.rewardID,
                    redemptionID: $0.redemptionID) == key
            }
        }
    }

    /// Sticky circuit-breaker state. A failed mutation remains unavailable
    /// until `verifyIntakeStorage()` proves an atomic commit works again.
    func intakeStorageIsUnavailable() -> Bool {
        lock.withLock { existingStoreIsUnreadable || intakeStorageHasFailed }
    }

    /// True when unreadable or quarantined bytes may contain a redemption that
    /// cannot be reconstructed automatically. This survives relaunch by
    /// detecting same-directory quarantine files and blocks credential teardown
    /// until the streamer explicitly recovers or removes those artifacts.
    func hasOpaqueRecoveryRisk() -> Bool {
        lock.withLock { existingStoreIsUnreadable || opaqueRecoveryRisk }
    }

    /// Clears quarantined opaque bytes only after held Helix recovery has
    /// enumerated and resolved every remote redemption and the live queue is
    /// empty. Normal logout never calls this discard boundary.
    func clearOpaqueRecoveryRiskAfterReconciliation() throws {
        try lock.withLock {
            guard !existingStoreIsUnreadable,
                  items.isEmpty,
                  bitsItems.isEmpty else {
                throw StoreError.unresolvedRecoveryRisk
            }
            let directory = fileURL.deletingLastPathComponent()
            let prefix = fileURL.lastPathComponent + ".corrupt-"
            let names: [String]
            if fileManager.fileExists(atPath: directory.path) {
                names = try fileManager.contentsOfDirectory(
                    atPath: directory.path)
            } else {
                names = []
            }
            for name in names where name.hasPrefix(prefix) {
                try fileManager.removeItem(
                    at: directory.appending(path: name))
            }
            opaqueRecoveryRisk = false
        }
    }

    /// Verifies that the current queue snapshot can be committed atomically.
    /// Call this before making the managed reward redeemable: a successful
    /// no-op rewrite proves intake can be persisted before any viewer spends
    /// points, while an unquarantined corrupt store remains protected.
    func verifyIntakeStorage() throws {
        try lock.withLock {
            guard !existingStoreIsUnreadable else {
                throw StoreError.unreadableExistingStore
            }
            let now = nowProvider()
            let normalizedPaid = Self.normalizedPaidEventTombstones(
                paidEventTombstones, now: now)
            let normalizedAcknowledged =
                Self.normalizedAcknowledgedRedemptionTombstones(
                    acknowledgedRedemptionTombstones, now: now)
            try persist(
                items,
                bitsItems: bitsItems,
                paidEventTombstones: normalizedPaid,
                acknowledgedRedemptionTombstones: normalizedAcknowledged)
            paidEventTombstones = normalizedPaid
            acknowledgedRedemptionTombstones = normalizedAcknowledged
            intakeStorageHasFailed = false
        }
    }

    /// Persists an idempotent work item before any network request begins.
    /// Duplicate EventSub deliveries reuse the existing item.
    func enqueueIntake(
        broadcasterID: String,
        rewardID: String,
        redemptionID: String,
        now: Date = Date()
    ) throws -> (item: Item, inserted: Bool) {
        try enqueue(
            broadcasterID: broadcasterID,
            rewardID: rewardID,
            redemptionID: redemptionID,
            resolutionRawValue: Item.intakeRawValue,
            now: now
        )
    }

    /// Persists a known resolution directly. Primarily used by replay fixtures;
    /// live redemption intake transitions via `updateResolution` instead.
    func enqueue(
        broadcasterID: String,
        rewardID: String,
        redemptionID: String,
        resolution: TwitchChannelPointsService.Resolution,
        now: Date = Date()
    ) throws -> Item {
        let result = try enqueue(
            broadcasterID: broadcasterID,
            rewardID: rewardID,
            redemptionID: redemptionID,
            resolutionRawValue: resolution.rawValue,
            now: now
        )
        return result.item
    }

    /// Atomically replaces an intake phase with its final Twitch resolution.
    /// Persistence happens before in-memory state changes, so a failed write
    /// deliberately leaves intake on disk and restart will refund it.
    func updateResolution(
        _ id: Item.ID,
        to resolution: TwitchChannelPointsService.Resolution
    ) throws -> Item {
        try lock.withLock {
            guard !existingStoreIsUnreadable else {
                throw StoreError.unreadableExistingStore
            }
            guard let index = items.firstIndex(where: { $0.id == id }) else {
                throw StoreError.missingItem
            }
            let current = items[index]
            if current.resolution == resolution { return current }
            // A confirmed resolution is immutable. A duplicate delivery must
            // never flip an already-persisted fulfil into a refund or vice versa.
            guard current.isIntake else { return current }
            let replacementItem = Item(
                id: current.id,
                broadcasterID: current.broadcasterID,
                rewardID: current.rewardID,
                redemptionID: current.redemptionID,
                resolutionRawValue: resolution.rawValue,
                createdAt: current.createdAt
            )
            var replacement = items
            replacement[index] = replacementItem
            try persist(
                replacement,
                bitsItems: bitsItems,
                paidEventTombstones: paidEventTombstones,
                acknowledgedRedemptionTombstones:
                    acknowledgedRedemptionTombstones)
            items = replacement
            return replacementItem
        }
    }

    private func enqueue(
        broadcasterID: String,
        rewardID: String,
        redemptionID: String,
        resolutionRawValue: String,
        now: Date
    ) throws -> (item: Item, inserted: Bool) {
        guard !broadcasterID.isEmpty, !rewardID.isEmpty, !redemptionID.isEmpty else {
            throw StoreError.invalidItem
        }

        return try lock.withLock {
            guard !existingStoreIsUnreadable else {
                throw StoreError.unreadableExistingStore
            }
            if let existing = items.first(where: {
                $0.broadcasterID == broadcasterID
                    && $0.rewardID == rewardID
                    && $0.redemptionID == redemptionID
            }) {
                return (existing, false)
            }

            let item = Item(
                id: UUID(),
                broadcasterID: broadcasterID,
                rewardID: rewardID,
                redemptionID: redemptionID,
                resolutionRawValue: resolutionRawValue,
                createdAt: now
            )
            guard item.isValid else { throw StoreError.invalidItem }
            let replacement = items + [item]
            try persist(
                replacement,
                bitsItems: bitsItems,
                paidEventTombstones: paidEventTombstones,
                acknowledgedRedemptionTombstones:
                    acknowledgedRedemptionTombstones)
            items = replacement
            return (item, true)
        }
    }

    /// Atomically removes a completed work item and records its exact business
    /// identity as terminal. A crash can therefore leave either replayable work
    /// or a tombstone, never an unprotected post-PATCH gap.
    func acknowledge(
        _ id: Item.ID,
        at date: Date? = nil
    ) throws {
        try lock.withLock {
            guard !existingStoreIsUnreadable else {
                throw StoreError.unreadableExistingStore
            }
            guard let item = items.first(where: { $0.id == id }) else {
                return
            }
            let acknowledgedAt = date ?? nowProvider()
            let now = nowProvider()
            let replacementItems = items.filter { $0.id != id }
            let key = RedemptionKey(
                broadcasterID: item.broadcasterID,
                rewardID: item.rewardID,
                redemptionID: item.redemptionID)
            var replacementAcknowledged =
                Self.normalizedAcknowledgedRedemptionTombstones(
                    acknowledgedRedemptionTombstones,
                    now: now)
                    .filter {
                        RedemptionKey(
                            broadcasterID: $0.broadcasterID,
                            rewardID: $0.rewardID,
                            redemptionID: $0.redemptionID) != key
                    }
            replacementAcknowledged.append(
                AcknowledgedRedemptionTombstone(
                    broadcasterID: item.broadcasterID,
                    rewardID: item.rewardID,
                    redemptionID: item.redemptionID,
                    acknowledgedAt: acknowledgedAt))
            replacementAcknowledged =
                Self.normalizedAcknowledgedRedemptionTombstones(
                    replacementAcknowledged,
                    now: now)
            let replacementPaid = Self.normalizedPaidEventTombstones(
                paidEventTombstones,
                now: now)
            try persist(
                replacementItems,
                bitsItems: bitsItems,
                paidEventTombstones: replacementPaid,
                acknowledgedRedemptionTombstones:
                    replacementAcknowledged)
            items = replacementItems
            paidEventTombstones = replacementPaid
            acknowledgedRedemptionTombstones =
                replacementAcknowledged
        }
    }

    /// Removes a pending item without marking its business transaction done.
    /// Production Helix acknowledgement uses `acknowledge(_:at:)`; this raw
    /// removal remains useful for explicit administrative/test cleanup.
    func remove(_ id: Item.ID) throws {
        try lock.withLock {
            guard !existingStoreIsUnreadable else {
                throw StoreError.unreadableExistingStore
            }
            let replacement = items.filter { $0.id != id }
            guard replacement.count != items.count else { return }
            try persist(
                replacement,
                bitsItems: bitsItems,
                paidEventTombstones: paidEventTombstones,
                acknowledgedRedemptionTombstones:
                    acknowledgedRedemptionTombstones)
            items = replacement
        }
    }

    private static func normalizedPaidEventTombstones(
        _ tombstones: [PaidEventTombstone],
        now: Date
    ) -> [PaidEventTombstone] {
        let oldestAcceptedAt = now.addingTimeInterval(
            -paidEventTombstoneRetention)
        let latestAcceptedAt = now.addingTimeInterval(
            paidEventTombstoneRetention)
        var newestByKey: [PaidEventKey: PaidEventTombstone] = [:]
        for tombstone in tombstones
        where tombstone.isValid
            && tombstone.acceptedAt >= oldestAcceptedAt
            && tombstone.acceptedAt <= latestAcceptedAt {
            let key = PaidEventKey(
                messageID: tombstone.messageID,
                broadcasterID: tombstone.broadcasterID,
                kind: tombstone.kind)
            if let existing = newestByKey[key],
               existing.acceptedAt >= tombstone.acceptedAt {
                continue
            }
            newestByKey[key] = tombstone
        }
        return newestByKey.values.sorted {
            if $0.acceptedAt != $1.acceptedAt {
                return $0.acceptedAt < $1.acceptedAt
            }
            if $0.broadcasterID != $1.broadcasterID {
                return $0.broadcasterID < $1.broadcasterID
            }
            if $0.kind != $1.kind {
                return $0.kind.rawValue < $1.kind.rawValue
            }
            return $0.messageID < $1.messageID
        }
    }

    private static func normalizedAcknowledgedRedemptionTombstones(
        _ tombstones: [AcknowledgedRedemptionTombstone],
        now: Date
    ) -> [AcknowledgedRedemptionTombstone] {
        let oldestAcknowledgedAt = now.addingTimeInterval(
            -paidEventTombstoneRetention)
        let latestAcknowledgedAt = now.addingTimeInterval(
            paidEventTombstoneRetention)
        var newestByKey:
            [RedemptionKey: AcknowledgedRedemptionTombstone] = [:]
        for tombstone in tombstones
        where tombstone.isValid
            && tombstone.acknowledgedAt >= oldestAcknowledgedAt
            && tombstone.acknowledgedAt <= latestAcknowledgedAt {
            let key = RedemptionKey(
                broadcasterID: tombstone.broadcasterID,
                rewardID: tombstone.rewardID,
                redemptionID: tombstone.redemptionID)
            if let existing = newestByKey[key],
               existing.acknowledgedAt >= tombstone.acknowledgedAt {
                continue
            }
            newestByKey[key] = tombstone
        }
        return newestByKey.values.sorted {
            if $0.acknowledgedAt != $1.acknowledgedAt {
                return $0.acknowledgedAt < $1.acknowledgedAt
            }
            if $0.broadcasterID != $1.broadcasterID {
                return $0.broadcasterID < $1.broadcasterID
            }
            if $0.rewardID != $1.rewardID {
                return $0.rewardID < $1.rewardID
            }
            return $0.redemptionID < $1.redemptionID
        }
    }

    private func persist(
        _ replacement: [Item],
        bitsItems: [BitsItem],
        paidEventTombstones: [PaidEventTombstone],
        acknowledgedRedemptionTombstones:
            [AcknowledgedRedemptionTombstone]
    ) throws {
        do {
            let directory = fileURL.deletingLastPathComponent()
            try fileManager.createDirectory(
                at: directory,
                withIntermediateDirectories: true
            )
            let state = PersistedState(
                version: PersistedState.currentVersion,
                items: replacement,
                bitsItems: bitsItems,
                paidEventTombstones: paidEventTombstones,
                acknowledgedRedemptionTombstones:
                    acknowledgedRedemptionTombstones)
            let data = try JSONEncoder().encode(state)
            try atomicWriter(data, fileURL)
        } catch {
            intakeStorageHasFailed = true
            throw error
        }
    }

    /// Same-directory rename is atomic on the app-container volume and retains
    /// every byte for diagnostics/manual recovery.
    private func quarantineExistingStore() throws -> URL {
        let quarantineURL = makeQuarantineURL()
        try quarantineMover(fileURL, quarantineURL)
        return quarantineURL
    }

    /// Preserves recovery bytes without creating a window where no live queue
    /// exists. The caller may now atomically replace `fileURL` with salvaged
    /// items while a failed replacement leaves the original intact.
    private func copyExistingStoreToQuarantine() throws -> URL {
        let quarantineURL = makeQuarantineURL()
        try quarantineCopier(fileURL, quarantineURL)
        return quarantineURL
    }

    private func makeQuarantineURL() -> URL {
        fileURL.appendingPathExtension("corrupt-\(UUID().uuidString)")
    }
}
