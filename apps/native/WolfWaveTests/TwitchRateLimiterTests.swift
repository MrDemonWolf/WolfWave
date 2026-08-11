//
//  TwitchRateLimiterTests.swift
//  WolfWave
//
//  Created by Nathanial Henniges on 2026-06-06.
//  Copyright © 2026 MrDemonWolf, Inc. All rights reserved.
//

import Testing
import Foundation
@testable import WolfWave

/// Covers the `TwitchChatService.RateLimiter` reactive-429 plumbing: the
/// nonisolated header-parse helper and the explicit reset-honoring backoff.
@Suite("Twitch RateLimiter Tests")
struct TwitchRateLimiterTests {

    private typealias RateLimiter = TwitchChatService.RateLimiter

    // MARK: - retryWaitSeconds header parsing

    @Test("The later Retry-After or reset signal wins")
    func testLaterServerSignalWins() {
        let now: TimeInterval = 1_000
        let headers: [AnyHashable: Any] = [
            "Retry-After": "10",
            "Ratelimit-Reset": "1030",
        ]
        let wait = RateLimiter.retryWaitSeconds(from: headers, now: now)
        #expect(wait == 30)

        let laterRetryAfter: [AnyHashable: Any] = [
            "Retry-After": "40",
            "Ratelimit-Reset": "1030",
        ]
        #expect(RateLimiter.retryWaitSeconds(
            from: laterRetryAfter, now: now) == 40)
    }

    @Test("Ratelimit-Reset epoch is converted to a delta when Retry-After is absent")
    func testRatelimitResetDelta() {
        let now: TimeInterval = 1_000
        let headers: [AnyHashable: Any] = ["Ratelimit-Reset": "1042"]
        let wait = RateLimiter.retryWaitSeconds(from: headers, now: now)
        #expect(wait == 42)
    }

    @Test("Header lookup is case-insensitive")
    func testCaseInsensitiveHeaderLookup() {
        let now: TimeInterval = 0
        let headers: [AnyHashable: Any] = ["retry-after": "7"]
        let wait = RateLimiter.retryWaitSeconds(from: headers, now: now)
        #expect(wait == 7)
    }

    @Test("A reset already in the past clamps to zero, never negative")
    func testPastResetClampsToZero() {
        let now: TimeInterval = 2_000
        let headers: [AnyHashable: Any] = ["Ratelimit-Reset": "1000"]
        let wait = RateLimiter.retryWaitSeconds(from: headers, now: now)
        #expect(wait == 0)
    }

    @Test("Missing or unparseable headers return nil")
    func testMissingHeadersReturnNil() {
        let now: TimeInterval = 100
        #expect(RateLimiter.retryWaitSeconds(from: [:], now: now) == nil)
        #expect(
            RateLimiter.retryWaitSeconds(
                from: ["Retry-After": "not-a-number"], now: now) == nil)
    }

    @Test("Retry-After rejects non-finite and negative values and caps huge waits")
    func testRetryAfterBounds() {
        let now: TimeInterval = 1_000
        #expect(RateLimiter.retryWaitSeconds(
            from: ["Retry-After": "1e309"], now: now) == nil)
        #expect(RateLimiter.retryWaitSeconds(
            from: ["Retry-After": "nan"], now: now) == nil)
        #expect(RateLimiter.retryWaitSeconds(
            from: ["Retry-After": "-1"], now: now) == nil)
        #expect(RateLimiter.retryWaitSeconds(
            from: ["Retry-After": "1e308"], now: now) == 300)
    }

    @Test("Ratelimit-Reset rejects non-finite values and caps huge waits")
    func testRatelimitResetBounds() {
        let now: TimeInterval = 1_000
        #expect(RateLimiter.retryWaitSeconds(
            from: ["Ratelimit-Reset": "1e309"], now: now) == nil)
        #expect(RateLimiter.retryWaitSeconds(
            from: ["Ratelimit-Reset": "nan"], now: now) == nil)
        #expect(RateLimiter.retryWaitSeconds(
            from: ["Ratelimit-Reset": "1e308"], now: now) == 300)
    }

    // MARK: - noteRateLimited honored by waitTimeIfRateLimited

    @Test("noteRateLimited marks the endpoint saturated until the reset epoch")
    func testNoteRateLimitedHonored() async {
        let limiter = RateLimiter()
        let endpoint = "/chat/messages"
        let now = Date().timeIntervalSince1970

        // Not saturated initially.
        #expect(await limiter.waitTimeIfRateLimited(endpoint: endpoint) == nil)

        // Mark saturated for ~5s into the future.
        await limiter.noteRateLimited(endpoint: endpoint, untilEpoch: now + 5)
        let wait = await limiter.waitTimeIfRateLimited(endpoint: endpoint)
        #expect(wait != nil)
        #expect((wait ?? 0) > 0)
        #expect((wait ?? 99) <= 5)
    }

    @Test("A reset already elapsed leaves the endpoint with capacity")
    func testNoteRateLimitedPastResetHasCapacity() async {
        let limiter = RateLimiter()
        let endpoint = "/streams"
        let now = Date().timeIntervalSince1970

        await limiter.noteRateLimited(endpoint: endpoint, untilEpoch: now - 5)
        #expect(await limiter.waitTimeIfRateLimited(endpoint: endpoint) == nil)
    }

    @Test("noteRateLimited rejects non-finite resets and caps huge epochs")
    func testNoteRateLimitedBounds() async {
        let limiter = RateLimiter()
        let endpoint = "/chat/messages"

        await limiter.noteRateLimited(endpoint: endpoint, untilEpoch: .infinity)
        #expect(await limiter.waitTimeIfRateLimited(endpoint: endpoint) == nil)

        await limiter.noteRateLimited(endpoint: endpoint, untilEpoch: 1e308)
        let wait = await limiter.waitTimeIfRateLimited(endpoint: endpoint)
        #expect((wait ?? 0) > 0)
        #expect((wait ?? 301) <= 300)
    }

    @Test("Cancelling a capacity wait propagates CancellationError")
    func testCapacityWaitPropagatesCancellation() async {
        let limiter = RateLimiter()
        let endpoint = "/chat/messages"
        await limiter.noteRateLimited(
            endpoint: endpoint,
            untilEpoch: Date().timeIntervalSince1970 + 60)

        let wait = Task {
            do {
                try await limiter.awaitCapacity(endpoint: endpoint)
                return false
            } catch is CancellationError {
                return true
            } catch {
                return false
            }
        }
        wait.cancel()
        let wasCancelled = await wait.value
        #expect(wasCancelled)
    }
}
