//
//  AlbumArtView.swift
//  wolfwave
//

import SwiftUI

/// Sized album-art tile. Falls back to the WolfWave-branded placeholder — the
/// wolf mark on a brand-blue gradient — when no artwork is supplied.
///
/// Used by the now-playing hero on the General tab (`NowPlayingHeroCard`), and
/// intended for any other album thumbnail the design adds.
struct AlbumArtView: View {

    // MARK: - Properties

    var image: NSImage? = nil
    var size: CGFloat = 64
    var cornerRadius: CGFloat? = nil

    // MARK: - Body

    var body: some View {
        let radius = cornerRadius ?? max(4, size * 0.10)
        Group {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                LinearGradient(
                    colors: [DSColor.brand500, DSColor.brand800],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .overlay(alignment: .center) {
                    Image("WolfMark")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: size * 0.52, height: size * 0.52)
                        .foregroundStyle(.white)
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .stroke(.white.opacity(0.10), lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.18), radius: 2, x: 0, y: 1)
        // Decorative — the track/artist text alongside the artwork carries
        // the semantic content. Hiding here keeps VoiceOver from announcing
        // "image" before the song title.
        .accessibilityHidden(true)
    }

}

#Preview("Branded fallback") {
    HStack(spacing: DSSpace.s4) {
        AlbumArtView(size: 92)
        AlbumArtView(size: 64)
        AlbumArtView(size: 36)
    }
    .padding()
}
