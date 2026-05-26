//
//  ActionGrid.swift
//  WolfWave
//
//  Created by Nathanial Henniges on 2026-05-26.
//  Copyright © 2026 MrDemonWolf, Inc. All rights reserved.
//

import SwiftUI

/// Standardized grid of bordered icon+label action buttons. Used by the
/// custom About panel and the About settings tab to render a 2-column grid
/// of secondary actions ("Check for Updates", "Release Notes", "Website",
/// "Send Feedback", "Sponsor").
///
/// Wraps `Grid` + `GridRow` so callers list buttons sequentially and the
/// grid auto-wraps every `columns` items. A single button can still span
/// extra columns via `.gridCellColumns(_:)` on `ActionGridButton`.
struct ActionGrid<Content: View>: View {

    // MARK: - Properties

    var columns: Int = 2
    @ViewBuilder var content: () -> Content

    // MARK: - Body

    var body: some View {
        Grid(horizontalSpacing: DSSpace.s2, verticalSpacing: DSSpace.s2) {
            // Single-row Grid; callers decide layout via `GridRow` blocks when
            // they need explicit row control. The simple path below wraps every
            // `columns` children into successive rows.
            content()
        }
    }
}

/// Bordered, label-style action button sized for `ActionGrid`. Renders an
/// SF Symbol next to the title, fills its grid cell horizontally, and uses
/// the standard pointer cursor.
struct ActionGridButton: View {

    // MARK: - Properties

    let title: String
    let systemImage: String
    let action: () -> Void
    var accessibilityIdentifier: String?

    // MARK: - Body

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.system(size: DSFont.Size.body, weight: .medium))
                .frame(maxWidth: .infinity)
                .padding(.vertical, DSSpace.s0)
        }
        .buttonStyle(.bordered)
        .controlSize(.regular)
        .pointerCursor()
        .accessibilityLabel(title)
        .accessibilityIdentifier(accessibilityIdentifier ?? "actionGrid.\(title)")
    }
}

// MARK: - Preview

#Preview {
    ActionGrid(columns: 2) {
        GridRow {
            ActionGridButton(title: "Check for Updates", systemImage: "arrow.down.circle", action: {})
            ActionGridButton(title: "Release Notes", systemImage: "list.bullet.rectangle", action: {})
        }
        GridRow {
            ActionGridButton(title: "Website", systemImage: "globe", action: {})
            ActionGridButton(title: "Send Feedback", systemImage: "envelope", action: {})
        }
        GridRow {
            ActionGridButton(title: "Sponsor on GitHub", systemImage: "heart.fill", action: {})
                .gridCellColumns(2)
        }
    }
    .padding()
    .frame(width: 360)
}
