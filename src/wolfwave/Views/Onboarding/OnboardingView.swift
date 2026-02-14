//
//  OnboardingView.swift
//  wolfwave
//
//  Created by MrDemonWolf, Inc. on 2/6/26.
//

import SwiftUI

/// Root view for the first-launch onboarding wizard.
///
/// Presents a step-by-step guided flow in a dedicated window:
/// 1. Welcome — App overview with feature highlights
/// 2. Twitch Connection — Optional OAuth Device Code flow (skippable)
///
/// Structure:
/// - Top: Progress dots indicator
/// - Center: Step content (swappable with page transitions)
/// - Bottom: Navigation buttons (Back, Next/Skip/Finish)
///
/// Hosted in a dedicated `NSWindow` created by `AppDelegate.showOnboarding()`.
struct OnboardingView: View {

    // MARK: - State

    @StateObject private var viewModel = OnboardingViewModel()
    @StateObject private var twitchViewModel = TwitchViewModel()

    /// Callback invoked when onboarding completes or is skipped.
    ///
    /// AppDelegate uses this to close the onboarding window and transition
    /// to the normal app state.
    var onComplete: () -> Void

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            // Progress indicator
            progressDots
                .padding(.top, 20)
                .padding(.bottom, 16)

            // Step content
            stepContent
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()
                .animation(.easeInOut(duration: 0.25), value: viewModel.currentStep)

            Divider()

            // Navigation bar
            navigationBar
                .padding(.horizontal, 24)
                .padding(.vertical, 16)
        }
        .frame(
            width: AppConstants.OnboardingUI.windowWidth,
            height: AppConstants.OnboardingUI.windowHeight
        )
        .background(Color(nsColor: .windowBackgroundColor))
    }

    // MARK: - Progress Dots

    private var progressDots: some View {
        HStack(spacing: 8) {
            ForEach(OnboardingViewModel.OnboardingStep.allCases, id: \.rawValue) { step in
                Circle()
                    .fill(step == viewModel.currentStep
                        ? Color.accentColor
                        : Color.secondary.opacity(0.3))
                    .frame(width: 8, height: 8)
                    .animation(.easeInOut(duration: 0.2), value: viewModel.currentStep)
            }
        }
    }

    // MARK: - Step Content

    @ViewBuilder
    private var stepContent: some View {
        Group {
            switch viewModel.currentStep {
            case .welcome:
                OnboardingWelcomeStepView()
            case .twitchConnect:
                OnboardingTwitchStepView(twitchViewModel: twitchViewModel)
            case .discordConnect:
                OnboardingDiscordStepView()
            }
        }
        .id(viewModel.currentStep)
        .transition(.asymmetric(
            insertion: .move(edge: .trailing).combined(with: .opacity),
            removal: .move(edge: .leading).combined(with: .opacity)
        ))
    }

    // MARK: - Navigation Bar

    private var navigationBar: some View {
        HStack {
            // Back button (hidden on first step)
            if !viewModel.isFirstStep {
                Button("Back") {
                    viewModel.goToPreviousStep()
                }
                .buttonStyle(.bordered)
                .controlSize(.regular)
                .pointerCursor()
            }

            Spacer()

            // Skip button on optional integration steps
            if viewModel.currentStep == .twitchConnect && !twitchViewModel.credentialsSaved {
                Button("Skip") {
                    viewModel.goToNextStep()
                }
                .buttonStyle(.bordered)
                .controlSize(.regular)
                .pointerCursor()
            } else if viewModel.currentStep == .discordConnect {
                Button("Skip") {
                    finishOnboarding()
                }
                .buttonStyle(.bordered)
                .controlSize(.regular)
                .pointerCursor()
            }

            // Primary action button
            if viewModel.isLastStep {
                Button("Finish") {
                    finishOnboarding()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)
                .pointerCursor()
            } else {
                Button("Next") {
                    viewModel.goToNextStep()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)
                .pointerCursor()
            }
        }
    }

    // MARK: - Helpers

    /// Completes onboarding: persists the flag and notifies AppDelegate.
    private func finishOnboarding() {
        viewModel.completeOnboarding()
        onComplete()
    }
}
