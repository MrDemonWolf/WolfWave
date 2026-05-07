//
//  AlbumArtView.swift
//  wolfwave
//

import SwiftUI

/// Sized album-art tile. Falls back to a deterministic gradient derived from
/// the track + artist when no artwork is supplied.
///
/// Use this everywhere the design shows an album thumbnail — the now-playing
/// hero on General, the Discord preview mock, the menu-bar header, the song
/// request queue rows, and the OBS widget preview.
struct AlbumArtView: View {

    // MARK: - Properties

    var image: NSImage? = nil
    var seed: String = ""
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
                    colors: gradientColors,
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .overlay(alignment: .center) {
                    Image(systemName: "music.note")
                        .font(.system(size: size * 0.32, weight: .medium))
                        .foregroundStyle(.white.opacity(0.85))
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
    }

    // MARK: - Helpers

    /// Hue derived from the seed string so the same track always gets the
    /// same fallback color.
    private var hue: Double {
        guard !seed.isEmpty else { return 0.55 }
        var hasher = Hasher()
        hasher.combine(seed)
        let raw = abs(hasher.finalize())
        return Double(raw % 360) / 360.0
    }

    private var gradientColors: [Color] {
        [
            Color(hue: hue, saturation: 0.55, brightness: 0.80),
            Color(hue: (hue + 0.16).truncatingRemainder(dividingBy: 1.0), saturation: 0.65, brightness: 0.40)
        ]
    }
}

#Preview {
    HStack(spacing: 12) {
        AlbumArtView(seed: "Anti-Hero — Taylor Swift", size: 92)
        AlbumArtView(seed: "Heat Waves — Glass Animals", size: 64)
        AlbumArtView(seed: "Blinding Lights — The Weeknd", size: 36)
    }
    .padding()
}
