//
//  OnboardingWelcomeStepView.swift
//  wolfwave
//
//  Created by MrDemonWolf, Inc. on 2/6/26.
//

import SwiftUI

/// Pure-hero welcome step: brand-tinted wolf mark, headline, plain-language
/// tagline, and a short privacy line. No integration chip row — the next four
/// steps brand each integration on their own.
struct OnboardingWelcomeStepView: View {

    // MARK: - Animation State

    @State private var heroVisible = false
    @State private var taglineVisible = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // MARK: - Layout Constants

    /// Hero mark render size. Lives here instead of inlined as a literal so
    /// `bun run ds:lint` stays clean — matches widget `tray` hero size.
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
                    .font(.system(size: DSFont.Size.x26, weight: .bold))
                    .opacity(heroVisible ? 1 : 0)

                Text("Share what you're listening to — everywhere.")
                    .font(.system(size: DSFont.Size.md))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .opacity(taglineVisible ? 1 : 0)
            }

            privacyLine
                .opacity(taglineVisible ? 1 : 0)

            Spacer()
        }
        .padding(.horizontal, DSSpace.s10)
        .task {
            if reduceMotion {
                heroVisible = true
                taglineVisible = true
                return
            }
            withAnimation(DSMotion.Spring.bouncy) {
                heroVisible = true
            }
            try? await Task.sleep(for: .milliseconds(180))
            withAnimation(.easeOut(duration: DSMotion.Duration.slow)) {
                taglineVisible = true
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
