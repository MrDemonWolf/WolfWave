//
//  OnboardingStepScaffold.swift
//  WolfWave
//
//  Created by Nathanial Henniges on 2026-05-25.
//  Copyright © 2026 MrDemonWolf, Inc. All rights reserved.
//

import SwiftUI

/// Shared centered layout for every onboarding integration step.
///
/// Vertically centers the icon → title → description → extras block while
/// reserving a fixed minimum height for the extras slot. Because the header
/// block is constant-height (icon + fixed-vertical text) and the extras slot
/// has a floor, the (header + extras) column is the same size on every step,
/// so balanced top/bottom spacers land the icon at an identical Y offset
/// across Welcome → Discord → Twitch → … → Completion. Steps whose extras
/// grow beyond the floor (e.g. Twitch device-code state) push the bottom
/// spacer down but never shift the header upward.
struct OnboardingStepScaffold<Icon: View, Extras: View>: View {

    // MARK: - Properties

    let title: String
    let description: String

    @ViewBuilder var icon: () -> Icon
    @ViewBuilder var extras: () -> Extras

    // MARK: - Body

    var body: some View {
        VStack(spacing: DSSpace.s7) {
            Spacer(minLength: 0)

            VStack(spacing: DSSpace.s4) {
                icon()

                VStack(spacing: DSSpace.s1) {
                    Text(title)
                        .font(.system(size: DSFont.Size.xl, weight: .bold))
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)

                    Text(description)
                        .font(.system(size: DSFont.Size.base))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 440)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.horizontal, DSSpace.s8)

            extras()
                .frame(maxWidth: 440)
                .frame(minHeight: DSDimension.Onboarding.stepContentMinHeight, alignment: .center)
                .padding(.horizontal, DSSpace.s8)

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Preview

#Preview("With extras") {
    OnboardingStepScaffold(
        title: "Sample step",
        description: "Header sits at a constant offset regardless of extras height.",
        icon: {
            BrandTile(
                background: AnyShapeStyle(AppConstants.Brand.discord),
                glowColor: AppConstants.Brand.discord,
                glyph:
                    Image(systemName: "bolt.fill")
                        .font(.system(size: DSFont.Size.xl, weight: .bold))
                        .foregroundStyle(.white)
            )
        },
        extras: {
            RoundedRectangle(cornerRadius: DSRadius.lg2)
                .fill(Color.accentColor.opacity(0.10))
                .frame(height: 80)
        }
    )
    .frame(width: 600, height: 480)
}

#Preview("No extras") {
    OnboardingStepScaffold(
        title: "Sample step",
        description: "Header stays put even with empty extras.",
        icon: {
            BrandTile(
                background: AnyShapeStyle(AppConstants.Brand.twitch),
                glowColor: AppConstants.Brand.twitch,
                glyph:
                    Image(systemName: "bolt.fill")
                        .font(.system(size: DSFont.Size.xl, weight: .bold))
                        .foregroundStyle(.white)
            )
        },
        extras: { EmptyView() }
    )
    .frame(width: 600, height: 480)
}
