//
//  BrandTile.swift
//  WolfWave
//
//  Created by Nathanial Henniges on 2026-05-07.
//  Copyright © 2026 MrDemonWolf, Inc. All rights reserved.
//

import SwiftUI

/// 56×56 rounded-square brand tile used as the visual anchor for each onboarding integration step.
///
/// Renders a flat brand-colored fill (`Color` or `LinearGradient`) with a soft
/// brand-tinted shadow glow, and centers an arbitrary glyph (typically `Image`
/// at white tint). No inner-highlight bevel — flat by default per brand rules.
// MARK: - BrandTileGlyph

/// Glyph sizing standards for `BrandTile`. Lives in a non-generic enum because
/// `BrandTile` is generic, and a static on a generic type can't be referenced
/// without specifying its type parameters. One source of truth so every step's
/// glyph renders at the same size instead of each call site picking its own.
enum BrandTileGlyph {
    /// Font for an SF Symbol glyph inside the tile (size + weight).
    static var font: Font {
        .system(size: DSFont.Size.x3xl, weight: .semibold)
    }

    /// Square edge for a brand-logo image glyph (template-rendered asset).
    /// Keeps Discord / Twitch / OBS marks at one size.
    static var assetSize: CGFloat { 30 }
}

// MARK: - BrandTile

struct BrandTile<Background: ShapeStyle, Glyph: View>: View {

    // MARK: - Properties

    let background: Background
    let glowColor: Color
    let glyph: Glyph

    // MARK: - Body

    var body: some View {
        // Flat by default: a colored fill defined by a shallow brand-tinted
        // shadow, no glassy white inner-highlight bevel. (See the flat-surface
        // brand rule — no inset white highlights.)
        RoundedRectangle(cornerRadius: AppConstants.OnboardingUI.brandTileRadius, style: .continuous)
            .fill(background)
            .frame(
                width: AppConstants.OnboardingUI.brandTileSize,
                height: AppConstants.OnboardingUI.brandTileSize
            )
            .overlay(glyph)
            .shadow(color: glowColor.opacity(0.40), radius: 11, x: 0, y: 8)
            .accessibilityHidden(true)
    }
}

// MARK: - Previews

#Preview("Brand tiles") {
    HStack(spacing: 24) {
        BrandTile(
            background: AnyShapeStyle(AppConstants.Brand.twitch),
            glowColor: AppConstants.Brand.twitch,
            glyph: Image(systemName: "bolt.fill")
                .font(BrandTileGlyph.font)
                .foregroundStyle(.white)
        )

        BrandTile(
            background: AnyShapeStyle(AppConstants.Brand.discord),
            glowColor: AppConstants.Brand.discord,
            glyph: Image(systemName: "bubble.left.and.bubble.right.fill")
                .font(BrandTileGlyph.font)
                .foregroundStyle(.white)
        )

        BrandTile(
            background: AnyShapeStyle(
                LinearGradient(
                    colors: [
                        AppConstants.Brand.appleMusicGradientStart,
                        AppConstants.Brand.appleMusicGradientEnd,
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            ),
            glowColor: AppConstants.Brand.appleMusicGradientEnd,
            glyph: Image(systemName: "music.note")
                .font(BrandTileGlyph.font)
                .foregroundStyle(.white)
        )
    }
    .padding()
}
