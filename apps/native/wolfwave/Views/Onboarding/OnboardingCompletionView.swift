//
//  OnboardingCompletionView.swift
//  wolfwave
//
//  Created by MrDemonWolf, Inc. on 3/19/26.
//

import SwiftUI

/// Celebration screen shown after onboarding completes, with sequenced animations before auto-dismiss.
struct OnboardingCompletionView: View {

    // MARK: - Properties

    /// Called after the animation sequence to dismiss the onboarding window.
    var onDismiss: () -> Void

    // MARK: - Animation State

    @State private var showIcon = false
    @State private var showText = false
    @State private var showCheck = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // MARK: - Body

    var body: some View {
        VStack(spacing: 20) {
            Spacer()

            // App icon — drops in with spring bounce
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .scaledToFit()
                .frame(width: 80, height: 80)
                .offset(y: showIcon ? 0 : -40)
                .opacity(showIcon ? 1 : 0)
                .animation(
                    reduceMotion
                        ? .none
                        : .interpolatingSpring(stiffness: 200, damping: 12),
                    value: showIcon
                )
                .accessibilityLabel("WolfWave app icon")

            // Title and subtitle — fade in together
            VStack(spacing: 8) {
                Text("You're all set!")
                    .font(.system(size: 24, weight: .bold))

                Text("WolfWave is running in your menu bar.")
                    .font(.system(size: 15))
                    .foregroundStyle(.secondary)
            }
            .opacity(showText ? 1 : 0)
            .animation(
                reduceMotion ? .none : .easeOut(duration: 0.4),
                value: showText
            )

            // Green checkmark — scales in with spring
            Image(systemName: "checkmark.circle.fill")
                .resizable()
                .scaledToFit()
                .frame(width: 44, height: 44)
                .foregroundStyle(.green)
                .scaleEffect(showCheck ? 1 : 0)
                .opacity(showCheck ? 1 : 0)
                .animation(
                    reduceMotion
                        ? .none
                        : .spring(response: 0.5, dampingFraction: 0.6),
                    value: showCheck
                )

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
        .task {
            if reduceMotion {
                showIcon = true
                showText = true
                showCheck = true
                try? await Task.sleep(nanoseconds: 1_500_000_000)
                guard !Task.isCancelled else { return }
                onDismiss()
            } else {
                showIcon = true
                try? await Task.sleep(nanoseconds: 300_000_000)
                guard !Task.isCancelled else { return }
                showText = true
                try? await Task.sleep(nanoseconds: 300_000_000)
                guard !Task.isCancelled else { return }
                showCheck = true
                try? await Task.sleep(nanoseconds: 1_900_000_000)
                guard !Task.isCancelled else { return }
                onDismiss()
            }
        }
    }
}
