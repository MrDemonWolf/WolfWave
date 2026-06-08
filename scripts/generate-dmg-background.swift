#!/usr/bin/swift
// Generates DMG background images for WolfWave installer
// Usage: swift generate-dmg-background.swift <output-dir>
//
// Layout is intentionally simple: WolfWave.app on the left, a chevron arrow
// in the middle with a "Drag to install" label, /Applications on the right.
// Icon positions in create-dmg.sh must match the slots below.

import AppKit
import CoreGraphics
import Foundation

// Canvas (points) = Finder's icon-view *content* area, which the background
// fills. create-dmg.sh sets the window bounds to {200,200,800,602} (600x402);
// the ~22px title-bar chrome is excluded, leaving a 600x380 content area that
// matches this canvas 1:1.
let canvasWidth = 600
let canvasHeight = 380

// WolfWave brand blue (design-system tokens: brand.500 / brand.600).
let brand = (r: 0.039, g: 0.518, b: 1.0)      // #0A84FF

func generateBackground(scale: Int, outputPath: String) {
    let w = canvasWidth * scale
    let h = canvasHeight * scale
    let s = CGFloat(scale)

    let colorSpace = CGColorSpaceCreateDeviceRGB()
    guard let context = CGContext(
        data: nil,
        width: w,
        height: h,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: colorSpace,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else {
        print("Failed to create graphics context")
        exit(1)
    }

    // 1. Flat dark base gradient: charcoal, matches brand dark surface (#1D1D1F).
    let base = CGGradient(
        colorsSpace: colorSpace,
        colors: [
            CGColor(red: 0.10, green: 0.10, blue: 0.12, alpha: 1.0),
            CGColor(red: 0.13, green: 0.13, blue: 0.15, alpha: 1.0),
        ] as CFArray,
        locations: [0.0, 1.0]
    )!
    context.drawLinearGradient(
        base,
        start: CGPoint(x: 0, y: CGFloat(h)),
        end: CGPoint(x: 0, y: 0),
        options: []
    )

    // 2. Soft brand glow behind the drop target (right side). The only color.
    let glow = CGGradient(
        colorsSpace: colorSpace,
        colors: [
            CGColor(red: brand.r, green: brand.g, blue: brand.b, alpha: 0.12),
            CGColor(red: brand.r, green: brand.g, blue: brand.b, alpha: 0.0),
        ] as CFArray,
        locations: [0.0, 1.0]
    )!
    let glowX = CGFloat(w) * 0.72
    let glowY = CGFloat(h) * 0.52
    context.drawRadialGradient(
        glow,
        startCenter: CGPoint(x: glowX, y: glowY),
        startRadius: 0,
        endCenter: CGPoint(x: glowX, y: glowY),
        endRadius: CGFloat(w) * 0.38,
        options: []
    )

    // 3. Chevron arrow ">" centered between the two icon slots, brand blue.
    //    Icons sit at y ~ 52% of height (top-left origin); CG origin is bottom-left,
    //    so draw at the mirrored y to line up with the icon row.
    let arrowX = CGFloat(w) * 0.50
    let arrowY = CGFloat(h) * 0.52           // CG bottom-left space (icon row ≈ y182 top-left)
    let chevronW: CGFloat = 22 * s           // horizontal reach of each stroke
    let chevronH: CGFloat = 26 * s           // vertical reach (half-height)
    let lineWidth: CGFloat = 9 * s

    context.setStrokeColor(CGColor(red: brand.r, green: brand.g, blue: brand.b, alpha: 0.9))
    context.setLineWidth(lineWidth)
    context.setLineCap(.round)
    context.setLineJoin(.round)
    context.beginPath()
    context.move(to: CGPoint(x: arrowX - chevronW, y: arrowY + chevronH))
    context.addLine(to: CGPoint(x: arrowX + chevronW, y: arrowY))
    context.addLine(to: CGPoint(x: arrowX - chevronW, y: arrowY - chevronH))
    context.strokePath()

    // 4. "Drag to install" label, above the chevron.
    let fontSize: CGFloat = 13.0 * s
    let font = CTFontCreateWithName("Helvetica Neue Medium" as CFString, fontSize, nil)
    let attrString = NSAttributedString(string: "Drag to install", attributes: [
        .font: font,
        .foregroundColor: NSColor(white: 1.0, alpha: 0.55),
        .kern: 0.5 * s,
    ])
    let line = CTLineCreateWithAttributedString(attrString)
    let textBounds = CTLineGetBoundsWithOptions(line, .useOpticalBounds)
    context.textPosition = CGPoint(
        x: arrowX - textBounds.width / 2,
        y: arrowY + chevronH + 18 * s
    )
    CTLineDraw(line, context)

    // Export PNG with DPI so Finder scales @2x correctly.
    guard let image = context.makeImage() else {
        print("Failed to create image")
        exit(1)
    }
    let url = URL(fileURLWithPath: outputPath)
    guard let dest = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil) else {
        print("Failed to create image destination")
        exit(1)
    }
    let dpi = 72.0 * Double(scale)
    CGImageDestinationAddImage(dest, image, [
        kCGImagePropertyDPIWidth: dpi,
        kCGImagePropertyDPIHeight: dpi,
    ] as CFDictionary)
    CGImageDestinationFinalize(dest)

    print("Generated: \(outputPath) (\(w)x\(h) @\(scale)x)")
}

let outputDir = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "assets"
generateBackground(scale: 1, outputPath: "\(outputDir)/dmg-background.png")
generateBackground(scale: 2, outputPath: "\(outputDir)/dmg-background@2x.png")
