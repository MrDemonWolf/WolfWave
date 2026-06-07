//
//  ArtworkTintTests.swift
//  WolfWave
//
//  Created by Nathanial Henniges on 2026-06-07.
//  Copyright © 2026 MrDemonWolf, Inc. All rights reserved.
//

import Testing
import AppKit
import CoreGraphics
@testable import WolfWave

/// Tests for the album-art dominant-color extraction that tints the Monthly Wrap card.
@Suite("Artwork Tint Tests")
struct ArtworkTintTests {

    // MARK: - Helpers

    /// Builds a solid-color CGImage locally (no network, deterministic).
    private func solidImage(_ color: NSColor, side: Int = 16) -> CGImage {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let ctx = CGContext(
            data: nil, width: side, height: side, bitsPerComponent: 8,
            bytesPerRow: 0, space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        let rgb = color.usingColorSpace(.sRGB)!
        ctx.setFillColor(red: rgb.redComponent, green: rgb.greenComponent,
                         blue: rgb.blueComponent, alpha: 1)
        ctx.fill(CGRect(x: 0, y: 0, width: side, height: side))
        return ctx.makeImage()!
    }

    /// Builds a two-tone CGImage: left half `left`, right half `right`.
    private func splitImage(_ left: NSColor, _ right: NSColor, side: Int = 16) -> CGImage {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let ctx = CGContext(
            data: nil, width: side, height: side, bitsPerComponent: 8,
            bytesPerRow: 0, space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        let leftRGB = left.usingColorSpace(.sRGB)!
        ctx.setFillColor(red: leftRGB.redComponent, green: leftRGB.greenComponent,
                         blue: leftRGB.blueComponent, alpha: 1)
        ctx.fill(CGRect(x: 0, y: 0, width: side / 2, height: side))
        let rightRGB = right.usingColorSpace(.sRGB)!
        ctx.setFillColor(red: rightRGB.redComponent, green: rightRGB.greenComponent,
                         blue: rightRGB.blueComponent, alpha: 1)
        ctx.fill(CGRect(x: side / 2, y: 0, width: side / 2, height: side))
        return ctx.makeImage()!
    }

    // MARK: - Tests

    @Test("A solid red image extracts a red-dominant color")
    func testSolidRed() {
        let color = ArtworkTint.dominantColor(from: solidImage(.red))
        let srgb = color?.usingColorSpace(.sRGB)
        #expect(srgb != nil)
        #expect((srgb?.redComponent ?? 0) > 0.8)
        #expect((srgb?.greenComponent ?? 1) < 0.3)
        #expect((srgb?.blueComponent ?? 1) < 0.3)
    }

    @Test("A solid blue image extracts a blue-dominant color")
    func testSolidBlue() {
        let color = ArtworkTint.dominantColor(from: solidImage(.blue))
        let srgb = color?.usingColorSpace(.sRGB)
        #expect((srgb?.blueComponent ?? 0) > 0.8)
        #expect((srgb?.redComponent ?? 1) < 0.3)
    }

    @Test("A saturated half beats a desaturated half")
    func testSaturationWeighting() {
        // Vivid green on the left, near-gray on the right. The weighting should
        // pull the result toward green rather than averaging to a muddy tone.
        let color = ArtworkTint.dominantColor(from: splitImage(.green, NSColor(white: 0.5, alpha: 1)))
        let srgb = color?.usingColorSpace(.sRGB)
        #expect(srgb != nil)
        #expect((srgb?.greenComponent ?? 0) > (srgb?.redComponent ?? 1))
        #expect((srgb?.greenComponent ?? 0) > (srgb?.blueComponent ?? 1))
    }

    @Test("A fully desaturated image still returns a (gray) color, not nil")
    func testGrayFallback() {
        let color = ArtworkTint.dominantColor(from: solidImage(NSColor(white: 0.5, alpha: 1)))
        #expect(color != nil)
    }
}
