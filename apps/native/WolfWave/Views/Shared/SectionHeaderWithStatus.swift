//
//  SectionHeaderWithStatus.swift
//  WolfWave
//
//  Created by Nathanial Henniges on 2026-04-04.
//  Copyright © 2026 MrDemonWolf, Inc. All rights reserved.
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
        VStack(alignment: .leading, spacing: DSSpace.s1h) {
            HStack(alignment: .center, spacing: DSSpace.s3) {
                Text(title)
                    .sectionHeader()

                if let statusText, let statusColor {
                    Spacer()

                    StatusChip(text: statusText, color: statusColor)
                        .accessibilityLabel("\(title) status: \(statusText)")
                        .animation(.easeInOut(duration: DSMotion.Duration.base), value: statusText)
                }
            }

            Text(subtitle)
                .font(.system(size: DSFont.Size.base))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Previews

#Preview("With status") {
    SectionHeaderWithStatus(
        title: "Discord Status",
        subtitle: "Show your music on your Discord profile.",
        statusText: "Connected",
        statusColor: .green
    )
    .padding()
    .frame(width: 480)
}

#Preview("Without status") {
    SectionHeaderWithStatus(
        title: "About WolfWave",
        subtitle: "Native macOS menu bar app for Apple Music streamers."
    )
    .padding()
    .frame(width: 480)
}
