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

    @Test("Retry-After delta is preferred and parsed as seconds")
    func testRetryAfterPreferred() {
        let now: TimeInterval = 1_000
        // Ratelimit-Reset would yield 30s; Retry-After (10) must win.
        let headers: [AnyHashable: Any] = [
            "Retry-After": "10",
            "Ratelimit-Reset": "1030",
        ]
        let wait = RateLimiter.retryWaitSeconds(from: headers, now: now)
        #expect(wait == 10)
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
}
