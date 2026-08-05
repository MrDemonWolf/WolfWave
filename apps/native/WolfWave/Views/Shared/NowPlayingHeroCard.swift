//
//  NowPlayingHeroCard.swift
//  WolfWave
//
//  Created by Nathanial Henniges on 2026-05-07.
//  Copyright © 2026 MrDemonWolf, Inc. All rights reserved.
//

import SwiftUI

/// Hero "Now Playing" card with 92pt album art, title/artist/album, and a
/// scrubber. Used on the General tab (Screen B in the redesign).
///
/// When `track` is nil this renders an empty-state card pointing back to the
/// permission helper or "tracking off" message.
struct NowPlayingHeroCard: View {

    // MARK: - Properties

    let track: String?
    let artist: String?
    let album: String?
    var artwork: NSImage? = nil
    var artworkURL: URL? = nil
    var elapsed: TimeInterval = 0
    var duration: TimeInterval = 0
    var trackingEnabled: Bool = true
    /// Renders the paused affordance: dimmed artwork, pause glyph overlay,
    /// frozen scrubber. The track text and subtitle remain at full opacity
    /// so the loaded song is still readable.
    var isPaused: Bool = false

    /// Music.app has no running process.
    ///
    /// Distinct from "nothing playing": with Music closed there is nothing for the
    /// user to do *in Music*, so the card says so plainly and offers to open it.
    /// Collapsing the two states left people staring at "Nothing playing right now"
    /// with no idea the app they needed was shut.
    var musicNotRunning: Bool = false

    /// Invoked by the Open Music button. Omit to hide the button.
    var onOpenMusic: (() -> Void)?

    // MARK: - Body

    var body: some View {
        HStack(alignment: .center, spacing: DSSpace.s6) {
            artworkView

            VStack(alignment: .leading, spacing: DSSpace.s1) {
                HStack(spacing: DSSpace.s2) {
                    Text(isPaused && track != nil ? "Paused" : "Now playing")
                        .sectionEyebrow()
                        .contentTransition(.opacity)
                        .id(isPaused)
                }

                Text(track ?? emptyStateTitle)
                    .font(.system(size: DSFont.Size.lg, weight: .semibold))
                    .lineLimit(1)
                    .foregroundStyle(track == nil ? .secondary : .primary)
                    .contentTransition(.opacity)
                    .id(track ?? emptyStateTitle)

                if let subtitle = subtitleText {
                    Text(subtitle)
                        .font(.system(size: DSFont.Size.base))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .contentTransition(.opacity)
                        .id(subtitle)
                }

                if track == nil, showsOpenMusic, let onOpenMusic {
                    Button("Open Music", action: onOpenMusic)
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .padding(.top, DSSpace.s2)
                }

                if track != nil, duration > 0 {
                    progressBar
                        .padding(.top, DSSpace.s2)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(DSSpace.s7)
        .cardStyleUnpadded()
        .animation(reduceMotion ? nil : .easeInOut(duration: DSMotion.Duration.base), value: track)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
    }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // MARK: - Subviews

    @ViewBuilder
    private var artworkView: some View {
        if track != nil {
            ZStack {
                AlbumArtView(image: artwork, url: artworkURL, size: 92)
                    .opacity(isPaused ? 0.55 : 1)
                    .saturation(isPaused ? 0.6 : 1)
                    .animation(reduceMotion ? nil : .easeInOut(duration: DSMotion.Duration.base), value: isPaused)

                if isPaused {
                    Image(systemName: "pause.circle.fill")
                        .font(.system(size: DSFont.Size.x3xl, weight: .semibold))
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(.white, .black.opacity(0.55))
                        .shadow(color: .black.opacity(0.35), radius: 6, y: 2)
                        .transition(.opacity.combined(with: .scale))
                }
            }
            .accessibilityLabel(isPaused ? "Paused" : "Now playing")
        } else {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(.quaternary.opacity(0.6))
                Image(systemName: "music.note")
                    .font(.system(size: DSFont.Size.x3xl, weight: .medium))
                    .foregroundStyle(.tertiary)
            }
            .frame(width: 92, height: 92)
        }
    }

    @ViewBuilder
    private var progressBar: some View {
        HStack(spacing: DSSpace.s3) {
            TimelineView(.animation(minimumInterval: 0.1, paused: reduceMotion || isPaused)) { _ in
                let fraction = duration > 0 ? min(max(elapsed / duration, 0), 1) : 0
                ProgressView(value: fraction)
                    .progressViewStyle(.linear)
                    .tint(.primary)
                    .frame(height: 3)
            }

            Text("\(HistoryFormat.clock(elapsed)) / \(HistoryFormat.clock(duration))")
                .font(.system(size: DSFont.Size.sm, design: .monospaced))
                .foregroundStyle(.secondary)
                .monospacedDigit()
                .contentTransition(.numericText())
        }
    }

    // MARK: - Helpers

    /// Headline for the no-track state.
    ///
    /// Three distinct causes, three distinct messages: tracking is switched off,
    /// Music is closed, or Music is open with nothing loaded. Each one implies a
    /// different next step for the user. Pure and `static` so the copy rules are
    /// unit-testable without rendering the view.
    static func emptyStateTitle(trackingEnabled: Bool, musicNotRunning: Bool) -> String {
        guard trackingEnabled else { return "Sync Music is off" }
        return musicNotRunning ? "Apple Music isn't open" : "Nothing playing right now"
    }

    /// Only offer to launch Music when it is actually closed and tracking is on.
    /// Offering it while tracking is off would launch Music to no effect.
    static func showsOpenMusic(trackingEnabled: Bool, musicNotRunning: Bool) -> Bool {
        trackingEnabled && musicNotRunning
    }

    private var emptyStateTitle: String {
        Self.emptyStateTitle(trackingEnabled: trackingEnabled, musicNotRunning: musicNotRunning)
    }

    private var showsOpenMusic: Bool {
        Self.showsOpenMusic(trackingEnabled: trackingEnabled, musicNotRunning: musicNotRunning)
    }

    private var subtitleText: String? {
        if track == nil {
            return showsOpenMusic ? "Open it and WolfWave picks up what you play." : nil
        }
        switch (artist, album) {
        case let (a?, b?): return "\(a) · \(b)"
        case let (a?, nil): return a
        case let (nil, b?): return b
        default: return nil
        }
    }

    private var accessibilityLabel: String {
        guard let track else { return emptyStateTitle }
        var label = isPaused ? "Paused: \(track)" : "Now playing: \(track)"
        if let artist { label += ", by \(artist)" }
        if let album { label += ", on \(album)" }
        if duration > 0 {
            let remaining = max(duration - elapsed, 0)
            label += ", \(HistoryFormat.clock(elapsed)) elapsed, \(HistoryFormat.clock(remaining)) remaining"
        }
        return label
    }
}

#Preview("Playing") {
    NowPlayingHeroCard(
        track: "Moonlit Howl",
        artist: "Arctic Wolf",
        album: "Tundra Sessions",
        elapsed: 72,
        duration: 218
    )
    .padding()
    .frame(width: 720)
    .background(Color(nsColor: .underPageBackgroundColor))
}

#Preview("Paused") {
    NowPlayingHeroCard(
        track: "Moonlit Howl",
        artist: "Arctic Wolf",
        album: "Tundra Sessions",
        elapsed: 72,
        duration: 218,
        isPaused: true
    )
    .padding()
    .frame(width: 720)
    .background(Color(nsColor: .underPageBackgroundColor))
}

#Preview("Empty") {
    NowPlayingHeroCard(track: nil, artist: nil, album: nil)
        .padding()
        .frame(width: 720)
}
