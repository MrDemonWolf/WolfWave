//
//  OnboardingWelcomeStepView.swift
//  wolfwave
//
//  Created by MrDemonWolf, Inc. on 2/6/26.
//

import SwiftUI

/// Welcome step displaying the app icon, tagline, and feature highlights.
struct OnboardingWelcomeStepView: View {

    // MARK: - Body

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .scaledToFit()
                .frame(width: 80, height: 80)
                .accessibilityLabel("WolfWave app icon")

            VStack(spacing: 8) {
                Text("Welcome to WolfWave")
                    .font(.system(size: 24, weight: .bold))

                Text("Bridge Apple Music to your stream")
                    .font(.system(size: 15))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            VStack(alignment: .leading, spacing: 16) {
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
                    title: "Discord Rich Presence",
                    description: "Shows what you're listening to on your Discord profile."
                )
                featureRow(
                    icon: "rectangle.inset.filled.and.person.filled",
                    title: "OBS Stream Widget",
                    description: "Display now-playing info as a browser source overlay on your stream."
                )
            }
            .padding(.horizontal, 32)

            Spacer()
        }
        .padding(.horizontal, 24)
    }

    // MARK: - Helpers

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
