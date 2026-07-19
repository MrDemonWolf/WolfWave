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
                BrandTileGlyph.symbol("gearshape.fill", tint: Color.accentColor)
            },
            extras: {
                VStack(spacing: DSSpace.s2) {
                    OnboardingToggleCard(
                        icon: "power",
                        iconColor: .green,
                        title: "Start WolfWave at login",
                        subtitle: "Starts in the menu bar, no Dock icon clutter.",
                        isOn: Binding(
                            get: { launchAtLogin },
                            set: { newValue in
                                // `.requiresApproval` still counts as opted-in; only a
                                // hard `.failure` leaves the toggle where it was.
                                guard LaunchAtLoginService.setEnabled(newValue) != .failure else { return }
                                launchAtLogin = newValue
                            }
                        ),
                        accessibilityLabel: "Start WolfWave at login",
                        accessibilityIdentifier: "onboardingLaunchAtLoginToggle"
                    )

                    OnboardingToggleCard(
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
}

// MARK: - Preview

#Preview {
    OnboardingPreferencesStepView(launchAtLogin: .constant(false))
        .frame(width: 600, height: 480)
}
