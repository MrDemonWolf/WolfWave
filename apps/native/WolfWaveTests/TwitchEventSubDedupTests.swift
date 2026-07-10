//
//  TwitchEventSubDedupTests.swift
//  WolfWave
//
//  Created by Nathanial Henniges on 2026-07-10.
//  Copyright © 2026 MrDemonWolf, Inc. All rights reserved.
//

import Foundation
import Testing

@testable import WolfWave

/// Contract tests for `TwitchChatService.EventSubMessageDeduplicator`, the
/// bounded seen-ID store that drops duplicate EventSub frames (Twitch delivers
/// at-least-once, especially around `session_reconnect`). Pure value type with
/// an injectable clock: no actor, no socket, no Keychain.
///
/// Note: `isDuplicate` is `mutating`, so calls are hoisted into locals instead
/// of being written inline inside `#expect` (the macro captures immutably).
@Suite("Twitch EventSub Dedup Tests")
struct TwitchEventSubDedupTests {

    private let base = Date(timeIntervalSinceReferenceDate: 800_000_000)

    // MARK: - Duplicate Detection

    @Test("First sighting of an ID is not a duplicate")
    func firstSightingIsNotDuplicate() {
        var dedup = TwitchChatService.EventSubMessageDeduplicator()
        let first = dedup.isDuplicate("msg-1", now: base)
        #expect(!first)
    }

    @Test("Repeat sighting within the TTL window is a duplicate")
    func repeatSightingWithinTTLIsDuplicate() {
        var dedup = TwitchChatService.EventSubMessageDeduplicator(ttl: 600, maxEntries: 500)
        let first = dedup.isDuplicate("msg-1", now: base)
        let sameInstant = dedup.isDuplicate("msg-1", now: base)
        let oneSecondLater = dedup.isDuplicate("msg-1", now: base.addingTimeInterval(1))
        let justInsideWindow = dedup.isDuplicate("msg-1", now: base.addingTimeInterval(599))
        #expect(!first)
        #expect(sameInstant)
        #expect(oneSecondLater)
        #expect(justInsideWindow)
    }

    @Test("Distinct IDs never flag each other")
    func distinctIDsAreIndependent() {
        var dedup = TwitchChatService.EventSubMessageDeduplicator()
        let first = dedup.isDuplicate("msg-1", now: base)
        let second = dedup.isDuplicate("msg-2", now: base)
        let third = dedup.isDuplicate("msg-3", now: base)
        let repeatSecond = dedup.isDuplicate("msg-2", now: base.addingTimeInterval(5))
        #expect(!first)
        #expect(!second)
        #expect(!third)
        #expect(repeatSecond)
    }

    // MARK: - TTL Pruning

    @Test("An ID older than the TTL is pruned and reads as new again")
    func expiredIDIsPruned() {
        var dedup = TwitchChatService.EventSubMessageDeduplicator(ttl: 600, maxEntries: 500)
        let first = dedup.isDuplicate("msg-1", now: base)
        // Past the window: the original sighting has aged out.
        let afterExpiry = dedup.isDuplicate("msg-1", now: base.addingTimeInterval(601))
        #expect(!first)
        #expect(!afterExpiry)
    }

    @Test("A duplicate sighting does not refresh the original timestamp")
    func duplicateSightingDoesNotRefreshTTL() {
        var dedup = TwitchChatService.EventSubMessageDeduplicator(ttl: 600, maxEntries: 500)
        let first = dedup.isDuplicate("msg-1", now: base)
        // Seen again mid-window; still keyed to the first sighting.
        let midWindow = dedup.isDuplicate("msg-1", now: base.addingTimeInterval(300))
        // The first sighting has aged out even though a duplicate arrived later.
        let afterExpiry = dedup.isDuplicate("msg-1", now: base.addingTimeInterval(601))
        #expect(!first)
        #expect(midWindow)
        #expect(!afterExpiry)
    }

    // MARK: - Size Cap

    @Test("Exceeding the cap evicts the oldest entries first")
    func capEvictsOldestFirst() {
        var dedup = TwitchChatService.EventSubMessageDeduplicator(ttl: 600, maxEntries: 3)
        let insertA = dedup.isDuplicate("a", now: base)
        let insertB = dedup.isDuplicate("b", now: base.addingTimeInterval(1))
        let insertC = dedup.isDuplicate("c", now: base.addingTimeInterval(2))
        // Fourth insert pushes the store over the cap; "a" (oldest) is evicted.
        let insertD = dedup.isDuplicate("d", now: base.addingTimeInterval(3))
        // Evicted, so it reads as brand new (re-inserting it evicts "b").
        let reinsertA = dedup.isDuplicate("a", now: base.addingTimeInterval(4))
        // Newer entries survived both evictions.
        let repeatC = dedup.isDuplicate("c", now: base.addingTimeInterval(5))
        let repeatD = dedup.isDuplicate("d", now: base.addingTimeInterval(6))
        #expect(!insertA)
        #expect(!insertB)
        #expect(!insertC)
        #expect(!insertD)
        #expect(!reinsertA)
        #expect(repeatC)
        #expect(repeatD)
    }

    @Test("A degenerate cap is clamped to at least one entry")
    func degenerateCapStillRemembersLatest() {
        var dedup = TwitchChatService.EventSubMessageDeduplicator(ttl: 600, maxEntries: 0)
        let insertA = dedup.isDuplicate("a", now: base)
        let repeatA = dedup.isDuplicate("a", now: base.addingTimeInterval(1))
        let insertB = dedup.isDuplicate("b", now: base.addingTimeInterval(2))
        // "a" was evicted to keep the store at the (clamped) single entry.
        let reinsertA = dedup.isDuplicate("a", now: base.addingTimeInterval(3))
        #expect(!insertA)
        #expect(repeatA)
        #expect(!insertB)
        #expect(!reinsertA)
    }
}
