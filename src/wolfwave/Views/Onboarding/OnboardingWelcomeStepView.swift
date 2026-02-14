//
//  OnboardingWelcomeStepView.swift
//  wolfwave
//
//  Created by MrDemonWolf, Inc. on 2/6/26.
//

import SwiftUI

/// Welcome step of the onboarding wizard.
///
/// Displays the app icon, tagline, and three feature highlights
/// explaining what WolfWave does. This is the first thing users
/// see on their initial launch.
struct OnboardingWelcomeStepView: View {

    // MARK: - Body

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            // App icon
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .scaledToFit()
                .frame(width: 80, height: 80)
                .accessibilityLabel("WolfWave app icon")

            // Title and tagline
            VStack(spacing: 8) {
                Text("Welcome to WolfWave")
                    .font(.system(size: 24, weight: .bold))

                Text("Bridge Apple Music with Twitch, Discord, and stream overlays")
                    .font(.system(size: 15))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            // Feature highlights
            VStack(alignment: .leading, spacing: 14) {
                featureRow(
                    icon: "music.note",
                    title: "Music Monitoring",
                    description: "Tracks your currently playing song from Apple Music in real time."
                )
                featureRow(
                    icon: "message.fill",
                    color: Color(red: 0.569, green: 0.275, blue: 1.0),  // Twitch #9146FF
                    title: "Twitch Chat Bot",
                    description: "Viewers can use !song and !last commands to see what you're playing."
                )
                featureRow(
                    icon: "gamecontroller.fill",
                    color: Color(red: 0.345, green: 0.396, blue: 0.949),  // Discord #5865F2
                    title: "Discord Rich Presence",
                    description: "Show what you're listening to on your Discord profile with album art."
                )
                featureRow(
                    icon: "rectangle.on.rectangle",
                    title: "Stream Overlays",
                    description: "Stream now-playing data to browser overlays via WebSocket."
                )
                featureRow(
                    icon: "menubar.rectangle",
                    title: "Menu Bar App",
                    description: "Lives in your menu bar for quick access without getting in the way."
                )
            }
            .padding(.horizontal, 32)

            Spacer()
        }
        .padding(.horizontal, 24)
    }

    // MARK: - Helpers

    /// Creates a feature highlight row with an icon, title, and description.
    @ViewBuilder
    private func featureRow(icon: String, color: Color = .accentColor, title: String, description: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 18))
                .foregroundStyle(color)
                .frame(width: 28, alignment: .center)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                Text(description)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

// MARK: - Preview

#Preview {
    OnboardingWelcomeStepView()
        .frame(width: 520, height: 400)
}
