//
//  SongRequestQueue.swift
//  WolfWave
//
//  Created by Nathanial Henniges on 2026-04-15.
//  Copyright © 2026 MrDemonWolf, Inc. All rights reserved.
//

import Foundation
import MusicKit
import SwiftUI

/// In-memory song request queue with per-user limits.
///
/// The queue is intentionally not persisted. Each stream session starts fresh.
/// MainActor-isolated (project default isolation); the `NSLock` is retained as a
/// defense-in-depth guard around the mutation methods. Consumers (the queue
/// settings view) poll the public state via a refresh timer rather than
/// observing it reactively, so this type does not adopt the `@Observable` macro.
final class SongRequestQueue {
    // MARK: - Properties

    /// The ordered queue of pending song requests.
    private(set) var items: [SongRequestItem] = []

    /// Requests awaiting streamer approval (approval mode only). Empty when the
    /// `songRequestApprovalRequired` toggle is off, since requests go straight to
    /// `items` then.
    private(set) var pending: [SongRequestItem] = []

    /// The item currently being played from the queue (nil if none).
    private(set) var nowPlaying: SongRequestItem?

    /// Lock for thread-safe access to queue state.
    private let lock = NSLock()

    /// Maximum number of items allowed in the queue.
    var maxQueueSize: Int {
        Preferences.int(AppConstants.UserDefaults.songRequestMaxQueueSize, default: 10)
    }

    /// Maximum requests per user in the queue at one time.
    var perUserLimit: Int {
        Preferences.int(AppConstants.UserDefaults.songRequestPerUserLimit, default: 2)
    }

    /// Whether new requests interleave round-robin (fair-share) instead of FIFO.
    var fairShareEnabled: Bool {
        Preferences.bool(AppConstants.UserDefaults.songRequestFairShare, default: true)
    }

    /// Total number of items in the queue (not counting now-playing).
    var count: Int {
        lock.withLock { items.count }
    }

    /// Whether the queue is empty (no pending items).
    var isEmpty: Bool {
        lock.withLock { items.isEmpty }
    }

    /// Whether the queue is at capacity.
    var isFull: Bool {
        lock.withLock { items.count >= maxQueueSize }
    }

    // MARK: - Queue Operations

    /// Result of attempting to add a song to the queue.
    enum AddResult {
        case added(position: Int)
        case queueFull(max: Int)
        case userLimitReached(max: Int)
        case alreadyInQueue
    }

    private func postQueueChanged() {
        NotificationCenter.default.post(name: .songRequestQueueChanged, object: nil)
    }

    /// Add a song request to the end of the queue.
    ///
    /// - Parameters:
    ///   - item: The song request to add.
    ///   - perUserLimitOverride: The effective per-user limit for this requester,
    ///     resolved from their roles by `SongRequestLimits`. When `nil`, the
    ///     global `perUserLimit` is used (legacy callers and tests).
    /// - Returns: The result indicating success or the reason for rejection.
    func add(_ item: SongRequestItem, perUserLimit perUserLimitOverride: Int? = nil) -> AddResult {
        let effectiveUserLimit = perUserLimitOverride ?? perUserLimit
        let result: AddResult = lock.withLock {
            // Check queue capacity
            guard items.count < maxQueueSize else {
                return .queueFull(max: maxQueueSize)
            }

            // Check per-user limit. Include the now-playing slot when it belongs
            // to the same requester so the total in-flight count stays at most
            // `effectiveUserLimit` rather than `effectiveUserLimit + 1`.
            let lowered = item.requesterUsername.lowercased()
            let nowPlayingCount = (nowPlaying?.requesterUsername.lowercased() == lowered) ? 1 : 0
            let userCount = items.filter { $0.requesterUsername.lowercased() == lowered }.count + nowPlayingCount
            guard userCount < effectiveUserLimit else {
                return .userLimitReached(max: effectiveUserLimit)
            }

            // Check for duplicate (same song by same user). The now-playing
            // slot counts too, mirroring the per-user limit above: a requester
            // shouldn't be able to immediately re-queue the song that's
            // currently playing for them.
            let isDuplicate = (nowPlaying?.isSameRequest(as: item) ?? false)
                || items.contains { $0.isSameRequest(as: item) }
            guard !isDuplicate else {
                return .alreadyInQueue
            }

            return insertRespectingCapacity(item)
        }
        postQueueChanged()
        return result
    }

    /// Fair-share (round-robin) insert index for a new item, assuming the lock is
    /// held. The new item's "round" is how many requests its requester already has
    /// queued (0 = their first). It slots after every item in earlier or equal
    /// rounds and before the first item in a later round, so everyone's Nth request
    /// plays before anyone's (N+1)th while FIFO order holds within a round.
    ///
    /// Sub/VIP priority (WW-43) applies *within* a round, not as a FIFO override: a
    /// priority item slots ahead of the non-priority items in its own round but
    /// stays behind earlier rounds and behind priority items already in that round.
    /// A non-priority item never jumps a priority item, so priority requests lead
    /// each round.
    private func fairShareInsertIndex(for item: SongRequestItem) -> Int {
        let lowered = item.requesterUsername.lowercased()
        let newRound = items.filter { $0.requesterUsername.lowercased() == lowered }.count
        var counts: [String: Int] = [:]
        for (index, existing) in items.enumerated() {
            let key = existing.requesterUsername.lowercased()
            let existingRound = counts[key, default: 0]
            counts[key] = existingRound + 1
            if existingRound > newRound { return index }
            if existingRound == newRound, item.isPriority, !existing.isPriority { return index }
        }
        return items.count
    }

    /// Inserts `item` at its fair-share position (or the tail) after a capacity
    /// check. Assumes `lock` is held. Returns `.queueFull` at capacity, else
    /// `.added(position:)`. Shared by `add(_:)` and `addApproved(_:)`.
    private func insertRespectingCapacity(_ item: SongRequestItem) -> AddResult {
        guard items.count < maxQueueSize else {
            return .queueFull(max: maxQueueSize)
        }
        let index = fairShareEnabled ? fairShareInsertIndex(for: item) : items.count
        items.insert(item, at: index)
        return .added(position: index + 1)
    }

    // MARK: - Approval Holding Pen

    /// Number of requests awaiting approval.
    var pendingCount: Int {
        lock.withLock { pending.count }
    }

    /// Add a request to the approval holding pen. Capacity-capped by
    /// `maxQueueSize`; dedups the same song by the same user. Per-user throttling
    /// is left to the upstream command cooldowns.
    /// ponytail: no per-user cap on pending; cooldowns + Clear All bound spam.
    @discardableResult
    func addPending(_ item: SongRequestItem) -> AddResult {
        let result: AddResult = lock.withLock {
            guard pending.count < maxQueueSize else {
                return .queueFull(max: maxQueueSize)
            }
            // Dedupe across the pending pen, the live queue, and now-playing, so a
            // song already queued/playing for a user can't be re-parked in pending
            // and later approved as a duplicate. Mirrors `add(_:)`.
            let isDuplicate = pending.contains { $0.isSameRequest(as: item) }
                || items.contains { $0.isSameRequest(as: item) }
                || (nowPlaying?.isSameRequest(as: item) ?? false)
            guard !isDuplicate else { return .alreadyInQueue }
            pending.append(item)
            return .added(position: pending.count)
        }
        postQueueChanged()
        return result
    }

    /// Remove and return a pending item by ID (used when approving it).
    func takePending(id: UUID) -> SongRequestItem? {
        let item: SongRequestItem? = lock.withLock {
            guard let index = pending.firstIndex(where: { $0.id == id }) else { return nil }
            return pending.remove(at: index)
        }
        if item != nil { postQueueChanged() }
        return item
    }

    /// Remove all pending items. Returns the number removed.
    @discardableResult
    func clearPending() -> Int {
        let count: Int = lock.withLock {
            let count = pending.count
            pending.removeAll()
            return count
        }
        postQueueChanged()
        return count
    }

    /// Append an already-approved item to the live queue, checking only queue
    /// capacity. The streamer vetted it, so the per-user and duplicate gates that
    /// `add(_:)` enforces don't apply to a manual approval.
    @discardableResult
    func addApproved(_ item: SongRequestItem) -> AddResult {
        let result: AddResult = lock.withLock {
            insertRespectingCapacity(item)
        }
        postQueueChanged()
        return result
    }

    /// Remove and return the next item from the front of the queue.
    ///
    /// Sets `nowPlaying` to the dequeued item.
    /// - Returns: The next song request, or nil if the queue is empty.
    @discardableResult
    func dequeue() -> SongRequestItem? {
        let item: SongRequestItem? = lock.withLock {
            guard !items.isEmpty else { return nil }
            let item = items.removeFirst()
            nowPlaying = item
            return item
        }
        if item != nil { postQueueChanged() }
        return item
    }

    /// Skip the currently playing request and advance to the next in queue.
    ///
    /// - Returns: The next song request that is now playing, or nil if queue is empty.
    @discardableResult
    func skip() -> SongRequestItem? {
        let result: SongRequestItem? = lock.withLock {
            if !items.isEmpty {
                nowPlaying = items.removeFirst()
            } else {
                nowPlaying = nil
            }
            return nowPlaying
        }
        postQueueChanged()
        return result
    }

    /// Remove all items from the queue and clear now-playing.
    ///
    /// - Returns: The number of items that were removed.
    @discardableResult
    func clear() -> Int {
        let count: Int = lock.withLock {
            let count = items.count
            items.removeAll()
            pending.removeAll()
            nowPlaying = nil
            return count
        }
        postQueueChanged()
        return count
    }

    /// Remove a specific item from the queue by its ID.
    func remove(id: UUID) {
        lock.withLock {
            items.removeAll { $0.id == id }
        }
        postQueueChanged()
    }

    /// Move an item from one position to another (for drag-to-reorder).
    func move(from source: IndexSet, to destination: Int) {
        lock.withLock {
            items.move(fromOffsets: source, toOffset: destination)
        }
        postQueueChanged()
    }

    /// Move a user's earliest pending request to the front of the queue. Used by
    /// the bit-cheer "boost" feature. Boosting the user's *oldest* queued request
    /// (the one they've waited on longest) matches "move me up" intuition better
    /// than jumping their newest addition ahead of it.
    ///
    /// - Parameter username: Twitch username whose request should jump ahead.
    /// - Returns: The boosted item, or `nil` when the user has nothing queued.
    @discardableResult
    func boost(username: String) -> SongRequestItem? {
        let boosted: SongRequestItem? = lock.withLock {
            let lowered = username.lowercased()
            guard let index = items.firstIndex(where: {
                $0.requesterUsername.lowercased() == lowered
            }) else {
                return nil
            }
            let item = items.remove(at: index)
            items.insert(item, at: 0)
            return item
        }
        if boosted != nil { postQueueChanged() }
        return boosted
    }

    /// Get the queue positions for a specific user.
    ///
    /// - Parameter username: The Twitch username to look up.
    /// - Returns: Array of (position, item) tuples for this user's requests.
    func positions(for username: String) -> [(position: Int, item: SongRequestItem)] {
        lock.withLock {
            items.enumerated()
                .filter { $0.element.requesterUsername.lowercased() == username.lowercased() }
                .map { (position: $0.offset + 1, item: $0.element) }
        }
    }

    /// Clear the now-playing state (e.g., when song finishes and queue is empty).
    func clearNowPlaying() {
        lock.withLock {
            nowPlaying = nil
        }
        postQueueChanged()
    }

    /// Re-insert an item at the front of the queue without re-running limit checks.
    ///
    /// Used when Music.app is closed mid-play. The item is placed back so it will be
    /// the first to play when Music.app re-opens.
    func insertAtHead(_ item: SongRequestItem) {
        lock.withLock {
            items.insert(item, at: 0)
        }
        postQueueChanged()
    }
}
