//
//  SectionHeaderWithStatus.swift
//  wolfwave
//
//  Created by MrDemonWolf, Inc. on 4/4/26.
//

import SwiftUI

/// A reusable section header with title, subtitle, and an optional status chip.
///
/// Used across settings views (Discord, Twitch, WebSocket) for a consistent
/// top-level section layout. When no status is provided, the chip is omitted
/// and the header renders as a simple title + subtitle pair.
///
/// Usage:
/// ```swift
/// SectionHeaderWithStatus(
///     title: "Discord Status",
///     subtitle: "Show your music on your Discord profile.",
///     statusText: "Connected",
///     statusColor: .green
/// )
/// ```
struct SectionHeaderWithStatus: View {

    // MARK: - Properties

    let title: String
    let subtitle: String
    var statusText: String? = nil
    var statusColor: Color? = nil

    // MARK: - Body

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .center, spacing: 10) {
                Text(title)
                    .sectionHeader()

                if let statusText, let statusColor {
                    Spacer()

                    StatusChip(text: statusText, color: statusColor)
                        .accessibilityLabel("\(title) status: \(statusText)")
                        .animation(.easeInOut(duration: 0.2), value: statusText)
                }
            }

            Text(subtitle)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }
}
