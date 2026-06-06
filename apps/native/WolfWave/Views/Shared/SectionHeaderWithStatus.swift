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

    // MARK: - Prominence

    /// Which heading level this header renders at.
    ///
    /// `.pane` is the H1 at the top of a settings pane (22pt via `.paneTitle()`).
    /// `.section` is an H2 for a sub-section inside a pane (17pt via
    /// `.sectionHeader()`), so a pane that hosts both a title and sub-sections
    /// keeps a clear two-step hierarchy instead of two near-identical headings.
    enum Prominence {
        case pane
        case section
    }

    // MARK: - Properties

    let title: String
    let subtitle: String
    var prominence: Prominence = .pane
    var statusText: String? = nil
    var statusColor: Color? = nil
    /// Optional leading SF Symbol for the status chip, so state is not conveyed
    /// by color alone. Passed straight through to `StatusChip`.
    var statusSymbol: String? = nil

    // MARK: - Body

    var body: some View {
        VStack(alignment: .leading, spacing: DSSpace.s1h) {
            HStack(alignment: .center, spacing: DSSpace.s3) {
                titleText

                if let statusText, let statusColor {
                    Spacer()

                    StatusChip(text: statusText, color: statusColor, systemImage: statusSymbol)
                        .accessibilityLabel("\(title) status: \(statusText)")
                }
            }

            Text(subtitle)
                .fieldSubtitle()
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: - Title

    @ViewBuilder
    private var titleText: some View {
        switch prominence {
        case .pane:
            Text(title).paneTitle()
        case .section:
            Text(title).sectionHeader()
        }
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
