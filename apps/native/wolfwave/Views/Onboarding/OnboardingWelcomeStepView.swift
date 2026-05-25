//
//  OnboardingWelcomeStepView.swift
//  wolfwave
//
//  Created by MrDemonWolf, Inc. on 2/6/26.
//

import SwiftUI

/// Pure-hero welcome step: large app icon, headline, plain-language tagline, and a single
/// inline brand line so the user knows what's about to happen without scanning a list.
struct OnboardingWelcomeStepView: View {

    // MARK: - Animation State

    @State private var heroVisible = false
    @State private var taglineVisible = false
    @State private var brandLineVisible = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // MARK: - Body

    var body: some View {
        VStack(spacing: 18) {
            Spacer()

            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .interpolation(.high)
                .scaledToFit()
                .frame(width: 96, height: 96)
                .opacity(heroVisible ? 1 : 0)
                .scaleEffect(heroVisible ? 1 : 0.92)
                .accessibilityLabel("WolfWave app icon")

            VStack(spacing: 8) {
                Text("Welcome to WolfWave")
                    .font(.system(size: DSFont.Size.x26, weight: .bold))
                    .opacity(heroVisible ? 1 : 0)

                Text("Share what you're listening to — everywhere.")
                    .font(.system(size: DSFont.Size.md))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .opacity(taglineVisible ? 1 : 0)
            }

            brandLine
                .opacity(brandLineVisible ? 1 : 0)
                .offset(y: brandLineVisible ? 0 : 6)

            privacyLine
                .opacity(brandLineVisible ? 1 : 0)

            Spacer()
        }
        .padding(.horizontal, DSSpace.s10)
        .task {
            if reduceMotion {
                heroVisible = true
                taglineVisible = true
                brandLineVisible = true
                return
            }
            withAnimation(DSMotion.Spring.bouncy) {
                heroVisible = true
            }
            try? await Task.sleep(for: .milliseconds(180))
            withAnimation(.easeOut(duration: DSMotion.Duration.slow)) {
                taglineVisible = true
            }
            try? await Task.sleep(for: .milliseconds(140))
            withAnimation(.easeOut(duration: DSMotion.Duration.slow)) {
                brandLineVisible = true
            }
        }
    }

    // MARK: - Brand Line

    private var brandLine: some View {
        HStack(spacing: 14) {
            brandChip(image: "AppleMusicLogo", color: AppConstants.Brand.appleMusicGradientEnd)
            dot
            brandChip(image: "TwitchLogo", color: AppConstants.Brand.twitch)
            dot
            brandChip(image: "DiscordLogo", color: AppConstants.Brand.discord)
            dot
            brandChip(systemSymbol: "tv.badge.wifi", color: .accentColor)
        }
        .padding(.horizontal, DSSpace.s6)
        .padding(.vertical, DSSpace.s3)
        .background(
            Capsule(style: .continuous)
                .fill(.regularMaterial)
        )
        .overlay(
            Capsule(style: .continuous)
                .stroke(Color.primary.opacity(0.06), lineWidth: 0.5)
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Connects with Apple Music, Twitch, Discord, and OBS overlays.")
    }

    private var dot: some View {
        Circle()
            .fill(Color.secondary.opacity(0.30))
            .frame(width: 3, height: 3)
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

    /// Tinted brand-asset chip (asset-catalog template image) used in the
    /// "integrates with" pills row.
    ///
    /// - Parameters:
    ///   - image: Asset name of the brand image.
    ///   - color: Tint applied via `.foregroundStyle`.
    @ViewBuilder
    private func brandChip(image: String, color: Color) -> some View {
        Image(image)
            .renderingMode(.template)
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(width: 16, height: 16)
            .foregroundStyle(color)
    }

    /// Tinted SF Symbol variant of `brandChip` for integrations without a
    /// dedicated brand asset (e.g. OBS).
    ///
    /// - Parameters:
    ///   - systemSymbol: SF Symbol name.
    ///   - color: Tint applied via `.foregroundStyle`.
    @ViewBuilder
    private func brandChip(systemSymbol: String, color: Color) -> some View {
        Image(systemName: systemSymbol)
            .font(.system(size: DSFont.Size.md, weight: .semibold))
            .foregroundStyle(color)
            .frame(width: 18, height: 16)
    }
}

// MARK: - Preview

#Preview {
    OnboardingWelcomeStepView()
        .frame(width: 600, height: 380)
}
