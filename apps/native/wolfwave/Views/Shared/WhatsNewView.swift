//
//  WhatsNewView.swift
//  wolfwave
//
//  Created by MrDemonWolf, Inc. on 3/30/26.
//

/// Displays a "What's New" sheet highlighting key features introduced in this version.
///
/// Shown once per version after the user has completed onboarding. Each feature is
/// displayed as a card-styled row with an SF Symbol icon, title, and short description.

import SwiftUI

struct WhatsNewView: View {
    @Environment(\.dismiss) private var dismiss

    // MARK: - Feature Data

    private static let twitchPurple = Color(red: 0.57, green: 0.27, blue: 1.0)
    private static let discordIndigo = Color(red: 0.35, green: 0.40, blue: 0.95)

    private let features: [(icon: String, iconColor: Color, title: String, description: String)] = [
        ("music.note.2", .pink, "Discord Buttons", "Open in Apple Music or jump to song.link from your Discord status"),
        ("arrow.up.right.circle", .blue, "Launch at Login", "WolfWave starts automatically when your Mac does"),
        ("sparkle", twitchPurple, "Homebrew Auto-Update", "Homebrew tap stays in sync whenever a new release ships"),
        ("rectangle.and.arrow.up.right.and.arrow.down.left", .green, "Custom DMG", "Polished installer background with WolfWave branding"),
        ("paintbrush", discordIndigo, "Artwork & Links", "Album art and song.link resolved automatically for every track"),
        ("checkmark.shield", .orange, "Stability", "Tighter entitlements, fixed Sparkle updates, and smarter reconnects")
    ]

    // MARK: - Body

    var body: some View {
        VStack(spacing: 20) {
            // MARK: Header
            VStack(spacing: 6) {
                Text("What's New in WolfWave v\(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")")
                    .sectionHeader()

                Text("Here's what's new in this release.")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 4)

            // MARK: Feature List
            ScrollView {
                VStack(spacing: 10) {
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
        .padding(24)
        .frame(idealWidth: 420, idealHeight: 500)
    }

    // MARK: - Private Helpers

    /// Renders a single feature as a card-styled row.
    private func featureRow(_ feature: (icon: String, iconColor: Color, title: String, description: String)) -> some View {
        HStack(spacing: 14) {
            Image(systemName: feature.icon)
                .font(.system(size: 20))
                .foregroundStyle(feature.iconColor)
                .frame(width: 36, height: 36)
                .background(feature.iconColor.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 2) {
                Text(feature.title)
                    .font(.system(size: 13, weight: .semibold))

                Text(feature.description)
                    .font(.system(size: 12))
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
        .frame(width: 420, height: 500)
}
