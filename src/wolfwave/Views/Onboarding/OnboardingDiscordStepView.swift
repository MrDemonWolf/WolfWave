//
//  OnboardingDiscordStepView.swift
//  wolfwave
//
//  Created by MrDemonWolf, Inc. on 2/12/26.
//

import SwiftUI

/// Discord Rich Presence step of the onboarding wizard.
///
/// Shows a visual preview of what the Discord Rich Presence integration
/// looks like on a user's profile, with a toggle to enable it.
///
/// Unlike the Twitch step, no authentication is required — Discord Rich
/// Presence connects automatically via local IPC when Discord is running.
/// This step is optional and can be skipped.
struct OnboardingDiscordStepView: View {

    // MARK: - Settings

    /// Whether Discord Rich Presence is enabled, persisted in UserDefaults.
    @AppStorage(AppConstants.UserDefaults.discordPresenceEnabled)
    private var presenceEnabled = false

    // MARK: - Body

    var body: some View {
        VStack(spacing: 20) {
            Spacer()

            // Header
            VStack(spacing: 8) {
                Image("DiscordLogo")
                    .renderingMode(.original)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 40, height: 40)
                    .accessibilityHidden(true)

                Text("Discord Rich Presence")
                    .font(.system(size: 20, weight: .bold))

                Text("Optional — you can change this later in Settings.")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }

            // Description
            Text("Show what you're listening to on your Discord profile, just like Spotify's listening activity.")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 380)

            // Rich Presence preview mock-up
            richPresencePreview
                .padding(.horizontal, 40)

            // Enable toggle
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Enable Rich Presence")
                        .font(.system(size: 13, weight: .medium))
                    Text("Works automatically when Discord is running")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Toggle("", isOn: $presenceEnabled)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .pointerCursor()
                    .accessibilityLabel("Enable Discord Rich Presence")
                    .onChange(of: presenceEnabled) { _, newValue in
                        NotificationCenter.default.post(
                            name: NSNotification.Name(
                                AppConstants.Notifications.discordPresenceChanged),
                            object: nil,
                            userInfo: ["enabled": newValue]
                        )
                    }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color(nsColor: .controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .padding(.horizontal, 40)

            Spacer()
        }
    }

    // MARK: - Rich Presence Preview

    /// A mock-up of how the Discord profile card looks with Rich Presence active.
    private var richPresencePreview: some View {
        VStack(alignment: .leading, spacing: 0) {
            // "Listening to" header
            Text("LISTENING TO APPLE MUSIC")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.white.opacity(0.7))
                .padding(.bottom, 10)

            HStack(alignment: .top, spacing: 10) {
                // Album art placeholder
                ZStack {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color(red: 0.98, green: 0.25, blue: 0.35),
                                    Color(red: 0.85, green: 0.15, blue: 0.55),
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                    Image(systemName: "music.note")
                        .font(.system(size: 22, weight: .medium))
                        .foregroundStyle(.white.opacity(0.9))
                }
                .frame(width: 56, height: 56)

                // Song info
                VStack(alignment: .leading, spacing: 2) {
                    Text("WolfWave")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)

                    Text("by MrDemonWolf, Inc.")
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.7))
                        .lineLimit(1)

                    Text("on WolfWave")
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.7))
                        .lineLimit(1)

                    // Progress bar mock
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 2)
                                .fill(.white.opacity(0.2))
                                .frame(height: 4)
                            RoundedRectangle(cornerRadius: 2)
                                .fill(.white.opacity(0.8))
                                .frame(width: geo.size.width * 0.45, height: 4)
                        }
                    }
                    .frame(height: 4)
                    .padding(.top, 4)

                    HStack {
                        Text("1:30")
                            .font(.system(size: 9))
                            .foregroundStyle(.white.opacity(0.5))
                        Spacer()
                        Text("3:20")
                            .font(.system(size: 9))
                            .foregroundStyle(.white.opacity(0.5))
                    }
                }
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(red: 0.2, green: 0.21, blue: 0.24))
        )
    }
}

// MARK: - Preview

#Preview {
    OnboardingDiscordStepView()
        .frame(width: 520, height: 500)
}
