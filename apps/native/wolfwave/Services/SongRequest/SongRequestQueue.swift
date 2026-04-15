//
//  SongRequestQueue.swift
//  wolfwave
//
//  Created by MrDemonWolf, Inc. on 4/8/26.
//

import Foundation
import MusicKit
import Observation
import SwiftUI

/// In-memory song request queue with per-user limits and observable state.
///
/// The queue is intentionally not persisted — each stream session starts fresh.
/// All mutations are thread-safe via `NSLock`.
@Observable
final class SongRequestQueue {
    // MARK: - Properties

    /// The ordered queue of pending song requests.
    private(set) var items: [SongRequestItem] = []

    /// The item currently being played from the queue (nil if none).
    private(set) var nowPlaying: SongRequestItem?

    /// Lock for thread-safe access to queue state.
    private let lock = NSLock()

    /// Maximum number of items allowed in the queue.
    var maxQueueSize: Int {
        let stored = Foundation.UserDefaults.standard.integer(forKey: AppConstants.UserDefaults.songRequestMaxQueueSize)
        return stored > 0 ? stored : 10
    }

    /// Maximum requests per user in the queue at one time.
    var perUserLimit: Int {
        let stored = Foundation.UserDefaults.standard.integer(forKey: AppConstants.UserDefaults.songRequestPerUserLimit)
        return stored > 0 ? stored : 2
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

    /// Add a song request to the end of the queue.
    ///
    /// - Parameters:
    ///   - item: The song request to add.
    /// - Returns: The result indicating success or the reason for rejection.
    func add(_ item: SongRequestItem) -> AddResult {
        lock.withLock {
            // Check queue capacity
            guard items.count < maxQueueSize else {
                return .queueFull(max: maxQueueSize)
            }

            // Check per-user limit
            let userCount = items.filter { $0.requesterUsername.lowercased() == item.requesterUsername.lowercased() }.count
            guard userCount < perUserLimit else {
                return .userLimitReached(max: perUserLimit)
            }

            // Check for duplicate (same song by same user)
            let isDuplicate = items.contains {
                $0.title.lowercased() == item.title.lowercased()
                && $0.artist.lowercased() == item.artist.lowercased()
                && $0.requesterUsername.lowercased() == item.requesterUsername.lowercased()
            }
            guard !isDuplicate else {
                return .alreadyInQueue
            }

            items.append(item)
            return .added(position: items.count)
        }
    }

    /// Remove and return the next item from the front of the queue.
    ///
    /// Sets `nowPlaying` to the dequeued item.
    /// - Returns: The next song request, or nil if the queue is empty.
    @discardableResult
    func dequeue() -> SongRequestItem? {
        lock.withLock {
            guard !items.isEmpty else { return nil }
            let item = items.removeFirst()
            nowPlaying = item
            return item
        }
    }

    /// Skip the currently playing request and advance to the next in queue.
    ///
    /// - Returns: The next song request that is now playing, or nil if queue is empty.
    @discardableResult
    func skip() -> SongRequestItem? {
        lock.withLock {
            if !items.isEmpty {
                nowPlaying = items.removeFirst()
            } else {
                nowPlaying = nil
            }
            return nowPlaying
        }
    }

    /// Remove all items from the queue and clear now-playing.
    ///
    /// - Returns: The number of items that were removed.
    @discardableResult
    func clear() -> Int {
        lock.withLock {
            let count = items.count
            items.removeAll()
            nowPlaying = nil
            return count
        }
    }

    /// Remove a specific item from the queue by its ID.
    func remove(id: UUID) {
        lock.withLock {
            items.removeAll { $0.id == id }
        }
    }

    /// Move an item from one position to another (for drag-to-reorder).
    func move(from source: IndexSet, to destination: Int) {
        lock.withLock {
            items.move(fromOffsets: source, toOffset: destination)
        }
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
    }

    /// Re-insert an item at the front of the queue without re-running limit checks.
    ///
    /// Used when Music.app is closed mid-play — the item is placed back so it will be
    /// the first to play when Music.app re-opens.
    func insertAtHead(_ item: SongRequestItem) {
        lock.withLock {
            items.insert(item, at: 0)
        }
    }
}
