//
//  OnboardingView.swift
//  wolfwave
//
//  Created by MrDemonWolf, Inc. on 2/6/26.
//

import SwiftUI

/// First-launch onboarding wizard with progress dots, step content, and navigation.
///
/// Steps: Welcome, Twitch, Discord, OBS Widget. Hosted in a dedicated `NSWindow`
/// created by `AppDelegate.showOnboarding()`.
struct OnboardingView: View {

    // MARK: - State

    @StateObject private var viewModel = OnboardingViewModel()
    @StateObject private var twitchViewModel = TwitchViewModel()

    @AppStorage(AppConstants.UserDefaults.discordPresenceEnabled)
    private var discordPresenceEnabled = false

    @AppStorage(AppConstants.UserDefaults.websocketEnabled)
    private var websocketEnabled = false

    /// Called when onboarding completes to dismiss the window.
    var onComplete: () -> Void

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            progressDots
                .padding(.top, 20)
                .padding(.bottom, 16)

            stepContent
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()
                .animation(.easeInOut(duration: 0.25), value: viewModel.currentStep)

            Divider()

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
                OnboardingDiscordStepView(presenceEnabled: $discordPresenceEnabled)
            case .obsWidget:
                OnboardingOBSWidgetStepView(websocketEnabled: $websocketEnabled)
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
            if !viewModel.isFirstStep {
                Button("Back") {
                    viewModel.goToPreviousStep()
                }
                .buttonStyle(.bordered)
                .controlSize(.regular)
                .pointerCursor()
            }

            Spacer()

            if shouldShowSkip {
                Button("Skip") {
                    viewModel.goToNextStep()
                }
                .buttonStyle(.bordered)
                .controlSize(.regular)
                .pointerCursor()
            }

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

    /// Returns `true` for optional steps the user hasn't yet enabled.
    private var shouldShowSkip: Bool {
        switch viewModel.currentStep {
        case .twitchConnect:
            return !twitchViewModel.credentialsSaved
        case .discordConnect:
            return !discordPresenceEnabled
        case .obsWidget:
            return !websocketEnabled
        default:
            return false
        }
    }

    /// Persists the completion flag and notifies AppDelegate.
    private func finishOnboarding() {
        viewModel.completeOnboarding()
        onComplete()
    }
}
