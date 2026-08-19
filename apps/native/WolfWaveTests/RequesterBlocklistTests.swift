//
//  RequesterBlocklistTests.swift
//  WolfWave
//
//  Created by Nathanial Henniges on 2026-08-18.
//  Copyright © 2026 MrDemonWolf, Inc. All rights reserved.
//

import Foundation
import Testing
@testable import WolfWave

/// Blocking a person is a different question from blocking a song, asked at a
/// different point in the request pipeline. These pin that separation.
@Suite("Requester blocklist")
struct RequesterBlocklistTests {

    private func makeBlocklist() -> SongBlocklist {
        SongBlocklist(storage: InMemoryBlocklistStorage())
    }

    @Test func blocksTheNamedRequester() async {
        let blocklist = makeBlocklist()
        await blocklist.add(BlocklistItem(value: "noisyviewer", type: .requester))

        #expect(await blocklist.isBlockedRequester("noisyviewer"))
    }

    @Test func matchesRegardlessOfCase() async {
        let blocklist = makeBlocklist()
        await blocklist.add(BlocklistItem(value: "NoisyViewer", type: .requester))

        // Twitch display names carry the user's chosen casing, so a stored
        // "NoisyViewer" has to match a "noisyviewer" arriving from chat.
        #expect(await blocklist.isBlockedRequester("noisyviewer"))
        #expect(await blocklist.isBlockedRequester("NOISYVIEWER"))
    }

    @Test func leavesEveryoneElseAlone() async {
        let blocklist = makeBlocklist()
        await blocklist.add(BlocklistItem(value: "noisyviewer", type: .requester))

        #expect(await blocklist.isBlockedRequester("quietviewer") == false)
        #expect(await blocklist.isBlockedRequester("") == false)
    }

    @Test func aBlockedSongTitleDoesNotBlockAUserOfThatName() async {
        let blocklist = makeBlocklist()
        await blocklist.add(BlocklistItem(value: "sandstorm", type: .song))

        // The two lists share storage but never each other's meaning.
        #expect(await blocklist.isBlockedRequester("sandstorm") == false)
    }

    @Test func aBlockedRequesterDoesNotBlockASongOfThatName() async {
        let blocklist = makeBlocklist()
        await blocklist.add(BlocklistItem(value: "sandstorm", type: .requester))

        #expect(await blocklist.isBlocked(title: "sandstorm", artist: "darude") == false)
        #expect(await blocklist.isBlocked(title: "anything", artist: "sandstorm") == false)
    }

    @Test func theSamePersonIsNotStoredTwice() async {
        let blocklist = makeBlocklist()
        await blocklist.add(BlocklistItem(value: "noisyviewer", type: .requester))
        await blocklist.add(BlocklistItem(value: "NOISYVIEWER", type: .requester))

        #expect(await blocklist.allEntries.count == 1)
    }
}

/// The audience cycle drives a single Stream Deck key, so its order and its
/// wrap-around are behaviour, not an implementation detail.
/// `@MainActor` because the module defaults to it and `RequestAudience` is a
/// production type, not because anything here touches UI.
@Suite("Request audience cycle")
@MainActor
struct RequestAudienceCycleTests {

    @Test func walksLoosestToStrictest() {
        #expect(RequestAudience.everyone.next == .subscribers)
        #expect(RequestAudience.subscribers.next == .vipsAndSubs)
        #expect(RequestAudience.vipsAndSubs.next == .modsOnly)
    }

    @Test func wrapsBackToOpen() {
        #expect(RequestAudience.modsOnly.next == .everyone)
    }

    @Test func visitsEveryAudienceExactlyOncePerLap() {
        var seen: [RequestAudience] = []
        var current = RequestAudience.everyone
        for _ in RequestAudience.allCases {
            seen.append(current)
            current = current.next
        }

        #expect(Set(seen).count == RequestAudience.allCases.count)
        #expect(current == .everyone)
    }
}
