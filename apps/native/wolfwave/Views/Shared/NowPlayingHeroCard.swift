//
//  NowPlayingHeroCard.swift
//  wolfwave
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
        HStack(alignment: .center, spacing: 16) {
            artworkView

            VStack(alignment: .leading, spacing: 4) {
                Text("Now playing")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.tertiary)
                    .textCase(.uppercase)
                    .tracking(0.6)

                Text(track ?? (trackingEnabled ? "Nothing playing right now" : "Sync Music is off"))
                    .font(.system(size: 18, weight: .semibold))
                    .lineLimit(1)
                    .foregroundStyle(track == nil ? .secondary : .primary)

                if let subtitle = subtitleText {
                    Text(subtitle)
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                if track != nil, duration > 0 {
                    progressBar
                        .padding(.top, 8)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(18)
        .glassEffect(.regular, in: .rect(cornerRadius: AppConstants.SettingsUI.cardCornerRadius))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
    }

    // MARK: - Subviews

    @ViewBuilder
    private var artworkView: some View {
        if track != nil {
            AlbumArtView(image: artwork, seed: "\(track ?? "")—\(artist ?? "")", size: 92)
        } else {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(.quaternary.opacity(0.6))
                Image(systemName: "music.note")
                    .font(.system(size: 26, weight: .medium))
                    .foregroundStyle(.tertiary)
            }
            .frame(width: 92, height: 92)
        }
    }

    @ViewBuilder
    private var progressBar: some View {
        let fraction = duration > 0 ? min(max(elapsed / duration, 0), 1) : 0
        HStack(spacing: 10) {
            ProgressView(value: fraction)
                .progressViewStyle(.linear)
                .tint(.primary)
                .frame(height: 3)

            Text("\(timeString(elapsed)) / \(timeString(duration))")
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.secondary)
                .monospacedDigit()
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
