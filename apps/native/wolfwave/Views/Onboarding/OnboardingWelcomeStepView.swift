//
//  OnboardingWelcomeStepView.swift
//  wolfwave
//
//  Created by MrDemonWolf, Inc. on 2/6/26.
//

import SwiftUI

/// Welcome step displaying the app icon, tagline, and feature highlights.
struct OnboardingWelcomeStepView: View {

    // MARK: - Feature Data

    private struct Feature {
        enum IconType {
            case brand(name: String, renderOriginal: Bool)
            case symbol(name: String)
        }

        let icon: IconType
        let title: String
        let description: String
    }

    private let features: [Feature] = [
        Feature(
            icon: .brand(name: "AppleMusicLogo", renderOriginal: false),
            title: "Music Monitoring",
            description: "Automatically detects what's playing in Apple Music."
        ),
        Feature(
            icon: .brand(name: "TwitchLogo", renderOriginal: true),
            title: "Twitch Chat Bot",
            description: "Anyone in chat can type !song to see what's playing."
        ),
        Feature(
            icon: .brand(name: "DiscordLogo", renderOriginal: false),
            title: "Discord Rich Presence",
            description: "Shows your current song on Discord, like Spotify does."
        ),
        Feature(
            icon: .symbol(name: "tv.badge.wifi"),
            title: "Now-Playing Widget",
            description: "Adds a customizable now-playing widget for OBS or any browser."
        ),
    ]

    // MARK: - Animation State

    @State private var rowsVisible = false

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
                ForEach(Array(features.enumerated()), id: \.offset) { index, feature in
                    featureRow(for: feature)
                        .opacity(rowsVisible ? 1 : 0)
                        .offset(x: rowsVisible ? 0 : 20)
                        .animation(
                            .spring(response: 0.4, dampingFraction: 0.8)
                                .delay(Double(index) * 0.08),
                            value: rowsVisible
                        )
                }
            }

            Spacer()
        }
        .padding(.horizontal, 24)
        .onAppear {
            rowsVisible = true
        }
    }

    // MARK: - Helpers

    @ViewBuilder
    private func featureRow(for feature: Feature) -> some View {
        switch feature.icon {
        case let .brand(name, renderOriginal):
            brandFeatureRow(
                image: name,
                renderOriginal: renderOriginal,
                title: feature.title,
                description: feature.description
            )
        case let .symbol(name):
            symbolFeatureRow(
                systemName: name,
                title: feature.title,
                description: feature.description
            )
        }
    }

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
