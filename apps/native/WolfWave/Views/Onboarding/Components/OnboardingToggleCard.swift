//
//  OnboardingToggleCard.swift
//  WolfWave
//
//  Created by Nathanial Henniges on 2026-06-04.
//  Copyright © 2026 MrDemonWolf, Inc. All rights reserved.
//

import SwiftUI

/// Onboarding toggle row: a tinted SF Symbol tile, a title + subtitle, and a
/// trailing switch inside a bordered card.
///
/// Shared by the Preferences and Notifications onboarding steps, which had
/// byte-identical private copies of this layout. Lives in `Onboarding/Components`
/// because it carries the onboarding design language (its own tile radius), not
/// the settings-pane look.
struct OnboardingToggleCard: View {

    // MARK: - Properties

    let icon: String
    let iconColor: Color
    let title: String
    let subtitle: String
    @Binding var isOn: Bool
    let accessibilityLabel: String
    let accessibilityIdentifier: String

    // MARK: - Body

    var body: some View {
        HStack(spacing: DSSpace.s4) {
            ZStack {
                RoundedRectangle(cornerRadius: AppConstants.OnboardingUI.iconTileRadius, style: .continuous)
                    .fill(iconColor.opacity(0.15))
                    .frame(
                        width: AppConstants.OnboardingUI.iconTileSize,
                        height: AppConstants.OnboardingUI.iconTileSize
                    )

                Image(systemName: icon)
                    .font(.system(size: DSFont.Size.base, weight: .semibold))
                    .foregroundStyle(iconColor)
            }

            VStack(alignment: .leading, spacing: DSSpace.s0) {
                Text(title)
                    .font(.system(size: DSFont.Size.base, weight: .semibold))

                Text(subtitle)
                    .font(.system(size: DSFont.Size.sm))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()

            Toggle("", isOn: $isOn)
                .toggleStyle(.switch)
                .labelsHidden()
                .pointerCursor()
                .accessibilityLabel(accessibilityLabel)
                .accessibilityIdentifier(accessibilityIdentifier)
        }
        .padding(DSSpace.s4)
        .background(
            RoundedRectangle(cornerRadius: DSRadius.lg2, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: DSRadius.lg2, style: .continuous)
                .stroke(Color.primary.opacity(0.06), lineWidth: 0.5)
        )
    }
}

// MARK: - Preview

#Preview {
    VStack(spacing: DSSpace.s3) {
        OnboardingToggleCard(
            icon: "bell.badge",
            iconColor: .orange,
            title: "Song change alerts",
            subtitle: "A banner when the track changes.",
            isOn: .constant(true),
            accessibilityLabel: "Song change alerts",
            accessibilityIdentifier: "onboarding.toggle.songChange"
        )
        OnboardingToggleCard(
            icon: "power",
            iconColor: .blue,
            title: "Launch at login",
            subtitle: "Start WolfWave when you sign in.",
            isOn: .constant(false),
            accessibilityLabel: "Launch at login",
            accessibilityIdentifier: "onboarding.toggle.launch"
        )
    }
    .padding()
    .frame(width: 420)
}
