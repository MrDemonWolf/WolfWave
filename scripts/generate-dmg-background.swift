#!/usr/bin/swift
// Generates DMG background images for WolfWave installer
// Usage: swift generate-dmg-background.swift <output-dir>

import AppKit
import CoreGraphics
import Foundation

func generateBackground(width: Int, height: Int, scale: Int, outputPath: String) {
    let scaledWidth = width * scale
    let scaledHeight = height * scale

    let colorSpace = CGColorSpaceCreateDeviceRGB()
    guard let context = CGContext(
        data: nil,
        width: scaledWidth,
        height: scaledHeight,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: colorSpace,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else {
        print("Failed to create graphics context")
        exit(1)
    }

    // Background gradient — dark charcoal to slightly lighter
    let gradientColors = [
        CGColor(red: 0.11, green: 0.11, blue: 0.13, alpha: 1.0),
        CGColor(red: 0.16, green: 0.16, blue: 0.19, alpha: 1.0),
    ]
    let gradient = CGGradient(
        colorsSpace: colorSpace,
        colors: gradientColors as CFArray,
        locations: [0.0, 1.0]
    )!
    context.drawLinearGradient(
        gradient,
        start: CGPoint(x: 0, y: CGFloat(scaledHeight)),
        end: CGPoint(x: 0, y: 0),
        options: []
    )

    // Subtle center glow
    let glowColors = [
        CGColor(red: 0.25, green: 0.45, blue: 0.85, alpha: 0.08),
        CGColor(red: 0.25, green: 0.45, blue: 0.85, alpha: 0.0),
    ]
    let glowGradient = CGGradient(
        colorsSpace: colorSpace,
        colors: glowColors as CFArray,
        locations: [0.0, 1.0]
    )!
    let centerX = CGFloat(scaledWidth) / 2.0
    let centerY = CGFloat(scaledHeight) * 0.45
    context.drawRadialGradient(
        glowGradient,
        startCenter: CGPoint(x: centerX, y: centerY),
        startRadius: 0,
        endCenter: CGPoint(x: centerX, y: centerY),
        endRadius: CGFloat(scaledWidth) * 0.5,
        options: []
    )

    // Draw arrow pointing right (between app icon and Applications folder positions)
    let arrowCenterX = CGFloat(scaledWidth) / 2.0
    let arrowCenterY = CGFloat(scaledHeight) * 0.50
    let arrowScale = CGFloat(scale)

    context.setFillColor(CGColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 0.25))

    // Arrow shaft
    let shaftWidth: CGFloat = 60 * arrowScale
    let shaftHeight: CGFloat = 8 * arrowScale
    let shaftRect = CGRect(
        x: arrowCenterX - shaftWidth / 2 - 5 * arrowScale,
        y: arrowCenterY - shaftHeight / 2,
        width: shaftWidth,
        height: shaftHeight
    )
    context.fill(shaftRect)

    // Arrow head (triangle)
    let headSize: CGFloat = 20 * arrowScale
    let headX = arrowCenterX + shaftWidth / 2 - 5 * arrowScale
    context.beginPath()
    context.move(to: CGPoint(x: headX, y: arrowCenterY + headSize))
    context.addLine(to: CGPoint(x: headX + headSize * 1.2, y: arrowCenterY))
    context.addLine(to: CGPoint(x: headX, y: arrowCenterY - headSize))
    context.closePath()
    context.fillPath()

    // Draw "Drag to install" text
    let fontSize: CGFloat = 13.0 * CGFloat(scale)
    let font = CTFontCreateWithName("Helvetica Neue" as CFString, fontSize, nil)
    let textString = "Drag to install"
    let attributes: [NSAttributedString.Key: Any] = [
        .font: font,
        .foregroundColor: NSColor(white: 1.0, alpha: 0.4),
    ]
    let attrString = NSAttributedString(string: textString, attributes: attributes)
    let line = CTLineCreateWithAttributedString(attrString)
    let textBounds = CTLineGetBoundsWithOptions(line, .useOpticalBounds)
    let textX = arrowCenterX - textBounds.width / 2
    let textY = arrowCenterY - 30 * arrowScale

    context.textPosition = CGPoint(x: textX, y: textY)
    CTLineDraw(line, context)

    // Export as PNG
    guard let image = context.makeImage() else {
        print("Failed to create image")
        exit(1)
    }

    let url = URL(fileURLWithPath: outputPath)
    guard let destination = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil) else {
        print("Failed to create image destination")
        exit(1)
    }

    // Set DPI metadata for proper scaling
    let dpi = 72.0 * Double(scale)
    let properties: [CFString: Any] = [
        kCGImagePropertyDPIWidth: dpi,
        kCGImagePropertyDPIHeight: dpi,
    ]
    CGImageDestinationAddImage(destination, image, properties as CFDictionary)
    CGImageDestinationFinalize(destination)

    print("Generated: \(outputPath) (\(scaledWidth)x\(scaledHeight) @\(scale)x)")
}

// Main
let outputDir: String
if CommandLine.arguments.count > 1 {
    outputDir = CommandLine.arguments[1]
} else {
    outputDir = "assets"
}

generateBackground(width: 540, height: 320, scale: 1, outputPath: "\(outputDir)/dmg-background.png")
generateBackground(width: 540, height: 320, scale: 2, outputPath: "\(outputDir)/dmg-background@2x.png")
