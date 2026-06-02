//
//  OnboardingPreferencesStepView.swift
//  WolfWave
//
//  Created by Nathanial Henniges on 2026-05-07.
//  Copyright © 2026 MrDemonWolf, Inc. All rights reserved.
//

import AppKit
import SwiftUI

/// Preferences step — wire up the Mac-level conveniences (launch at login,
/// listening history) so the user doesn't have to hunt for them in Settings
/// later. Permissions (Apple Music, notifications) live in the next step.
struct OnboardingPreferencesStepView: View {

    // MARK: - Properties

    @Binding var launchAtLogin: Bool

    @AppStorage(AppConstants.UserDefaults.listeningHistoryEnabled)
    private var listeningHistoryEnabled = false

    // MARK: - Body

    var body: some View {
        OnboardingStepScaffold(
            title: "A couple Mac settings",
            description: "Start WolfWave at login and choose whether to remember your listening history.",
            icon: {
                BrandTile(
                    background: AnyShapeStyle(
                        LinearGradient(
                            colors: [Color.accentColor, Color.accentColor.opacity(0.75)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    ),
                    glowColor: Color.accentColor,
                    glyph:
                        Image(systemName: "gearshape.fill")
                            .font(.system(size: DSFont.Size.x26, weight: .semibold))
                            .foregroundStyle(.white)
                )
            },
            extras: {
                VStack(spacing: DSSpace.s2) {
                    preferenceRow(
                        icon: "power",
                        iconColor: .green,
                        title: "Start WolfWave at login",
                        subtitle: "Starts in the menu bar, no Dock icon clutter.",
                        isOn: Binding(
                            get: { launchAtLogin },
                            set: { newValue in
                                guard LaunchAtLoginService.setEnabled(newValue) else { return }
                                launchAtLogin = newValue
                            }
                        ),
                        accessibilityLabel: "Start WolfWave at login",
                        accessibilityIdentifier: "onboardingLaunchAtLoginToggle"
                    )

                    preferenceRow(
                        icon: "chart.bar.xaxis",
                        iconColor: .purple,
                        title: "Remember my listening history",
                        subtitle: "Private & on-device. Powers top artists and stats.",
                        isOn: Binding(
                            get: { listeningHistoryEnabled },
                            set: { newValue in
                                listeningHistoryEnabled = newValue
                                NotificationCenter.default.postEnabled(
                                    .listeningHistorySettingChanged, enabled: newValue)
                            }
                        ),
                        accessibilityLabel: "Remember my listening history",
                        accessibilityIdentifier: "onboardingListeningHistoryToggle"
                    )
                }
            }
        )
    }

    // MARK: - Row

    /// Builds a single labeled toggle row used in the preferences step:
    /// colored icon tile, title, subtitle, and a binding switch.
    ///
    /// - Parameters:
    ///   - icon: SF Symbol name shown in the colored tile.
    ///   - iconColor: Accent color for the tile background and glyph.
    ///   - title: Primary row title.
    ///   - subtitle: Supporting copy under the title.
    ///   - isOn: Two-way binding to the underlying boolean preference.
    ///   - accessibilityLabel: VoiceOver label for the toggle.
    ///   - accessibilityIdentifier: UI-testing identifier for the toggle.
    /// - Returns: A styled preference row.
    @ViewBuilder
    private func preferenceRow(
        icon: String,
        iconColor: Color,
        title: String,
        subtitle: String,
        isOn: Binding<Bool>,
        accessibilityLabel: String,
        accessibilityIdentifier: String
    ) -> some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(iconColor.opacity(0.15))
                    .frame(width: 28, height: 28)

                Image(systemName: icon)
                    .font(.system(size: DSFont.Size.base, weight: .semibold))
                    .foregroundStyle(iconColor)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: DSFont.Size.base, weight: .semibold))

                Text(subtitle)
                    .font(.system(size: DSFont.Size.sm))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()

            Toggle("", isOn: isOn)
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
    OnboardingPreferencesStepView(launchAtLogin: .constant(false))
        .frame(width: 600, height: 480)
}
