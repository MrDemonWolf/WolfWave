//
//  DiscordPreviewCard.swift
//  WolfWave
//
//  Created by Nathanial Henniges on 2026-05-16.
//  Copyright © 2026 MrDemonWolf, Inc. All rights reserved.
//

import SwiftUI

/// Mock Discord profile activity card rendered inside Settings.
///
/// Driven entirely by inputs so the live settings UI can preview button label
/// edits, toggle changes, and state-line tweaks without waiting for the
/// Discord client to update.
///
/// The card mirrors what Discord *actually* shows. A track is only rendered in
/// the `.playing` and `.paused` modes; when nothing is playing, Apple Music is
/// closed, or Discord itself isn't running, the card renders a matching empty
/// state instead of a stale song. This keeps the preview honest about the fact
/// that the real presence is cleared (shows nothing on the profile) outside of
/// active playback.
///
/// Visual styling deliberately matches the Discord desktop client (dark grey
/// surface, muted "Listening to WolfWave" header with a green now-playing dot,
/// gray pill buttons) rather than macOS Liquid Glass. This view represents
/// Discord, not native chrome, so `.glassEffect()` should NOT be applied here.
struct DiscordPreviewCard: View {

    // MARK: - Types

    /// What the card is currently representing. Drives the header, dot color,
    /// body content, and whether buttons render.
    enum Mode: Equatable {
        /// A track is actively playing. Full card, moving progress, buttons.
        case playing
        /// A track is loaded but paused. Track stays, frozen bar, "Paused" badge.
        case paused
        /// Apple Music is open but nothing is playing. Real presence is cleared.
        case stopped
        /// Apple Music isn't running. Real presence is cleared.
        case musicClosed
        /// Discord client isn't running, so nothing can be shown on the profile.
        case discordOffline
        /// Opt-in idle activity: nothing playing, but WolfWave stays on the
        /// profile as "Listening to WolfWave" · idle instead of clearing.
        case idleActivity

        /// Whether this mode renders the track + buttons (vs. an empty state).
        var showsTrack: Bool { self == .playing || self == .paused }

        /// Whether the header reads "LISTENING TO WOLFWAVE" (an activity is on
        /// the profile) vs. just "WOLFWAVE" (no activity).
        var showsListeningHeader: Bool {
            self == .playing || self == .paused || self == .idleActivity
        }
    }

    /// A single button row in the mock card.
    struct PreviewButton: Equatable {
        let label: String
        let url: String
    }

    // MARK: - Properties

    var mode: Mode = .playing
    let trackTitle: String
    let artist: String
    let album: String
    let artworkURL: URL?
    let button1: PreviewButton?
    let button2: PreviewButton?

    /// Hover tooltip for the small Apple Music badge. When non-nil, mirrors the
    /// playlist text Discord shows on the small icon (`assets.small_text`).
    var playlistTooltip: String? = nil

    // MARK: - Constants

    /// Discord card background `#2B2D31`.
    private let cardBackground = AppConstants.Brand.discordSurface
    /// Discord button background `#4E5058`.
    private let buttonBackground = AppConstants.Brand.discordControl
    /// Faux progress bar fill, visual placeholder only.
    private let progressFraction: Double = 0.32

    // MARK: - Body

    var body: some View {
        VStack(alignment: .leading, spacing: DSSpace.s4) {
            header
            if mode.showsTrack {
                trackContent
                buttons
            } else if mode == .idleActivity {
                idleActivityContent
            } else {
                emptyContent
            }
        }
        .padding(DSSpace.s5)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: DSRadius.lg2, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: DSRadius.lg2, style: .continuous)
                .stroke(Color.white.opacity(0.06), lineWidth: 1)
        )
        .opacity(mode == .discordOffline ? 0.55 : 1)
        .animation(.easeInOut(duration: DSMotion.Duration.base), value: mode)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilitySummary)
    }

    // MARK: - Header

    private var header: some View {
        // Mirrors Discord's real "Listening to <app>" row: muted gray label with
        // the app name brighter, preceded by a status dot. Discord shows the
        // registered application name (WolfWave), not "Apple Music", and the
        // header is never blurple/purple.
        HStack(spacing: DSSpace.s1h) {
            Circle()
                .fill(dotColor)
                .frame(width: 8, height: 8)
            headerLabel
                .foregroundStyle(Color.white.opacity(0.55))
                .font(.system(size: DSFont.Size.sm, weight: .bold))
                .kerning(0.6)
        }
    }

    private var dotColor: Color {
        switch mode {
        case .playing:        return .green
        case .paused:         return .orange
        case .stopped,
             .musicClosed,
             .discordOffline,
             .idleActivity:   return Color.white.opacity(0.35)
        }
    }

    private var headerLabel: Text {
        if mode.showsListeningHeader {
            return Text("LISTENING TO \(Text("WOLFWAVE").foregroundStyle(Color.white.opacity(0.9)))")
        }
        return Text("WOLFWAVE").foregroundStyle(Color.white.opacity(0.55))
    }

    // MARK: - Track content

    private var trackContent: some View {
        HStack(alignment: .top, spacing: DSSpace.s4) {
            artworkView
            VStack(alignment: .leading, spacing: 3) {
                Text(trackTitle)
                    .font(.system(size: DSFont.Size.md, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Text(artist)
                    .font(.system(size: DSFont.Size.base))
                    .foregroundStyle(Color.white.opacity(0.85))
                    .lineLimit(1)
                Text(album)
                    .font(.system(size: DSFont.Size.body))
                    .foregroundStyle(Color.white.opacity(0.55))
                    .lineLimit(1)
                progressBar
                    .padding(.top, DSSpace.s1)
            }
        }
        // Paused playback is dimmed and desaturated to read as "on hold".
        .opacity(mode == .paused ? 0.65 : 1)
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
                            // Matches the real presence fallback: `large_image`
                            // is `artworkURL ?? "apple_music"`, so no art = the
                            // Apple Music tile, not the WolfMark.
                            appleMusicTile
                        }
                    }
                } else {
                    appleMusicTile
                }
            }
            .frame(width: 80, height: 80)
            .saturation(mode == .paused ? 0.4 : 1)
            .clipShape(RoundedRectangle(cornerRadius: DSRadius.sm, style: .continuous))

            // Small corner badge mirrors Discord's `assets.small_image`. While
            // paused the live presence swaps this to a pause glyph + "Paused"
            // text, so the preview does the same.
            cornerBadge(
                paused: mode == .paused,
                tooltip: mode == .paused ? "Paused" : (playlistTooltip ?? "Apple Music")
            )
        }
    }

    /// Apple Music source badge mirroring Discord's `assets.small_image`.
    /// `paused` swaps the glyph to a pause symbol. Shared by the playing,
    /// paused, and idle tiles so the small badge stays visually identical.
    private func cornerBadge(paused: Bool, tooltip: String) -> some View {
        // Renders the real Discord `assets.small_image` art (`apple_music.png` /
        // `pause.png` uploaded to the Discord portal) clipped to a circle, which
        // is exactly how the live client draws the small badge. Previously a
        // hand-built SF Symbol on a gradient stood in for it.
        Image(paused ? "DiscordArtPause" : "DiscordArtAppleMusic")
            .resizable()
            .scaledToFill()
            .frame(width: 22, height: 22)
            .clipShape(Circle())
            .overlay(Circle().stroke(cardBackground, lineWidth: 2))
            .offset(x: 4, y: 4)
            .help(tooltip)
    }

    private var artworkPlaceholder: some View {
        LinearGradient(
            colors: [DSColor.brand500, DSColor.brand800],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .overlay(
            Image("WolfMark")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 42, height: 42)
                .foregroundStyle(.white)
        )
    }

    /// Mirrors Discord's `assets.large_image: "apple_music"` art asset: the Apple
    /// Music app icon (white note on the Apple Music gradient). The real idle
    /// presence ships this as its large image, so the idle card renders it too
    /// instead of the WolfMark placeholder, keeping the preview honest.
    private var appleMusicTile: some View {
        // Mirrors Discord's `assets.large_image: "apple_music"` art exactly: the
        // same `apple_music.png` uploaded to the Discord portal, not a rebuilt
        // logo-on-gradient. Rendered on black so the asset's transparent corners
        // read like the live client.
        //
        // The asset's own corner radius is rounder than the tile's `DSRadius.sm`
        // clip, so at 1:1 the black backing peeked through the tile corners. Scale
        // the art up so its rounded corners overshoot the clip and the tile's
        // corner radius defines clean, fully-filled edges.
        Color.black
            .overlay(
                Image("DiscordArtAppleMusic")
                    .resizable()
                    .scaledToFill()
                    .scaleEffect(1.22)
            )
    }

    /// Mirrors Discord's `assets.large_image: "wolfwave"` art exactly: the same
    /// WolfWave app-icon PNG (`discord-assets/wolfwave.png`) that's uploaded to
    /// the Discord developer portal as the `wolfwave` Rich Presence asset. Used
    /// for the idle tile so the preview shows the real registered art instead of
    /// a hand-built `WolfMark`-on-gradient stand-in. Rendered on the Discord card
    /// surface so the asset's transparent edges read like the live client.
    private var wolfWaveArtTile: some View {
        Color.black
            .overlay(
                Image("DiscordArtWolfWave")
                    .resizable()
                    .scaledToFill()
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
            VStack(spacing: DSSpace.s1h) {
                ForEach(visible.indices, id: \.self) { i in
                    buttonPill(label: visible[i].label)
                }
            }
        }
    }

    private func buttonPill(label: String) -> some View {
        Text(label)
            .font(.system(size: DSFont.Size.base, weight: .medium))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 32)
            .background(buttonBackground)
            .clipShape(RoundedRectangle(cornerRadius: DSRadius.xs, style: .continuous))
    }

    // MARK: - Empty content

    /// Shared empty-state layout for `.stopped`, `.musicClosed`, and
    /// `.discordOffline`. Reuses the WolfMark artwork tile so the card keeps its
    /// shape, then explains why nothing is showing on the profile.
    private var emptyContent: some View {
        HStack(alignment: .center, spacing: DSSpace.s4) {
            artworkPlaceholder
                .frame(width: 80, height: 80)
                .saturation(0.35)
                .opacity(0.7)
                .clipShape(RoundedRectangle(cornerRadius: DSRadius.sm, style: .continuous))
            VStack(alignment: .leading, spacing: DSSpace.s1) {
                Text(emptyHeadline)
                    .font(.system(size: DSFont.Size.md, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.9))
                    .lineLimit(1)
                Text(emptySubtext)
                    .font(.system(size: DSFont.Size.body))
                    .foregroundStyle(Color.white.opacity(0.5))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
    }

    private var emptyHeadline: String {
        switch mode {
        case .stopped:        return "Nothing playing"
        case .musicClosed:    return "Apple Music is closed"
        case .discordOffline: return "Discord isn't running"
        case .playing, .paused, .idleActivity: return ""
        }
    }

    private var emptySubtext: String {
        switch mode {
        case .stopped:        return "Play a song in Apple Music and it shows up here."
        case .musicClosed:    return "Open Apple Music to share what you're listening to."
        case .discordOffline: return "Open Discord, then your music shows on your profile."
        case .playing, .paused, .idleActivity: return ""
        }
    }

    // MARK: - Idle activity content

    /// Opt-in idle marker. Looks like a real activity ("Listening to WolfWave ·
    /// Apple Music is idle") so the preview matches what stays on the profile
    /// when the user keeps idle status on. The large tile is the WolfWave logo
    /// with an Apple Music corner badge, mirroring the real payload's
    /// `large_image: wolfwave` + `small_image: apple_music`. No track,
    /// progress, or buttons.
    private var idleActivityContent: some View {
        HStack(alignment: .center, spacing: DSSpace.s4) {
            ZStack(alignment: .bottomTrailing) {
                wolfWaveArtTile
                    .frame(width: 80, height: 80)
                    .clipShape(RoundedRectangle(cornerRadius: DSRadius.sm, style: .continuous))
                cornerBadge(paused: false, tooltip: "Apple Music")
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(AppConstants.Discord.idleDetails)
                    .font(.system(size: DSFont.Size.md, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Text(AppConstants.Discord.idleState)
                    .font(.system(size: DSFont.Size.base))
                    .foregroundStyle(Color.white.opacity(0.6))
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
    }

    // MARK: - Accessibility

    private var accessibilitySummary: String {
        switch mode {
        case .playing, .paused:
            var parts = [
                "Discord preview",
                mode == .paused ? "Paused on WolfWave" : "Listening to WolfWave",
                trackTitle, artist, album,
            ]
            if let playlistTooltip { parts.append("App icon tooltip: \(playlistTooltip)") }
            if let b1 = button1 { parts.append("Button: \(b1.label)") }
            if let b2 = button2 { parts.append("Button: \(b2.label)") }
            return parts.joined(separator: ", ")
        case .stopped, .musicClosed, .discordOffline:
            return "Discord preview, \(emptyHeadline). \(emptySubtext)"
        case .idleActivity:
            return "Discord preview, Listening to WolfWave, \(AppConstants.Discord.idleDetails), \(AppConstants.Discord.idleState)"
        }
    }
}

// MARK: - Preview

#Preview("Playing") {
    DiscordPreviewCard(
        mode: .playing,
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

#Preview("Paused") {
    DiscordPreviewCard(
        mode: .paused,
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

#Preview("Stopped") {
    DiscordPreviewCard(
        mode: .stopped,
        trackTitle: "",
        artist: "",
        album: "",
        artworkURL: nil,
        button1: nil,
        button2: nil
    )
    .padding()
    .frame(width: 360)
    .background(Color.black)
}

#Preview("Apple Music closed") {
    DiscordPreviewCard(
        mode: .musicClosed,
        trackTitle: "",
        artist: "",
        album: "",
        artworkURL: nil,
        button1: nil,
        button2: nil
    )
    .padding()
    .frame(width: 360)
    .background(Color.black)
}

#Preview("Idle activity") {
    DiscordPreviewCard(
        mode: .idleActivity,
        trackTitle: "",
        artist: "",
        album: "",
        artworkURL: nil,
        button1: nil,
        button2: nil
    )
    .padding()
    .frame(width: 360)
    .background(Color.black)
}

#Preview("Discord offline") {
    DiscordPreviewCard(
        mode: .discordOffline,
        trackTitle: "",
        artist: "",
        album: "",
        artworkURL: nil,
        button1: nil,
        button2: nil
    )
    .padding()
    .frame(width: 360)
    .background(Color.black)
}
