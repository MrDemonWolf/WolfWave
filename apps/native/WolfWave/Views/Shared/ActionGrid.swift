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
/// Wraps `Grid` with shared design-system spacing. Callers lay out their own
/// `GridRow` blocks (see the preview); `columns` only sets the intended width.
/// A single button can span extra columns via `.gridCellColumns(_:)` on
/// `ActionGridButton`.
struct ActionGrid<Content: View>: View {

    // MARK: - Properties

    var columns: Int = 2
    @ViewBuilder var content: () -> Content

    // MARK: - Body

    var body: some View {
        Grid(horizontalSpacing: DSSpace.s2, verticalSpacing: DSSpace.s2) {
            // Layout comes from the caller's `GridRow` blocks; this just owns
            // the shared spacing so every action grid lines up identically.
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
