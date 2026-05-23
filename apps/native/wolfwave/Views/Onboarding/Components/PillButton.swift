//
//  PillButton.swift
//  wolfwave
//
//  Created by MrDemonWolf, Inc. on 5/7/26.
//

import SwiftUI

/// Pill-shaped primary CTA used in onboarding integration steps (Sign in with Twitch,
/// Grant Apple Music Access, etc.). Renders a brand-colored fill, inner light highlight,
/// and brand-tinted glow shadow.
struct PillButton<Label: View>: View {

    // MARK: - Properties

    let action: () -> Void
    let background: AnyShapeStyle
    let glowColor: Color
    let label: Label
    var disabled: Bool = false

    // MARK: - Init

    init(
        background: AnyShapeStyle,
        glowColor: Color,
        disabled: Bool = false,
        action: @escaping () -> Void,
        @ViewBuilder label: () -> Label
    ) {
        self.background = background
        self.glowColor = glowColor
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
                .shadow(color: glowColor.opacity(0.40), radius: 9, x: 0, y: 6)
                .opacity(disabled ? 0.65 : 1)
                .contentShape(RoundedRectangle(cornerRadius: AppConstants.OnboardingUI.primaryButtonRadius, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .pointerCursor()
    }
}
