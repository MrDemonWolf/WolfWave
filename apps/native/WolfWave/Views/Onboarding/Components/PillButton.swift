//
//  PillButton.swift
//  WolfWave
//
//  Created by Nathanial Henniges on 2026-05-07.
//  Copyright © 2026 MrDemonWolf, Inc. All rights reserved.
//

import SwiftUI

/// Pill-shaped primary CTA used in onboarding integration steps (Sign in with Twitch,
/// Grant Apple Music Access, etc.). Renders a brand-colored fill and an inner light
/// highlight. Flat by design: no outer glow halo.
struct PillButton<Label: View>: View {

    // MARK: - Properties

    let action: () -> Void
    let background: AnyShapeStyle
    let label: Label
    var disabled: Bool = false

    // MARK: - Init

    init(
        background: AnyShapeStyle,
        disabled: Bool = false,
        action: @escaping () -> Void,
        @ViewBuilder label: () -> Label
    ) {
        self.background = background
        self.disabled = disabled
        self.action = action
        self.label = label()
    }

    // MARK: - Body

    var body: some View {
        Button(action: action) {
            label
                .font(.system(size: DSFont.Size.md, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, DSSpace.s8)
                .frame(height: 36)
                .background(
                    RoundedRectangle(cornerRadius: AppConstants.OnboardingUI.primaryButtonRadius, style: .continuous).fill(background)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: AppConstants.OnboardingUI.primaryButtonRadius, style: .continuous)
                        .stroke(
                            LinearGradient(
                                colors: [Color.white.opacity(0.30), Color.white.opacity(0.0)],
                                startPoint: .top,
                                endPoint: .bottom
                            ),
                            lineWidth: 0.5
                        )
                )
                .opacity(disabled ? 0.65 : 1)
                .contentShape(RoundedRectangle(cornerRadius: AppConstants.OnboardingUI.primaryButtonRadius, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .pointerCursor()
    }
}

// MARK: - Previews

#Preview("Enabled") {
    PillButton(
        background: AnyShapeStyle(AppConstants.Brand.twitch),
        action: {}
    ) {
        Text("Sign in with Twitch")
    }
    .padding()
    .frame(width: 360)
}

#Preview("Disabled") {
    PillButton(
        background: AnyShapeStyle(AppConstants.Brand.discord),
        disabled: true,
        action: {}
    ) {
        Text("Connect Discord")
    }
    .padding()
    .frame(width: 360)
}
