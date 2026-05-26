//
//  WarningBanner.swift
//  WolfWave
//
//  Created by Nathanial Henniges on 2026-05-26.
//  Copyright © 2026 MrDemonWolf, Inc. All rights reserved.
//

import SwiftUI

/// Inline tinted banner used to flag a warning, caution, or error condition
/// inside settings panes.
///
/// Replaces hand-rolled `HStack { exclamationmark.triangle.fill + Text }` +
/// tinted background + rounded clip patterns that had drifted across the
/// codebase. Tint is configurable so the same chrome serves both informational
/// orange callouts and destructive red banners. When `strokeVisible` is true,
/// a 1pt stroke at 25% tint is overlaid — used in the Debug pane to highlight
/// developer-only tooling.
struct WarningBanner: View {

    // MARK: - Properties

    let text: String
    var systemImage: String = "exclamationmark.triangle.fill"
    var tint: Color = .orange
    var strokeVisible: Bool = false

    // MARK: - Body

    var body: some View {
        HStack(alignment: .top, spacing: DSSpace.s2) {
            Image(systemName: systemImage)
                .foregroundStyle(tint)
                .accessibilityHidden(true)
            Text(text)
                .font(.system(size: DSFont.Size.body))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, DSSpace.s4)
        .padding(.vertical, DSSpace.s2)
        .background(tint.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: AppConstants.SettingsUI.cardCornerRadius))
        .overlay {
            if strokeVisible {
                RoundedRectangle(cornerRadius: AppConstants.SettingsUI.cardCornerRadius)
                    .stroke(tint.opacity(0.25), lineWidth: 1)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(text)
    }
}

// MARK: - Preview

#Preview {
    VStack(spacing: DSSpace.s4) {
        WarningBanner(text: "These tools mutate live state. Use at your own risk.", strokeVisible: true)
        WarningBanner(text: "Twitch token expired — sign in again to keep chat replies working.")
        WarningBanner(text: "Deleting the queue cannot be undone.", tint: .red)
    }
    .padding()
    .frame(width: 480)
}
