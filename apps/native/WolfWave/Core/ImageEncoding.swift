//
//  ImageEncoding.swift
//  WolfWave
//
//  Copyright © 2026 MrDemonWolf, Inc. All rights reserved.
//

import AppKit

extension NSImage {

    /// Encodes the image as PNG data, or `nil` if it has no bitmap representation.
    ///
    /// Centralizes the `tiffRepresentation` to `NSBitmapImageRep` to `.png` chain that
    /// was duplicated between the Monthly Wrap share card and the widget HTTP favicon
    /// route, so a fix in one place (color space, properties) reaches both.
    ///
    /// `nonisolated` so the widget HTTP server can call it from its Network.framework
    /// callback queue. Bitmap encoding does not touch the main actor.
    nonisolated func pngData() -> Data? {
        guard let tiff = tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff) else { return nil }
        return bitmap.representation(using: .png, properties: [:])
    }
}
