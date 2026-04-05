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
/// connection or server state. Has a fixed minimum width so the pill doesn't
/// resize when the text changes between states.
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
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.primary)
        }
        .frame(minWidth: 130)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(color.opacity(0.1))
        .clipShape(Capsule())
        .accessibilityElement(children: .combine)
        .accessibilityLabel(text)
        .accessibilityValue(text)
        .accessibilityIdentifier("statusChip.\(text)")
    }
}
