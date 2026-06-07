//
//  ArtworkTint.swift
//  WolfWave
//
//  Created by Nathanial Henniges on 2026-06-07.
//  Copyright © 2026 MrDemonWolf, Inc. All rights reserved.
//

import AppKit
import CoreGraphics

// MARK: - ArtworkTint

/// Extracts a single representative color from album artwork, used to personalize
/// the Monthly Wrap share card the way Spotify Wrapped / Apple Music Replay tint
/// from the listener's own art. Pure and `nonisolated` so it can run off the main
/// actor; no network, no I/O.
enum ArtworkTint {

    /// A vivid, representative color sampled from `image`, or `nil` if it can't
    /// be read. Convenience over the `CGImage` overload.
    nonisolated static func dominantColor(from image: NSImage, sample: Int = 16) -> NSColor? {
        var rect = CGRect(origin: .zero, size: image.size)
        guard let cgImage = image.cgImage(forProposedRect: &rect, context: nil, hints: nil) else {
            return nil
        }
        return dominantColor(from: cgImage, sample: sample)
    }

    /// Samples `cg` over a small grid and returns a saturation-weighted average so
    /// a punchy accent color wins over muddy background pixels. Near-black and
    /// near-white pixels are skipped. Falls back to a plain average when the art
    /// is fully desaturated. Returns `nil` only when no usable pixels remain.
    ///
    /// Reads through `NSBitmapImageRep.colorAt`, which is color-managed, so we
    /// don't have to reason about raw byte order or premultiplied alpha.
    nonisolated static func dominantColor(from cgImage: CGImage, sample: Int = 16) -> NSColor? {
        let rep = NSBitmapImageRep(cgImage: cgImage)
        let width = rep.pixelsWide
        let height = rep.pixelsHigh
        guard width > 0, height > 0 else { return nil }

        let steps = max(1, sample)
        var weighted = (r: 0.0, g: 0.0, b: 0.0, w: 0.0)
        var plain = (r: 0.0, g: 0.0, b: 0.0, count: 0.0)

        for row in 0..<steps {
            for col in 0..<steps {
                let x = min(width - 1, col * width / steps)
                let y = min(height - 1, row * height / steps)
                guard let pixel = rep.colorAt(x: x, y: y)?.usingColorSpace(.sRGB),
                      pixel.alphaComponent > 0.1 else { continue }

                let r = pixel.redComponent
                let g = pixel.greenComponent
                let b = pixel.blueComponent
                let maxC = max(r, g, b)
                let minC = min(r, g, b)
                let saturation = maxC <= 0 ? 0 : (maxC - minC) / maxC

                // Skip near-black (no hue) and near-white (bright but flat). A
                // bright yet saturated color, e.g. pure red, must survive.
                if maxC < 0.06 { continue }
                if maxC > 0.96, saturation < 0.15 { continue }

                let weight = saturation * saturation
                weighted.r += r * weight
                weighted.g += g * weight
                weighted.b += b * weight
                weighted.w += weight
                plain.r += r
                plain.g += g
                plain.b += b
                plain.count += 1
            }
        }

        guard plain.count > 0 else { return nil }

        if weighted.w > 0.0001 {
            return NSColor(
                srgbRed: weighted.r / weighted.w,
                green: weighted.g / weighted.w,
                blue: weighted.b / weighted.w,
                alpha: 1
            )
        }
        return NSColor(
            srgbRed: plain.r / plain.count,
            green: plain.g / plain.count,
            blue: plain.b / plain.count,
            alpha: 1
        )
    }
}
