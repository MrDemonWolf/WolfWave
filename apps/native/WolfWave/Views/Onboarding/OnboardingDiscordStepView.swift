//
//  OnboardingDiscordStepView.swift
//  WolfWave
//
//  Created by Nathanial Henniges on 2026-02-13.
//  Copyright © 2026 MrDemonWolf, Inc. All rights reserved.
//

import SwiftUI

/// Discord Rich Presence step. Brand tile + smart toggle card that brightens
/// with brand-tinted glow when enabled.
struct OnboardingDiscordStepView: View {

    // MARK: - Properties

    @Binding var presenceEnabled: Bool

    // MARK: - Body

    var body: some View {
        OnboardingStepScaffold(
            title: "Light up your Discord status",
            description: "Friends see your song, artist, and album art right under your name.",
            icon: {
                BrandTile(
                    background: AnyShapeStyle(AppConstants.Brand.discord),
                    glowColor: AppConstants.Brand.discord,
                    glyph:
                        Image("DiscordLogo")
                            .renderingMode(.template)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: BrandTileGlyph.assetSize, height: BrandTileGlyph.assetSize)
                            .foregroundStyle(.white)
                )
            },
            extras: {
                VStack(spacing: DSSpace.s5) {
                    ToggleSettingRow(
                        title: "Show music on Discord",
                        subtitle: "Updates every time the song changes.",
                        isOn: $presenceEnabled,
                        controlSize: .regular,
                        accessibilityLabel: "Enable Discord Status",
                        accessibilityIdentifier: "onboardingDiscordToggle",
                        onChange: { newValue in
                            NotificationCenter.default.postEnabled(.discordPresenceChanged, enabled: newValue)
                        }
                    )
                    .onboardingTintedToggleShell(
                        isOn: presenceEnabled,
                        tint: AppConstants.Brand.discord,
                        fillOpacity: 0.10,
                        glowOpacity: 0.18,
                        glowRadius: 18,
                        glowYOffset: 6
                    )

                    Text("Make sure Discord is open. We talk to it locally. Nothing leaves your Mac.")
                        .font(.system(size: DSFont.Size.sm))
                        .foregroundStyle(.tertiary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 380)
                }
            }
        )
    }
}

// MARK: - Preview

#Preview {
    OnboardingDiscordStepView(presenceEnabled: .constant(false))
        .frame(width: 600, height: 380)
}
