//
//  StatusChip.swift
//  WolfWave
//
//  Created by Nathanial Henniges on 2026-03-27.
//  Copyright © 2026 MrDemonWolf, Inc. All rights reserved.
//

import SwiftUI

/// A capsule-shaped status indicator with a leading glyph and label text.
///
/// Used across settings views (Discord, WebSocket, Twitch, etc.) to show
/// connection or server state. Has a modest minimum width so the pill stays
/// stable across short state labels ("Off"/"Live"/"On") without crowding the
/// neighboring Configure affordance in tight rows.
///
/// Pass `systemImage` for status chips so the state reads through a shape, not
/// color alone (WCAG 1.4.1). When omitted, the chip falls back to a plain
/// colored dot — fine for non-status category tags where there is no shared
/// icon vocabulary.
struct StatusChip: View {

    // MARK: - Properties

    let text: String
    let color: Color
    /// Optional leading SF Symbol. When set, the symbol replaces the colored
    /// dot so state is conveyed by shape and color together, not color alone.
    var systemImage: String? = nil

    // MARK: - Body

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: DSSpace.s1h) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.system(size: DSFont.Size.sm, weight: .semibold))
                    .foregroundStyle(color)
                    .contentTransition(.symbolEffect(.replace))
                    .accessibilityHidden(true)
            } else {
                Circle()
                    .fill(color)
                    .frame(width: 6, height: 6)
                    .contentTransition(.interpolate)
            }

            Text(text)
                .font(.system(size: DSFont.Size.sm, weight: .semibold))
                .foregroundStyle(.primary)
                .contentTransition(.opacity)
        }
        .frame(minWidth: 88)
        .padding(.horizontal, DSSpace.s3)
        .padding(.vertical, DSSpace.s1)
        .background(color.opacity(0.1))
        .clipShape(Capsule())
        .animation(reduceMotion ? nil : .easeInOut(duration: DSMotion.Duration.base), value: text)
        .animation(reduceMotion ? nil : .easeInOut(duration: DSMotion.Duration.base), value: color)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(text)
        .accessibilityValue(text)
        .accessibilityIdentifier("statusChip.\(text)")
    }
}

// MARK: - Status-State Symbols

extension StatusChip {

    /// Standard leading glyphs so connection state reads through shape as well
    /// as color (WCAG 1.4.1). Reused by the integration dashboard and any pane
    /// that shows an on / off / paused chip.
    enum StateGlyph {
        /// A connected / live / on state. Filled check.
        public static let on = "checkmark.circle.fill"
        /// An off / disconnected state. Hollow circle.
        public static let off = "circle"
        /// A paused-by-system state (e.g. missing permission). Pause glyph.
        public static let paused = "pause.circle.fill"
        /// An error state. Warning triangle.
        public static let error = "exclamationmark.triangle.fill"
        /// A transient starting / connecting state. Ellipsis.
        public static let starting = "ellipsis.circle"
    }
}

// MARK: - Previews

#Preview("Live") {
    StatusChip(text: "Live", color: .green, systemImage: StatusChip.StateGlyph.on)
        .padding()
        .frame(width: 360)
}

#Preview("Off") {
    StatusChip(text: "Off", color: .gray, systemImage: StatusChip.StateGlyph.off)
        .padding()
        .frame(width: 360)
}

#Preview("Error") {
    StatusChip(text: "Error", color: .red, systemImage: StatusChip.StateGlyph.error)
        .padding()
        .frame(width: 360)
}

#Preview("Dot fallback (category tag)") {
    StatusChip(text: "Twitch", color: .purple)
        .padding()
        .frame(width: 360)
}
