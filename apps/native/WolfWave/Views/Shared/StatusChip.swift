//
//  StatusChip.swift
//  WolfWave
//
//  Created by Nathanial Henniges on 2026-03-27.
//  Copyright © 2026 MrDemonWolf, Inc. All rights reserved.
//

import SwiftUI

/// A capsule-shaped status indicator with a colored dot and label text.
///
/// Used across settings views (Discord, WebSocket, Twitch, etc.) to show
/// connection or server state. Has a modest minimum width so the pill stays
/// stable across short state labels ("Off"/"Live"/"On") without crowding the
/// neighboring Configure affordance in tight rows.
struct StatusChip: View {

    // MARK: - Properties

    let text: String
    let color: Color

    // MARK: - Body

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: DSSpace.s1h) {
            Circle()
                .fill(color)
                .frame(width: 6, height: 6)
                .contentTransition(.interpolate)

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

// MARK: - Previews

#Preview("Live") {
    StatusChip(text: "Live", color: .green)
        .padding()
        .frame(width: 360)
}

#Preview("Off") {
    StatusChip(text: "Off", color: .gray)
        .padding()
        .frame(width: 360)
}

#Preview("Error") {
    StatusChip(text: "Error", color: .red)
        .padding()
        .frame(width: 360)
}
