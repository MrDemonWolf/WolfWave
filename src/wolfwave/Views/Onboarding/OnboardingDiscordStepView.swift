//
//  OnboardingDiscordStepView.swift
//  wolfwave
//
//  Created by MrDemonWolf, Inc. on 2/13/26.
//

import SwiftUI

/// Discord connection step of the onboarding wizard.
///
/// Presents a simple toggle to enable Discord Rich Presence.
/// When enabled, WolfWave shows "Listening to Apple Music" on the
/// user's Discord profile with track, artist, and album info.
///
/// This step is optional — users can skip it from the navigation bar.
struct OnboardingDiscordStepView: View {

    // MARK: - Properties

    /// Binding to the Discord Rich Presence enabled state.
    @Binding var presenceEnabled: Bool

    // MARK: - Body

    var body: some View {
        VStack(spacing: 20) {
            Spacer()

            // Header
            VStack(spacing: 8) {
                Image(systemName: "gamecontroller.fill")
                    .font(.system(size: 36))
                    .foregroundStyle(.indigo)
                    .accessibilityHidden(true)

                Text("Discord Rich Presence")
                    .font(.system(size: 20, weight: .bold))

                Text("Optional — you can set this up later in Settings.")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }

            // Description
            VStack(spacing: 16) {
                Text("Show what you're listening to on your Discord profile, just like Spotify does.")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                // Enable toggle
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Enable Discord Rich Presence")
                            .font(.system(size: 13, weight: .medium))
                        Text("Displays current track on your Discord profile")
                            .font(.system(size: 11))
                            .foregroundStyle(.tertiary)
                    }
                    Spacer()
                    Toggle("", isOn: $presenceEnabled)
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .controlSize(.regular)
                        .pointerCursor()
                        .accessibilityLabel("Enable Discord Rich Presence")
                        .accessibilityIdentifier("onboardingDiscordToggle")
                        .onChange(of: presenceEnabled) { _, newValue in
                            NotificationCenter.default.post(
                                name: NSNotification.Name(AppConstants.Notifications.discordPresenceChanged),
                                object: nil,
                                userInfo: ["enabled": newValue]
                            )
                        }
                }
                .padding(14)
                .background(Color(nsColor: .controlBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 10))

                if presenceEnabled {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 14))
                            .foregroundStyle(.green)
                        Text("Discord Rich Presence enabled!")
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                    }
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
