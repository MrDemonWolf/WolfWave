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
    var elapsed: TimeInterval = 0
    var duration: TimeInterval = 0
    var trackingEnabled: Bool = true

    // MARK: - Body

    var body: some View {
        HStack(alignment: .center, spacing: DSSpace.s6) {
            artworkView

            VStack(alignment: .leading, spacing: DSSpace.s1) {
                Text("Now playing")
                    .font(.system(size: DSFont.Size.sm, weight: .semibold))
                    .foregroundStyle(.tertiary)
                    .textCase(.uppercase)
                    .tracking(0.6)

                Text(track ?? (trackingEnabled ? "Nothing playing right now" : "Sync Music is off"))
                    .font(.system(size: DSFont.Size.x18, weight: .semibold))
                    .lineLimit(1)
                    .foregroundStyle(track == nil ? .secondary : .primary)
                    .contentTransition(.opacity)
                    .id(track ?? "")

                if let subtitle = subtitleText {
                    Text(subtitle)
                        .font(.system(size: DSFont.Size.base))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .contentTransition(.opacity)
                        .id(subtitle)
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
            AlbumArtView(image: artwork, size: 92)
        } else {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(.quaternary.opacity(0.6))
                Image(systemName: "music.note")
                    .font(.system(size: DSFont.Size.x26, weight: .medium))
                    .foregroundStyle(.tertiary)
            }
            .frame(width: 92, height: 92)
        }
    }

    @ViewBuilder
    private var progressBar: some View {
        HStack(spacing: DSSpace.s3) {
            TimelineView(.animation(minimumInterval: 0.1, paused: reduceMotion)) { _ in
                let fraction = duration > 0 ? min(max(elapsed / duration, 0), 1) : 0
                ProgressView(value: fraction)
                    .progressViewStyle(.linear)
                    .tint(.primary)
                    .frame(height: 3)
            }

            Text("\(timeString(elapsed)) / \(timeString(duration))")
                .font(.system(size: DSFont.Size.sm, design: .monospaced))
                .foregroundStyle(.secondary)
                .monospacedDigit()
                .contentTransition(.numericText())
        }
    }

    // MARK: - Helpers

    private var subtitleText: String? {
        switch (artist, album) {
        case let (a?, b?): return "\(a) — \(b)"
        case let (a?, nil): return a
        case let (nil, b?): return b
        default: return nil
        }
    }

    /// Formats a playback position as a colon-separated `M:SS` timestamp.
    ///
    /// - Parameter seconds: Position in seconds. Rounded to the nearest second.
    /// - Returns: A `M:SS` string (e.g. `"3:07"`).
    private func timeString(_ seconds: TimeInterval) -> String {
        let total = Int(seconds.rounded())
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    private var accessibilityLabel: String {
        guard let track else {
            return trackingEnabled ? "Nothing playing right now" : "Sync Music is off"
        }
        var label = "Now playing: \(track)"
        if let artist { label += ", by \(artist)" }
        if let album { label += ", on \(album)" }
        return label
    }
}

#Preview("Playing") {
    NowPlayingHeroCard(
        track: "Anti-Hero",
        artist: "Taylor Swift",
        album: "Midnights",
        elapsed: 68,
        duration: 201
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
