//
//  WhatsNewView.swift
//  WolfWave
//
//  Created by Nathanial Henniges on 2026-03-30.
//  Copyright © 2026 MrDemonWolf, Inc. All rights reserved.
//

/// Displays a "What's New" sheet highlighting key features introduced in this version.
///
/// Shown once per version after the user has completed onboarding. Each feature is
/// displayed as a card-styled row with an SF Symbol icon, title, and short description.

import SwiftUI

struct WhatsNewView: View {
    @Environment(\.dismiss) private var dismiss

    // MARK: - Feature Data

    private let features: [(icon: String, iconColor: Color, title: String, description: String)] = [
        ("music.mic", .pink, "Song Requests", "Viewers add tracks with !sr. No focus-steal."),
        ("hand.raised.fill", .cyan, "Chat Vote-Skip", "!vs lets chat vote out a song. Chat tally or Twitch Polls."),
        ("chart.bar.fill", .green, "Listening History & Stats", "Top artists, weekly trend, hourly pattern. On-device only."),
        ("calendar", .purple, "Monthly Wrap", "Personal Wrapped for any month. Export as PNG."),
        ("bell.badge.fill", .orange, "Song Notifications", "Optional macOS notification on every track change."),
        ("gamecontroller.fill", .indigo, "Discord Playlist Presence", "Discord now shows the playlist you're spinning."),
        ("paintpalette.fill", .teal, "Widget Themes", "Six overlay themes and three layouts for OBS."),
        ("sparkles", .mint, "Liquid Glass Redesign", "Settings, menu bar, and onboarding rebuilt for macOS 26."),
        ("circle.lefthalf.filled", .blue, "Appearance", "Light, Dark, or System. The menu bar follows too."),
        ("eye.slash.fill", .gray, "Streamer Mode", "Masks your channel name, overlay URLs, and token. Camera safe."),
        ("pawprint.fill", .red, "WolfMark Branding", "New album-art placeholder and brand polish everywhere."),
        ("ladybug.fill", .yellow, "Diagnostics & Bug Reports", "Opt-in MetricKit reports plus one-click bug filing with redacted logs."),
    ]

    // MARK: - Body

    var body: some View {
        VStack(spacing: DSSpace.s7) {
            // MARK: Header
            VStack(spacing: DSSpace.s1h) {
                Text("What's New in WolfWave v\(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")")
                    .sectionHeader()

                Text("Highlights from this release.")
                    .font(.system(size: DSFont.Size.base))
                    .foregroundStyle(.secondary)
            }
            .padding(.top, DSSpace.s1)

            // MARK: Feature List
            ScrollView {
                VStack(spacing: DSSpace.s3) {
                    ForEach(Array(features.enumerated()), id: \.offset) { _, feature in
                        featureRow(feature)
                    }
                }
            }

            // MARK: Dismiss Button
            Button("Get Started") {
                dismiss()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .accessibilityLabel("Get Started")
            .accessibilityHint("Dismisses the what's new screen")
            .accessibilityIdentifier("whatsNew.getStarted")
        }
        .padding(DSSpace.s8)
        .frame(
            idealWidth: DSDimension.WhatsNew.windowWidth,
            idealHeight: DSDimension.WhatsNew.windowHeight
        )
    }

    // MARK: - Private Helpers

    /// Renders a single feature as a card-styled row.
    private func featureRow(_ feature: (icon: String, iconColor: Color, title: String, description: String)) -> some View {
        HStack(spacing: DSSpace.s5) {
            Image(systemName: feature.icon)
                .font(.system(size: DSFont.Size.xl))
                .foregroundStyle(feature.iconColor)
                .frame(width: 36, height: 36)
                .background(feature.iconColor.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: DSSpace.s0) {
                Text(feature.title)
                    .font(.system(size: DSFont.Size.base, weight: .semibold))

                Text(feature.description)
                    .font(.system(size: DSFont.Size.body))
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .cardStyle()
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(feature.title). \(feature.description)")
        .accessibilityIdentifier("whatsNew.feature.\(feature.title)")
    }
}

// MARK: - Preview

#Preview {
    WhatsNewView()
        .frame(
            width: DSDimension.WhatsNew.windowWidth,
            height: DSDimension.WhatsNew.windowHeight
        )
}
