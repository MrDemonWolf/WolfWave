//
//  DiscordPreviewCard.swift
//  wolfwave
//
//  Created by MrDemonWolf, Inc. on 5/16/26.
//

import SwiftUI

/// Mock Discord profile activity card rendered inside Settings.
///
/// Driven entirely by inputs so the live settings UI can preview button label
/// edits, toggle changes, and state-line tweaks without waiting for the
/// Discord client to update.
///
/// Visual styling deliberately matches the Discord desktop client (dark grey
/// surface, blurple "Listening to" header, gray pill buttons) rather than
/// macOS Liquid Glass — this view represents Discord, not native chrome,
/// so `.glassEffect()` should NOT be applied here.
struct DiscordPreviewCard: View {

    // MARK: - Types

    /// A single button row in the mock card.
    struct PreviewButton: Equatable {
        let label: String
        let url: String
    }

    // MARK: - Properties

    let trackTitle: String
    let artist: String
    let album: String
    let artworkURL: URL?
    let button1: PreviewButton?
    let button2: PreviewButton?

    // MARK: - Constants

    /// Discord card background `#2B2D31`.
    private let cardBackground = Color(red: 0.169, green: 0.176, blue: 0.192)
    /// Discord button background `#4E5058`.
    private let buttonBackground = Color(red: 0.306, green: 0.314, blue: 0.345)
    /// Faux progress bar fill — visual placeholder only.
    private let progressFraction: Double = 0.32

    // MARK: - Body

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            content
            buttons
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.white.opacity(0.06), lineWidth: 1)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilitySummary)
    }

    // MARK: - Subviews

    private var header: some View {
        HStack(spacing: 6) {
            Image(systemName: "headphones")
                .font(.system(size: 11, weight: .semibold))
            Text("LISTENING TO APPLE MUSIC")
                .font(.system(size: 11, weight: .semibold))
                .kerning(0.6)
        }
        .foregroundStyle(AppConstants.Brand.discord)
    }

    private var content: some View {
        HStack(alignment: .top, spacing: 12) {
            artworkView
            VStack(alignment: .leading, spacing: 3) {
                Text(trackTitle)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Text(artist)
                    .font(.system(size: 13))
                    .foregroundStyle(Color.white.opacity(0.85))
                    .lineLimit(1)
                Text(album)
                    .font(.system(size: 12))
                    .foregroundStyle(Color.white.opacity(0.55))
                    .lineLimit(1)
                progressBar
                    .padding(.top, 4)
            }
        }
    }

    private var artworkView: some View {
        ZStack(alignment: .bottomTrailing) {
            Group {
                if let artworkURL {
                    AsyncImage(url: artworkURL) { phase in
                        switch phase {
                        case .success(let image):
                            image.resizable().scaledToFill()
                        default:
                            artworkPlaceholder
                        }
                    }
                } else {
                    artworkPlaceholder
                }
            }
            .frame(width: 80, height: 80)
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))

            Image(systemName: "music.note")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 22, height: 22)
                .background(
                    LinearGradient(
                        colors: [
                            AppConstants.Brand.appleMusicGradientStart,
                            AppConstants.Brand.appleMusicGradientEnd,
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .clipShape(Circle())
                .overlay(Circle().stroke(cardBackground, lineWidth: 2))
                .offset(x: 4, y: 4)
        }
    }

    private var artworkPlaceholder: some View {
        LinearGradient(
            colors: [
                AppConstants.Brand.appleMusicGradientStart,
                AppConstants.Brand.appleMusicGradientEnd,
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .overlay(
            Image(systemName: "music.note")
                .font(.system(size: 28, weight: .bold))
                .foregroundStyle(.white.opacity(0.8))
        )
    }

    private var progressBar: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.white.opacity(0.15))
                Capsule()
                    .fill(Color.white.opacity(0.7))
                    .frame(width: geo.size.width * progressFraction)
            }
        }
        .frame(height: 4)
    }

    @ViewBuilder
    private var buttons: some View {
        let visible = [button1, button2].compactMap { $0 }
        if !visible.isEmpty {
            VStack(spacing: 6) {
                ForEach(visible.indices, id: \.self) { i in
                    buttonPill(label: visible[i].label)
                }
            }
        }
    }

    private func buttonPill(label: String) -> some View {
        Text(label)
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 32)
            .background(buttonBackground)
            .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
    }

    private var accessibilitySummary: String {
        var parts = ["Discord preview", "Listening to Apple Music", trackTitle, artist, album]
        if let b1 = button1 { parts.append("Button: \(b1.label)") }
        if let b2 = button2 { parts.append("Button: \(b2.label)") }
        return parts.joined(separator: ", ")
    }
}

// MARK: - Preview

#Preview("Both buttons") {
    DiscordPreviewCard(
        trackTitle: "Smooth Operator",
        artist: "Sade",
        album: "Diamond Life",
        artworkURL: nil,
        button1: .init(label: "Listen on Apple Music", url: "https://music.apple.com/x"),
        button2: .init(label: "Find on Other Services", url: "https://song.link/i/1")
    )
    .padding()
    .frame(width: 360)
    .background(Color.black)
}

#Preview("One button") {
    DiscordPreviewCard(
        trackTitle: "Redbone",
        artist: "Childish Gambino",
        album: "Awaken, My Love!",
        artworkURL: nil,
        button1: .init(label: "Listen on Apple Music", url: "https://music.apple.com/x"),
        button2: nil
    )
    .padding()
    .frame(width: 360)
    .background(Color.black)
}

#Preview("No buttons") {
    DiscordPreviewCard(
        trackTitle: "Truly Madly Deeply",
        artist: "Savage Garden",
        album: "Savage Garden",
        artworkURL: nil,
        button1: nil,
        button2: nil
    )
    .padding()
    .frame(width: 360)
    .background(Color.black)
}
