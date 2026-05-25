//
//  DebugMetricsCard.swift
//  wolfwave
//
//  Created by MrDemonWolf, Inc. on 5/22/26.
//

#if DEBUG
import Combine
import SwiftUI

// MARK: - Debug Metrics Card

/// Debug-tab card showing live runtime metrics from `MetricsService` —
/// WebSocket overlay throughput, Twitch API rate-limit headroom, and memory use.
struct DebugMetricsCard: View {

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
        VStack(alignment: .leading, spacing: DSSpace.s4) {
            VStack(alignment: .leading, spacing: DSSpace.s1) {
                Text("Performance")
                    .font(.system(size: DSFont.Size.base, weight: .semibold))

                Text("Live runtime metrics, refreshed every couple of seconds.")
                    .font(.system(size: DSFont.Size.body))
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
        .onReceive(refreshTimer) { _ in
            snapshot = MetricsService.shared.snapshot()
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
