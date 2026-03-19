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
        VStack(spacing: 16) {
            Spacer()

            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .scaledToFit()
                .frame(width: 64, height: 64)
                .accessibilityLabel("WolfWave app icon")

            VStack(spacing: 8) {
                Text("Welcome to WolfWave")
                    .font(.system(size: 24, weight: .bold))

                Text("Share what you're listening to — everywhere.")
                    .font(.system(size: 15))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            VStack(alignment: .leading, spacing: 18) {
                brandFeatureRow(
                    image: "AppleMusicLogo",
                    title: "Music Monitoring",
                    description: "Automatically detects what's playing in Apple Music."
                )
                brandFeatureRow(
                    image: "TwitchLogo",
                    renderOriginal: true,
                    title: "Twitch Chat Bot",
                    description: "Lets your viewers type !song in chat to see your track."
                )
                brandFeatureRow(
                    image: "DiscordLogo",
                    title: "Discord Rich Presence",
                    description: "Shows your current song on Discord, like Spotify does."
                )
                symbolFeatureRow(
                    systemName: "tv.badge.wifi",
                    title: "Stream Overlay",
                    description: "Puts a now-playing widget on your stream in OBS."
                )
            }

            Spacer()
        }
        .padding(.horizontal, 24)
    }

    // MARK: - Helpers

    @ViewBuilder
    private func symbolFeatureRow(systemName: String, color: Color = .accentColor, title: String, description: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: systemName)
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
