//
//  ResponsiveRow.swift
//  WolfWave
//
//  Created by Nathanial Henniges on 2026-06-03.
//  Copyright © 2026 MrDemonWolf, Inc. All rights reserved.
//

import SwiftUI

/// Two views placed side by side that collapse to a vertical stack when the
/// container is narrower than `floor`.
///
/// Used by the History & Stats dashboard to pair cards (summary + today's top
/// track, the two charts, retention + actions) into two columns on a wide
/// settings window while stacking them on a narrow one.
///
/// The wide (`HStack`) candidate declares a `minWidth` floor so `ViewThatFits`
/// only selects it when the pane is genuinely wide enough. Without that floor,
/// flexible `maxWidth: .infinity` children report as "fitting" at any width and
/// the layout would never collapse to a single column.
///
/// Both children are stretched to the row's height in the wide layout so paired
/// cards read as one band rather than two ragged-bottomed boxes.
struct ResponsiveRow<Left: View, Right: View>: View {

    // MARK: - Properties

    /// Minimum container width that justifies two columns. Defaults to the
    /// History & Stats dashboard floor (two ~300pt columns + the section gutter).
    let floor: CGFloat

    /// Gap between the two columns, and between the stacked views when collapsed.
    let spacing: CGFloat

    private let left: () -> Left
    private let right: () -> Right

    // MARK: - Init

    init(
        floor: CGFloat = DSDimension.HistoryStats.twoColumnFloor,
        spacing: CGFloat = AppConstants.SettingsUI.sectionSpacing,
        @ViewBuilder left: @escaping () -> Left,
        @ViewBuilder right: @escaping () -> Right
    ) {
        self.floor = floor
        self.spacing = spacing
        self.left = left
        self.right = right
    }

    // MARK: - Body

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: spacing) {
                left().frame(maxWidth: .infinity, maxHeight: .infinity)
                right().frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(minWidth: floor)

            VStack(spacing: spacing) {
                left()
                right()
            }
        }
    }
}

// MARK: - Preview

#Preview("Wide vs narrow") {
    VStack(spacing: DSSpace.s8) {
        ResponsiveRow {
            RoundedRectangle(cornerRadius: 12).fill(.blue.opacity(0.2)).frame(height: 80)
                .overlay(Text("Left"))
        } right: {
            RoundedRectangle(cornerRadius: 12).fill(.green.opacity(0.2)).frame(height: 80)
                .overlay(Text("Right"))
        }
    }
    .padding()
    .frame(width: 720)
}
