//
//  StatusChip.swift
//  wolfwave
//
//  Created by MrDemonWolf, Inc. on 3/20/26.
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

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(color)
                .frame(width: 6, height: 6)

            Text(text)
                .font(.system(size: DSFont.Size.sm, weight: .semibold))
                .foregroundStyle(.primary)
        }
        .frame(minWidth: 88)
        .padding(.horizontal, DSSpace.s3)
        .padding(.vertical, DSSpace.s1)
        .background(color.opacity(0.1))
        .clipShape(Capsule())
        .accessibilityElement(children: .combine)
        .accessibilityLabel(text)
        .accessibilityValue(text)
        .accessibilityIdentifier("statusChip.\(text)")
    }
}
