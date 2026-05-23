//
//  MetricsServiceTests.swift
//  WolfWaveTests
//
//  Created by MrDemonWolf, Inc. on 5/22/26.
//

import XCTest

@testable import WolfWave

// MARK: - MetricsServiceTests

/// Covers `MetricsService` recording and snapshot logic. Each test uses an
/// isolated instance (the internal initializer) rather than `.shared`.
final class MetricsServiceTests: XCTestCase {

    private var service: MetricsService!

    override func setUp() {
        super.setUp()
        service = MetricsService()
    }

    override func tearDown() {
        service = nil
        super.tearDown()
    }

    // MARK: - WebSocket

    func testWebSocketMessageRecordingAccumulates() {
        service.recordWebSocketMessage(byteCount: 100)
        service.recordWebSocketMessage(byteCount: 250)

        let snapshot = service.snapshot()
        XCTAssertEqual(snapshot.webSocketMessagesSent, 2)
        XCTAssertEqual(snapshot.webSocketBytesSent, 350)
    }

    func testWebSocketClientCountReflectsLatestValue() {
        service.recordWebSocketClients(3)
        XCTAssertEqual(service.snapshot().webSocketClients, 3)

        service.recordWebSocketClients(1)
        XCTAssertEqual(service.snapshot().webSocketClients, 1)
    }

    func testThroughputIsNonNegative() {
        _ = service.snapshot()  // Establish the baseline window.
        service.recordWebSocketMessage(byteCount: 10)
        service.recordWebSocketMessage(byteCount: 10)

        XCTAssertGreaterThanOrEqual(service.snapshot().webSocketMessagesPerSecond, 0)
    }

    // MARK: - Twitch Rate Limits

    func testTwitchRateLimitStoredAndSortedByEndpoint() {
        let future = Date().timeIntervalSince1970 + 60
        service.recordTwitchRateLimit(endpoint: "users", remaining: 700, limit: 800, resetTime: future)
        service.recordTwitchRateLimit(endpoint: "chat/messages", remaining: 95, limit: 100, resetTime: future)

        let limits = service.snapshot().twitchRateLimits
        XCTAssertEqual(limits.map(\.endpoint), ["chat/messages", "users"])
        XCTAssertEqual(limits.first?.remaining, 95)
        XCTAssertEqual(limits.first?.limit, 100)
        XCTAssertGreaterThan(limits.first?.secondsUntilReset ?? 0, 0)
    }

    func testTwitchRateLimitLatestRecordWins() {
        let future = Date().timeIntervalSince1970 + 60
        service.recordTwitchRateLimit(endpoint: "chat/messages", remaining: 95, limit: 100, resetTime: future)
        service.recordTwitchRateLimit(endpoint: "chat/messages", remaining: 40, limit: 100, resetTime: future)

        let limits = service.snapshot().twitchRateLimits
        XCTAssertEqual(limits.count, 1)
        XCTAssertEqual(limits.first?.remaining, 40)
    }

    func testRateLimitResetClampsToZeroWhenInPast() {
        let past = Date().timeIntervalSince1970 - 60
        service.recordTwitchRateLimit(endpoint: "users", remaining: 0, limit: 800, resetTime: past)

        XCTAssertEqual(service.snapshot().twitchRateLimits.first?.secondsUntilReset, 0)
    }

    // MARK: - Memory

    func testResidentMemoryIsPositive() {
        // The running test process always has a non-zero resident size.
        XCTAssertGreaterThan(MetricsService.residentMemory(), 0)
    }
}
