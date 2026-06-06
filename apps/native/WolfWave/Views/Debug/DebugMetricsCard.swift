//
//  DebugMetricsCard.swift
//  WolfWave
//
//  Created by Nathanial Henniges on 2026-05-22.
//  Copyright © 2026 MrDemonWolf, Inc. All rights reserved.
//

#if DEBUG
import SwiftUI

// MARK: - Debug Metrics Card

/// Debug-tab card showing live runtime metrics from `MetricsService`:
/// WebSocket overlay throughput, Twitch API rate-limit headroom, and memory use.
struct DebugMetricsCard: View {

    // MARK: - State

    @State private var snapshot = MetricsService.shared.snapshot()

    /// Interval between metric snapshots while the card is on-screen.
    private static let refreshInterval: Duration = .seconds(2)

    // MARK: - Body

    var body: some View {
        VStack(alignment: .leading, spacing: DSSpace.s4) {
            Text("Live runtime metrics, refreshed every couple of seconds.")
                .font(.system(size: DSFont.Size.body))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            metricRow(
                "Memory usage",
                ByteFormatting.memory(Int64(snapshot.residentMemoryBytes))
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
                    .font(.system(size: DSFont.Size.body, weight: .medium))
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
        .task {
            // Driven by structured concurrency so the loop cancels when the
            // card disappears, no Combine subscription to clean up.
            while !Task.isCancelled {
                snapshot = MetricsService.shared.snapshot()
                try? await Task.sleep(for: Self.refreshInterval)
            }
        }
        .accessibilityIdentifier("performanceMetricsCard")
    }

    // MARK: - Helpers

    private func metricRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .font(.system(size: DSFont.Size.body))
            Spacer()
            Text(value)
                .font(.system(size: DSFont.Size.body, weight: .medium))
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Previews

#Preview {
    DebugMetricsCard()
        .padding()
        .frame(width: 600)
}
#endif
