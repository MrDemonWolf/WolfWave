//
//  OnboardingPreferencesStepView.swift
//  WolfWave
//
//  Created by Nathanial Henniges on 2026-05-07.
//  Copyright © 2026 MrDemonWolf, Inc. All rights reserved.
//

import AppKit
import SwiftUI

/// Preferences step. Wire up the Mac-level conveniences (launch at login,
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
        OnboardingToggleCard(
            icon: icon,
            iconColor: iconColor,
            title: title,
            subtitle: subtitle,
            isOn: isOn,
            accessibilityLabel: accessibilityLabel,
            accessibilityIdentifier: accessibilityIdentifier
        )
    }
}

// MARK: - Preview

#Preview {
    OnboardingPreferencesStepView(launchAtLogin: .constant(false))
        .frame(width: 600, height: 480)
}
