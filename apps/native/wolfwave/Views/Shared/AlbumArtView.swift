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

    // MARK: - Memoized fallback gradient

    /// Hash → gradient cache. Identical track/artist seeds skip the HSL conversion on every
    /// render — the same fallback art shows up on the General hero, queue rows, widget preview,
    /// and Discord mock, so amortizing this matters across switches.
    nonisolated(unsafe) private static var gradientCache: [String: [Color]] = [:]
    private static let gradientCacheLock = NSLock()

    private var gradientColors: [Color] {
        let key = seed
        Self.gradientCacheLock.lock()
        defer { Self.gradientCacheLock.unlock() }
        if let cached = Self.gradientCache[key] { return cached }
        let hueValue: Double = {
            guard !key.isEmpty else { return 0.55 }
            var hasher = Hasher()
            hasher.combine(key)
            let raw = abs(hasher.finalize())
            return Double(raw % 360) / 360.0
        }()
        let colors: [Color] = [
            Color(hue: hueValue, saturation: 0.55, brightness: 0.80),
            Color(hue: (hueValue + 0.16).truncatingRemainder(dividingBy: 1.0), saturation: 0.65, brightness: 0.40)
        ]
        if Self.gradientCache.count > 64 { Self.gradientCache.removeAll(keepingCapacity: true) }
        Self.gradientCache[key] = colors
        return colors
    }

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

}

#Preview {
    HStack(spacing: 12) {
        AlbumArtView(seed: "Anti-Hero — Taylor Swift", size: 92)
        AlbumArtView(seed: "Heat Waves — Glass Animals", size: 64)
        AlbumArtView(seed: "Blinding Lights — The Weeknd", size: 36)
    }
    .padding()
}
