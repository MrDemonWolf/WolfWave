//
//  OnboardingToggleCard.swift
//  WolfWave
//
//  Created by Nathanial Henniges on 2026-06-04.
//  Copyright © 2026 MrDemonWolf, Inc. All rights reserved.
//

import SwiftUI

/// Onboarding toggle row: a tinted SF Symbol tile, a title + subtitle, and a
/// trailing switch inside a bordered card.
///
/// Shared by the Preferences and Notifications onboarding steps, which had
/// byte-identical private copies of this layout. Lives in `Onboarding/Components`
/// because it carries the onboarding design language (its own tile radius), not
/// the settings-pane look.
struct OnboardingToggleCard: View {

    // MARK: - Properties

    let icon: String
    let iconColor: Color
    let title: String
    let subtitle: String
    @Binding var isOn: Bool
    let accessibilityLabel: String
    let accessibilityIdentifier: String

    /// When `true` (default) the row draws its own bordered card. Set `false`
    /// to render a chrome-free row meant to live inside a shared grouped
    /// container (the Notifications step stacks three of these under one border).
    var showsCardBackground: Bool = true

    // MARK: - Body

    var body: some View {
        if showsCardBackground {
            row.subtleCardShell(cornerRadius: DSRadius.lg2)
        } else {
            row
        }
    }

    /// The row content: tinted icon tile, title + subtitle, trailing switch.
    /// `body` wraps it in the shared card shell unless the caller stacks the
    /// row inside its own grouped container.
    private var row: some View {
        HStack(spacing: DSSpace.s4) {
            ZStack {
                RoundedRectangle(cornerRadius: AppConstants.OnboardingUI.iconTileRadius, style: .continuous)
                    .fill(iconColor.opacity(0.15))
                    .frame(
                        width: AppConstants.OnboardingUI.iconTileSize,
                        height: AppConstants.OnboardingUI.iconTileSize
                    )

                Image(systemName: icon)
                    .font(.system(size: DSFont.Size.base, weight: .semibold))
                    .foregroundStyle(iconColor)
            }

            VStack(alignment: .leading, spacing: DSSpace.s0) {
                Text(title)
                    .font(.system(size: DSFont.Size.base, weight: .semibold))

                Text(subtitle)
                    .font(.system(size: DSFont.Size.sm))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()

            Toggle("", isOn: $isOn)
                .toggleStyle(.switch)
                .labelsHidden()
                .pointerCursor()
                .accessibilityLabel(accessibilityLabel)
                .accessibilityIdentifier(accessibilityIdentifier)
        }
        .padding(DSSpace.s4)
    }
}

// MARK: - Tinted Toggle Card Shell

/// Card chrome for the onboarding "smart toggle" cards (Discord presence, OBS
/// Stream Widgets): a neutral opaque card when off that brightens with a
/// brand-tinted fill, stroke, and glow when on.
///
/// The off state renders exactly like `subtleCardShell(cornerRadius: DSRadius.lg2)`.
/// The Discord and OBS steps carried byte-identical copies of this chrome that
/// differed only in tint and glow numbers, so those stay parameters.
struct OnboardingTintedToggleShell: ViewModifier {
    /// Whether the feature is on; drives the tinted fill, stroke, and glow.
    let isOn: Bool
    /// Brand tint used for the enabled fill, stroke, and glow shadow.
    let tint: Color
    /// Opacity applied to `tint` for the enabled fill.
    let fillOpacity: Double
    /// Opacity applied to `tint` for the enabled glow shadow.
    let glowOpacity: Double
    /// Glow shadow blur radius.
    let glowRadius: CGFloat
    /// Glow shadow vertical offset.
    let glowYOffset: CGFloat

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: DSRadius.lg2, style: .continuous)
        return content
            .padding(DSSpace.s5)
            .background(
                shape.fill(isOn
                    ? tint.opacity(fillOpacity)
                    : Color(nsColor: .controlBackgroundColor))
            )
            .overlay(
                shape.stroke(
                    isOn
                        ? tint.opacity(0.40)
                        : Color.primary.opacity(0.06),
                    lineWidth: 0.5
                )
            )
            .shadow(
                color: isOn ? tint.opacity(glowOpacity) : .clear,
                radius: glowRadius, x: 0, y: glowYOffset
            )
            .animation(.easeInOut(duration: DSMotion.Duration.base), value: isOn)
    }
}

extension View {
    /// Wraps an onboarding smart-toggle row in the tinted card shell:
    /// neutral card when off, brand-tinted fill + 0.40 stroke + glow when on.
    /// Includes the row's `DSSpace.s5` padding and the on/off animation.
    func onboardingTintedToggleShell(
        isOn: Bool,
        tint: Color,
        fillOpacity: Double,
        glowOpacity: Double,
        glowRadius: CGFloat,
        glowYOffset: CGFloat
    ) -> some View {
        modifier(OnboardingTintedToggleShell(
            isOn: isOn,
            tint: tint,
            fillOpacity: fillOpacity,
            glowOpacity: glowOpacity,
            glowRadius: glowRadius,
            glowYOffset: glowYOffset
        ))
    }
}

// MARK: - Preview

#Preview {
    VStack(spacing: DSSpace.s3) {
        OnboardingToggleCard(
            icon: "bell.badge",
            iconColor: .orange,
            title: "Song change alerts",
            subtitle: "A banner when the track changes.",
            isOn: .constant(true),
            accessibilityLabel: "Song change alerts",
            accessibilityIdentifier: "onboarding.toggle.songChange"
        )
        OnboardingToggleCard(
            icon: "power",
            iconColor: .blue,
            title: "Launch at login",
            subtitle: "Start WolfWave when you sign in.",
            isOn: .constant(false),
            accessibilityLabel: "Launch at login",
            accessibilityIdentifier: "onboarding.toggle.launch"
        )
    }
    .padding()
    .frame(width: 420)
}
