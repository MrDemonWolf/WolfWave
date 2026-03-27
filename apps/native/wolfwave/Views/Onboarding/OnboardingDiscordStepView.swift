//
//  OnboardingDiscordStepView.swift
//  wolfwave
//
//  Created by MrDemonWolf, Inc. on 2/13/26.
//

import SwiftUI

/// Optional onboarding step to enable Discord Rich Presence.
struct OnboardingDiscordStepView: View {

    // MARK: - Properties

    @Binding var presenceEnabled: Bool

    // MARK: - Body

    var body: some View {
        VStack(spacing: 20) {
            Spacer()

            VStack(spacing: 8) {
                Image("DiscordLogo")
                    .renderingMode(.template)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 36, height: 36)
                    .foregroundStyle(.indigo)
                    .accessibilityHidden(true)

                Text("Discord Status")
                    .font(.system(size: 20, weight: .bold))

                Text("Totally optional. You can always do this later.")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }

            VStack(spacing: 16) {
                Text("Your Discord status will show what song you're listening to — just like Spotify.")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                ToggleSettingRow(
                    title: "Show music on Discord",
                    subtitle: "Updates your Discord status with the current song",
                    isOn: $presenceEnabled,
                    controlSize: .regular,
                    accessibilityLabel: "Enable Discord Status",
                    accessibilityIdentifier: "onboardingDiscordToggle",
                    onChange: { newValue in
                        NotificationCenter.default.post(
                            name: NSNotification.Name(AppConstants.Notifications.discordPresenceChanged),
                            object: nil,
                            userInfo: ["enabled": newValue]
                        )
                    }
                )
                .cardStyle()

                if presenceEnabled {
                    SuccessFeedbackRow(text: "Discord Status enabled!")
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
            .frame(maxWidth: 400)
            .padding(.horizontal, 24)
            .animation(.easeInOut(duration: 0.2), value: presenceEnabled)

            Spacer()
        }
    }
}

// MARK: - Preview

#Preview {
    OnboardingDiscordStepView(presenceEnabled: .constant(false))
        .frame(width: 520, height: 400)
}
