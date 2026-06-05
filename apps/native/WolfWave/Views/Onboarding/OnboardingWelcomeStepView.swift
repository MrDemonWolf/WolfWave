//
//  OnboardingWelcomeStepView.swift
//  WolfWave
//
//  Created by Nathanial Henniges on 2026-02-06.
//  Copyright © 2026 MrDemonWolf, Inc. All rights reserved.
//

import SwiftUI

/// Pure-hero welcome step: brand-tinted wolf mark, headline, plain-language
/// tagline, and a short privacy line. No integration chip row. The next four
/// steps brand each integration on their own.
struct OnboardingWelcomeStepView: View {

    // MARK: - Animation State

    @State private var heroVisible = false
    @State private var titleVisible = false
    @State private var taglineVisible = false
    @State private var privacyVisible = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Vertical offset applied to text rows before they slide into place.
    private static let entranceRise: CGFloat = DSSpace.s5

    // MARK: - Layout Constants

    /// Hero mark render size. Lives here instead of inlined as a literal so
    /// `bun run ds:lint` stays clean. Matches widget `tray` hero size.
    private static let heroSize: CGFloat = DSDimension.Onboarding.brandTileSize + DSSpace.s10 + DSSpace.s2

    // MARK: - Body

    var body: some View {
        VStack(spacing: DSSpace.s7) {
            Spacer()

            WolfHeroMark(
                size: Self.heroSize,
                style: .brandGradient,
                animatedBars: true,
                reduceMotion: reduceMotion
            )
            .opacity(heroVisible ? 1 : 0)
            .scaleEffect(heroVisible ? 1 : 0.92)

            VStack(spacing: DSSpace.s2) {
                Text("Welcome to WolfWave")
                    .font(.system(size: DSFont.Size.x3xl, weight: .bold))
                    .opacity(titleVisible ? 1 : 0)
                    .offset(y: titleVisible ? 0 : Self.entranceRise)

                Text("The new way to share your Apple Music with everyone.")
                    .font(.system(size: DSFont.Size.md))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .opacity(taglineVisible ? 1 : 0)
                    .offset(y: taglineVisible ? 0 : Self.entranceRise)
            }

            privacyLine
                .opacity(privacyVisible ? 1 : 0)
                .offset(y: privacyVisible ? 0 : Self.entranceRise)

            Spacer()
        }
        .padding(.horizontal, DSSpace.s10)
        .task {
            if reduceMotion {
                heroVisible = true
                titleVisible = true
                taglineVisible = true
                privacyVisible = true
                return
            }
            // Staggered entrance: hero springs in, then title, tagline, and
            // privacy line rise + fade in sequence so the screen reads as a
            // guided reveal rather than a single pop.
            withAnimation(DSMotion.Spring.bouncy) {
                heroVisible = true
            }
            try? await Task.sleep(for: .milliseconds(140))
            withAnimation(DSMotion.Spring.gentle) {
                titleVisible = true
            }
            try? await Task.sleep(for: .milliseconds(110))
            withAnimation(.easeOut(duration: DSMotion.Duration.slow)) {
                taglineVisible = true
            }
            try? await Task.sleep(for: .milliseconds(110))
            withAnimation(.easeOut(duration: DSMotion.Duration.slow)) {
                privacyVisible = true
            }
        }
    }

    // MARK: - Privacy Line

    /// Short one-liner clarifying what WolfWave sees and where the privacy
    /// policy lives, so first-launch consent is explicit.
    private var privacyLine: some View {
        VStack(spacing: DSSpace.s1) {
            Text("Reads your Apple Music track. Shares only what you turn on.")
                .font(.system(size: DSFont.Size.sm))
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)

            if let url = URL(string: AppConstants.URLs.privacyPolicy) {
                Link("Privacy policy", destination: url)
                    .font(.system(size: DSFont.Size.sm))
                    .pointerCursor()
                    .accessibilityLabel("Open WolfWave privacy policy")
                    .accessibilityIdentifier("onboarding.welcome.privacyLink")
            }
        }
    }
}

// MARK: - Preview

#Preview {
    OnboardingWelcomeStepView()
        .frame(width: 600, height: 380)
}
