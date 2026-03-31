//
//  OnboardingView.swift
//  wolfwave
//
//  Created by MrDemonWolf, Inc. on 2/6/26.
//

import SwiftUI

/// First-launch onboarding wizard with progress dots, step content, and navigation.
///
/// Steps: Welcome, Twitch, Discord, WebSocket & OBS Widget. Hosted in a dedicated `NSWindow`
/// created by `AppDelegate.showOnboarding()`.
struct OnboardingView: View {

    // MARK: - State

    @State private var viewModel = OnboardingViewModel()
    @State private var twitchViewModel = TwitchViewModel()

    @AppStorage(AppConstants.UserDefaults.discordPresenceEnabled)
    private var discordPresenceEnabled = false

    @AppStorage(AppConstants.UserDefaults.websocketEnabled)
    private var websocketEnabled = false

    /// Called when onboarding completes to dismiss the window.
    var onComplete: () -> Void

    /// Tracks navigation direction for slide transitions.
    @State private var navigationDirection: Edge = .trailing

    // MARK: - Body

    var body: some View {
        Group {
            if viewModel.showCompletion {
                OnboardingCompletionView(onDismiss: onComplete)
                    .transition(.opacity)
            } else {
                VStack(spacing: 0) {
                    progressDots
                        .padding(.top, 20)
                        .padding(.bottom, 16)

                    stepContent
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .clipped()
                        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: viewModel.currentStep)

                    Divider()

                    navigationBar
                        .padding(.horizontal, 24)
                        .padding(.vertical, 16)
                }
            }
        }
        .frame(
            width: AppConstants.OnboardingUI.windowWidth,
            height: AppConstants.OnboardingUI.windowHeight
        )
        .background(Color(nsColor: .windowBackgroundColor))
        .animation(.easeInOut(duration: 0.3), value: viewModel.showCompletion)
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
                    .scaleEffect(step == viewModel.currentStep ? 1.3 : 1.0)
                    .animation(.spring(response: 0.3, dampingFraction: 0.6), value: viewModel.currentStep)
                    .accessibilityHidden(true)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Setup progress")
        .accessibilityValue("Step \(viewModel.currentStep.rawValue + 1) of \(OnboardingViewModel.OnboardingStep.allCases.count)")
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
            insertion: .move(edge: navigationDirection).combined(with: .opacity),
            removal: .move(edge: navigationDirection == .trailing ? .leading : .trailing).combined(with: .opacity)
        ))
    }

    // MARK: - Navigation Bar

    private var navigationBar: some View {
        HStack {
            // Left side: "Back" and "Skip All" always rendered, toggled via opacity
            // to prevent layout jumping when switching steps.
            ZStack(alignment: .leading) {
                Button("Back") {
                    navigationDirection = .leading
                    cancelTwitchOAuthIfNeeded()
                    viewModel.goToPreviousStep()
                }
                .buttonStyle(.bordered)
                .controlSize(.regular)
                .pointerCursor()
                .opacity(viewModel.isFirstStep ? 0 : 1)
                .disabled(viewModel.isFirstStep)
                .accessibilityLabel("Go back")
                .accessibilityHint("Returns to the previous setup step")

                Button("Skip All") {
                    finishOnboarding()
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .pointerCursor()
                .opacity(viewModel.isFirstStep ? 1 : 0)
                .disabled(!viewModel.isFirstStep)
                .accessibilityLabel("Skip all steps")
                .accessibilityHint("Skips the setup wizard and uses default settings")
            }

            Spacer()

            // Right side: "Skip" always rendered, toggled via opacity
            Button("Skip") {
                navigationDirection = .trailing
                cancelTwitchOAuthIfNeeded()
                viewModel.goToNextStep()
            }
            .buttonStyle(.bordered)
            .controlSize(.regular)
            .pointerCursor()
            .opacity(shouldShowSkip ? 1 : 0)
            .disabled(!shouldShowSkip)
            .accessibilityLabel("Skip this step")
            .accessibilityHint("Skips the current setup step without making changes")

            if viewModel.isLastStep {
                Button("Finish") {
                    finishOnboarding()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)
                .pointerCursor()
                .accessibilityLabel("Finish setup")
                .accessibilityHint("Completes the setup wizard and starts using WolfWave")
            } else {
                Button("Next") {
                    navigationDirection = .trailing
                    cancelTwitchOAuthIfNeeded()
                    viewModel.goToNextStep()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)
                .pointerCursor()
                .accessibilityLabel("Next step")
                .accessibilityHint("Continues to the next setup step")
            }
        }
        .transaction { $0.animation = nil }
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

    /// Cancels any in-progress Twitch OAuth polling when leaving the Twitch step.
    private func cancelTwitchOAuthIfNeeded() {
        guard viewModel.currentStep == .twitchConnect else { return }
        if case .authorizing = twitchViewModel.integrationState {
            twitchViewModel.cancelOAuth()
        }
    }

    /// Persists the completion flag and shows the celebration screen.
    private func finishOnboarding() {
        viewModel.completeOnboarding()
    }
}
