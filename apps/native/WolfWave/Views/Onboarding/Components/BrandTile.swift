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
/// Renders a brand-colored fill (`Color` or `LinearGradient`) with an inner light highlight,
/// soft brand-tinted shadow glow, and centers an arbitrary glyph (typically `Image` at white tint).
struct BrandTile<Background: ShapeStyle, Glyph: View>: View {

    // MARK: - Properties

    let background: Background
    let glowColor: Color
    let glyph: Glyph

    // MARK: - Body

    var body: some View {
        RoundedRectangle(cornerRadius: AppConstants.OnboardingUI.brandTileRadius, style: .continuous)
            .fill(background)
            .overlay(
                RoundedRectangle(cornerRadius: AppConstants.OnboardingUI.brandTileRadius, style: .continuous)
                    .stroke(
                        LinearGradient(
                            colors: [Color.white.opacity(0.30), Color.white.opacity(0.0)],
                            startPoint: .top,
                            endPoint: .bottom
                        ),
                        lineWidth: 0.5
                    )
            )
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
                .font(.system(size: DSFont.Size.x24, weight: .bold))
                .foregroundStyle(.white)
        )

        BrandTile(
            background: AnyShapeStyle(AppConstants.Brand.discord),
            glowColor: AppConstants.Brand.discord,
            glyph: Image(systemName: "bubble.left.and.bubble.right.fill")
                .font(.system(size: DSFont.Size.xl, weight: .bold))
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
                .font(.system(size: DSFont.Size.x24, weight: .bold))
                .foregroundStyle(.white)
        )
    }
    .padding()
}
