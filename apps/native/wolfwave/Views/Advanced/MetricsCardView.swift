//
//  MetricsCardView.swift
//  wolfwave
//
//  Created by MrDemonWolf, Inc. on 5/22/26.
//

import Combine
import SwiftUI

// MARK: - Metrics Card View

/// Advanced-settings card showing live runtime metrics from `MetricsService` —
/// WebSocket overlay throughput, Twitch API rate-limit headroom, and memory use.
struct MetricsCardView: View {

    // MARK: - State

    @State private var snapshot = MetricsService.shared.snapshot()

    /// Refreshes the displayed snapshot on a steady interval.
    private let refreshTimer = Timer.publish(every: 2, on: .main, in: .common).autoconnect()

    private static let byteFormatter: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useMB]
        formatter.countStyle = .memory
        return formatter
    }()

    // MARK: - Body

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Performance")
                    .font(.system(size: 13, weight: .semibold))

                Text("Live runtime metrics, refreshed every couple of seconds.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            metricRow(
                "Memory usage",
                Self.byteFormatter.string(fromByteCount: Int64(snapshot.residentMemoryBytes))
            )
            metricRow("Overlay clients", "\(snapshot.webSocketClients)")
            metricRow("Overlay messages sent", "\(snapshot.webSocketMessagesSent)")
            metricRow(
                "Overlay throughput",
                String(format: "%.1f msg/s", snapshot.webSocketMessagesPerSecond)
            )

            if !snapshot.twitchRateLimits.isEmpty {
                Divider()

                Text("Twitch API rate limits")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)

                ForEach(snapshot.twitchRateLimits) { limit in
                    metricRow(
                        limit.endpoint,
                        "\(limit.remaining)/\(limit.limit) · resets in \(limit.secondsUntilReset)s"
                    )
                }
            }
        }
        .cardStyle()
        .onReceive(refreshTimer) { _ in
            snapshot = MetricsService.shared.snapshot()
        }
        .accessibilityIdentifier("performanceMetricsCard")
    }

    // MARK: - Helpers

    private func metricRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .font(.system(size: 12))
            Spacer()
            Text(value)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
        .accessibilityElement(children: .combine)
    }
}
