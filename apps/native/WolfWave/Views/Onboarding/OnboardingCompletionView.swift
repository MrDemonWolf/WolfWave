//
//  OnboardingCompletionView.swift
//  WolfWave
//
//  Created by Nathanial Henniges on 2026-03-20.
//  Copyright © 2026 MrDemonWolf, Inc. All rights reserved.
//

import SwiftUI

/// Celebration screen shown after onboarding completes. The animated
/// howl-wave bars on the `WolfHeroMark` are the celebration cue. No
/// separate checkmark.
struct OnboardingCompletionView: View {

    // MARK: - Properties

    /// Called after the animation sequence to dismiss the onboarding window.
    var onDismiss: () -> Void

    // MARK: - Animation State

    @State private var showHero = false
    @State private var showText = false

    /// Guards `onDismiss` so the auto-timer and a manual tap can't both fire it.
    @State private var didDismiss = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // MARK: - Layout Constants

    private static let heroSize: CGFloat = DSDimension.Onboarding.brandTileSize + DSSpace.s10

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
            .offset(y: showHero ? 0 : -DSSpace.s10)
            .opacity(showHero ? 1 : 0)
            .animation(
                reduceMotion
                    ? .none
                    : .interpolatingSpring(stiffness: 200, damping: 14),
                value: showHero
            )

            VStack(spacing: DSSpace.s2) {
                Text("Howl yeah, you're set.")
                    .font(.system(size: DSFont.Size.x3xl, weight: .bold))
                    .multilineTextAlignment(.center)

                Text("WolfWave's in your menu bar. Click the wolf any time.")
                    .font(.system(size: DSFont.Size.base))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .opacity(showText ? 1 : 0)
            .animation(
                reduceMotion ? .none : .easeOut(duration: DSMotion.Duration.long),
                value: showText
            )

            Spacer()

            Text(Self.copyrightLine)
                .font(.system(size: DSFont.Size.xs))
                .foregroundStyle(.tertiary)
                .padding(.bottom, DSSpace.s4)
                .opacity(showText ? 1 : 0)
                .animation(
                    reduceMotion ? .none : .easeOut(duration: DSMotion.Duration.long),
                    value: showText
                )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
        // Tap anywhere to dismiss early instead of waiting out the timer.
        .contentShape(Rectangle())
        .onTapGesture { dismissOnce() }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Setup complete. WolfWave is in your menu bar.")
        .accessibilityHint("Tap to close")
        .accessibilityAddTraits(.isButton)
        .task {
            if reduceMotion {
                showHero = true
                showText = true
                try? await Task.sleep(for: .milliseconds(1200))
                guard !Task.isCancelled else { return }
                dismissOnce()
            } else {
                showHero = true
                try? await Task.sleep(for: .milliseconds(280))
                guard !Task.isCancelled else { return }
                showText = true
                try? await Task.sleep(for: .milliseconds(1500))
                guard !Task.isCancelled else { return }
                dismissOnce()
            }
        }
    }

    // MARK: - Dismiss

    /// Fires `onDismiss` at most once, whether triggered by the auto-timer or a
    /// manual tap.
    private func dismissOnce() {
        guard !didDismiss else { return }
        didDismiss = true
        onDismiss()
    }

    // MARK: - Copyright

    /// Hardcoded for now. When the config refactor lands a `COPYRIGHT_HOLDER`
    /// key, swap to `AppConstants.copyrightHolder`.
    private static var copyrightLine: String {
        let year = Calendar.current.component(.year, from: Date())
        return "© \(year) MrDemonWolf, Inc."
    }
}

// MARK: - Previews

#Preview {
    OnboardingCompletionView(onDismiss: {})
        .frame(
            width: AppConstants.OnboardingUI.windowWidth,
            height: AppConstants.OnboardingUI.windowHeight
        )
}
