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
                    .font(.system(size: 26, weight: .bold))
                    .opacity(heroVisible ? 1 : 0)

                Text("Share what you're listening to — everywhere.")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .opacity(taglineVisible ? 1 : 0)
            }

            brandLine
                .opacity(brandLineVisible ? 1 : 0)
                .offset(y: brandLineVisible ? 0 : 6)

            Spacer()
        }
        .padding(.horizontal, 32)
        .task {
            if reduceMotion {
                heroVisible = true
                taglineVisible = true
                brandLineVisible = true
                return
            }
            withAnimation(.spring(response: 0.45, dampingFraction: 0.78)) {
                heroVisible = true
            }
            try? await Task.sleep(nanoseconds: 180_000_000)
            withAnimation(.easeOut(duration: 0.30)) {
                taglineVisible = true
            }
            try? await Task.sleep(nanoseconds: 140_000_000)
            withAnimation(.easeOut(duration: 0.30)) {
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
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
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

    @ViewBuilder
    private func brandChip(image: String, color: Color) -> some View {
        Image(image)
            .renderingMode(.template)
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(width: 16, height: 16)
            .foregroundStyle(color)
    }

    @ViewBuilder
    private func brandChip(systemSymbol: String, color: Color) -> some View {
        Image(systemName: systemSymbol)
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(color)
            .frame(width: 18, height: 16)
    }
}

// MARK: - Preview

#Preview {
    OnboardingWelcomeStepView()
        .frame(width: 600, height: 380)
}
