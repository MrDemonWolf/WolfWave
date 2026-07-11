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
        ("music.mic", .pink, "Song Requests", "Chat adds tracks with !sr. No focus-steal."),
        ("hand.raised.fill", .cyan, "Chat Vote-Skip", "!vs lets chat vote out a song."),
        ("chart.bar.fill", .green, "History & Stats", "Top artists, weekly trend, hourly pattern. On-device only."),
        ("calendar", .purple, "Monthly Wrap", "Your Wrapped for any month. Save as a PNG."),
        ("paintpalette.fill", .teal, "Widget Themes", "Six overlay themes and three layouts for OBS."),
        ("circle.lefthalf.filled", .blue, "Light & Dark", "Pick Light, Dark, or System. The menu bar follows too."),
        ("tray.and.arrow.down.fill", .indigo, "Backup & Restore", "Export settings to JSON, restore on any Mac."),
    ]

    // MARK: - Body

    var body: some View {
        VStack(spacing: DSSpace.s7) {
            // MARK: Header
            VStack(spacing: DSSpace.s1h) {
                Text("What's New in WolfWave v\(AppConstants.AppInfo.whatsNewVersion)")
                    .sectionHeader()

                Text("The big ones. There's more in the full changelog.")
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

            // MARK: Actions
            VStack(spacing: DSSpace.s3) {
                Button("Get Started") {
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .accessibilityLabel("Get Started")
                .accessibilityHint("Dismisses the what's new screen")
                .accessibilityIdentifier("whatsNew.getStarted")

                Button("See all changes") {
                    ExternalLink.open(AppConstants.URLs.changelog)
                }
                .buttonStyle(.link)
                .font(.system(size: DSFont.Size.body))
                .accessibilityLabel("See all changes")
                .accessibilityHint("Opens the full changelog in your browser")
                .accessibilityIdentifier("whatsNew.seeAllChanges")
            }
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
