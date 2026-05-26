//
//  MetricsService.swift
//  WolfWave
//
//  Created by Nathanial Henniges on 2026-05-22.
//  Copyright © 2026 MrDemonWolf, Inc. All rights reserved.
//

import Foundation

// MARK: - Metrics Snapshot

/// A consistent point-in-time capture of runtime performance metrics.
nonisolated struct MetricsSnapshot: Sendable {
    /// Connected overlay (WebSocket) clients.
    let webSocketClients: Int
    /// Total WebSocket frames sent since launch.
    let webSocketMessagesSent: Int
    /// Total WebSocket bytes sent since launch.
    let webSocketBytesSent: Int
    /// WebSocket frames sent per second since the previous snapshot.
    let webSocketMessagesPerSecond: Double
    /// Process resident memory size in bytes.
    let residentMemoryBytes: UInt64
    /// Twitch Helix rate-limit headroom, one entry per observed endpoint.
    let twitchRateLimits: [TwitchRateLimitMetric]
}

/// Rate-limit headroom for a single Twitch Helix endpoint.
nonisolated struct TwitchRateLimitMetric: Sendable, Identifiable {
    /// Helix endpoint key (e.g. `"chat/messages"`).
    let endpoint: String
    /// Requests remaining in the current bucket window.
    let remaining: Int
    /// Bucket size reported by Twitch.
    let limit: Int
    /// Seconds until the bucket window resets.
    let secondsUntilReset: Int

    var id: String { endpoint }
}

// MARK: - Metrics Service

/// Collects lightweight runtime performance metrics — WebSocket throughput,
/// Twitch API rate-limit headroom, and process memory.
///
/// Thread-safe: `record…` methods may be called from any queue (they only
/// touch lock-guarded counters). The UI reads a consistent view via
/// `snapshot()`, which also computes throughput as the message rate since the
/// previous snapshot.
///
/// Use `MetricsService.shared`. The initializer is internal only so tests can
/// construct isolated instances.
nonisolated final class MetricsService: @unchecked Sendable {

    // MARK: - Singleton

    /// Shared instance used across the app.
    nonisolated static let shared = MetricsService()

    // MARK: - Properties

    /// Guards every mutable counter below.
    private let lock = NSLock()

    private var wsClients = 0
    private var wsMessagesSent = 0
    private var wsBytesSent = 0

    /// Message count + timestamp at the previous `snapshot()` — used to derive
    /// the per-second rate.
    private var lastSnapshotMessageCount = 0
    private var lastSnapshotTime = Date()

    private var twitchRateLimits: [String: TwitchRateLimitMetric] = [:]

    // MARK: - Init

    /// Internal so unit tests can create isolated instances; app code uses `shared`.
    init() {}

    // MARK: - Recording

    /// Records one WebSocket frame sent to an overlay client.
    ///
    /// - Parameter byteCount: Serialized frame size in bytes.
    func recordWebSocketMessage(byteCount: Int) {
        lock.withLock {
            wsMessagesSent += 1
            wsBytesSent += byteCount
        }
    }

    /// Records the current connected overlay-client count.
    func recordWebSocketClients(_ count: Int) {
        lock.withLock { wsClients = count }
    }

    /// Records the latest Twitch rate-limit headroom for a Helix endpoint.
    ///
    /// - Parameters:
    ///   - endpoint: Helix endpoint key.
    ///   - remaining: Requests left in the bucket.
    ///   - limit: Bucket size.
    ///   - resetTime: Bucket reset time as a Unix timestamp.
    func recordTwitchRateLimit(endpoint: String, remaining: Int, limit: Int, resetTime: TimeInterval) {
        let secondsLeft = max(0, Int(resetTime - Date().timeIntervalSince1970))
        let metric = TwitchRateLimitMetric(
            endpoint: endpoint,
            remaining: remaining,
            limit: limit,
            secondsUntilReset: secondsLeft
        )
        lock.withLock { twitchRateLimits[endpoint] = metric }
    }

    // MARK: - Snapshot

    /// Captures a consistent snapshot of all metrics.
    ///
    /// WebSocket throughput is the message rate since the previous call, so
    /// `snapshot()` is expected to be invoked on a steady interval.
    func snapshot() -> MetricsSnapshot {
        let memory = Self.residentMemory()
        let now = Date()

        return lock.withLock {
            let elapsed = now.timeIntervalSince(lastSnapshotTime)
            let delta = wsMessagesSent - lastSnapshotMessageCount
            let perSecond = elapsed > 0.01 ? Double(delta) / elapsed : 0

            lastSnapshotMessageCount = wsMessagesSent
            lastSnapshotTime = now

            return MetricsSnapshot(
                webSocketClients: wsClients,
                webSocketMessagesSent: wsMessagesSent,
                webSocketBytesSent: wsBytesSent,
                webSocketMessagesPerSecond: max(0, perSecond),
                residentMemoryBytes: memory,
                twitchRateLimits: twitchRateLimits.values.sorted { $0.endpoint < $1.endpoint }
            )
        }
    }

    // MARK: - Memory

    /// Returns the process's current resident memory size in bytes, or 0 if the
    /// kernel query fails.
    static func residentMemory() -> UInt64 {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(
            MemoryLayout<mach_task_basic_info>.size / MemoryLayout<natural_t>.size
        )
        let result = withUnsafeMutablePointer(to: &info) { infoPtr in
            infoPtr.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { intPtr in
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), intPtr, &count)
            }
        }
        return result == KERN_SUCCESS ? info.resident_size : 0
    }
}
