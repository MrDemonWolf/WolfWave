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
                brandFeatureRow(
                    image: "AppleMusicLogo",
                    title: "Music Monitoring",
                    description: "Tracks your currently playing song from Apple Music in real time."
                )
                brandFeatureRow(
                    image: "TwitchLogo",
                    renderOriginal: true,
                    title: "Twitch Chat Bot",
                    description: "Viewers can use !song and !last commands to see what you're playing."
                )
                brandFeatureRow(
                    image: "DiscordLogo",
                    title: "Discord Rich Presence",
                    description: "Shows what you're listening to on your Discord profile."
                )
                brandFeatureRow(
                    image: "OBSLogo",
                    title: "OBS Stream Widget",
                    description: "Display now-playing info as a browser source overlay on your stream."
                )
            }

            Spacer()
        }
        .padding(.horizontal, 24)
    }

    // MARK: - Helpers

    @ViewBuilder
    private func brandFeatureRow(image: String, renderOriginal: Bool = false, color: Color = .accentColor, title: String, description: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(image)
                .renderingMode(renderOriginal ? .original : .template)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 18, height: 18)
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
