//
//  OnboardingStepScaffold.swift
//  WolfWave
//
//  Created by Nathanial Henniges on 2026-05-25.
//  Copyright © 2026 MrDemonWolf, Inc. All rights reserved.
//

import SwiftUI

/// Shared header-anchored layout for every onboarding integration step.
///
/// Locks the icon → title → description block to a constant vertical position
/// across steps so it doesn't drift when a step's `extras` block changes height.
/// Previously each step rolled its own `VStack` with Spacer top + bottom, which
/// centered the whole column and shifted the icon whenever extras were added.
struct OnboardingStepScaffold<Icon: View, Extras: View>: View {

    // MARK: - Properties

    let title: String
    let description: String

    @ViewBuilder var icon: () -> Icon
    @ViewBuilder var extras: () -> Extras

    // MARK: - Body

    var body: some View {
        VStack(spacing: DSSpace.s7) {
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
            .padding(.top, DSSpace.s8)
            .padding(.horizontal, DSSpace.s8)

            extras()
                .frame(maxWidth: 440)
                .padding(.horizontal, DSSpace.s8)

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity)
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
            RoundedRectangle(cornerRadius: 12)
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
