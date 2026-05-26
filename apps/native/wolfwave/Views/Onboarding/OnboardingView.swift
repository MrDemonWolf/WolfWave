//
//  OnboardingView.swift
//  WolfWave
//
//  Created by Nathanial Henniges on 2026-02-06.
//  Copyright © 2026 MrDemonWolf, Inc. All rights reserved.
//

import SwiftUI

/// First-launch onboarding wizard with progress dots, step content, and navigation.
///
/// Steps: Welcome → Discord → Twitch → OBS → Preferences → Apple Music → Menu bar pointer.
/// Hosted in a dedicated `NSWindow` created by `AppDelegate.showOnboarding()`.
struct OnboardingView: View {

    // MARK: - State

    @State private var viewModel = OnboardingViewModel()
    @State private var twitchViewModel = TwitchViewModel()

    @AppStorage(AppConstants.UserDefaults.discordPresenceEnabled)
    private var discordPresenceEnabled = false

    @AppStorage(AppConstants.UserDefaults.websocketEnabled)
    private var websocketEnabled = false

    @AppStorage(AppConstants.UserDefaults.launchAtLogin)
    private var launchAtLogin = false

    /// Called when onboarding completes to dismiss the window.
    var onComplete: () -> Void

    /// Tracks navigation direction for slide transitions.
    @State private var navigationDirection: Edge = .trailing

    /// Re-read on every step change so the Skip button stays in sync with
    /// permission grants without needing each step view to publish state up.
    @State private var musicPermissionState: MusicPermissionState = MusicPermissionChecker.currentState()

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // MARK: - Body

    var body: some View {
        Group {
            if viewModel.showCompletion {
                OnboardingCompletionView(onDismiss: onComplete)
                    .transition(.opacity)
            } else {
                VStack(spacing: 0) {
                    progressDots
                        .padding(.top, DSSpace.s7)
                        .padding(.bottom, DSSpace.s6)

                    GeometryReader { geo in
                        ScrollView(.vertical, showsIndicators: false) {
                            stepContent
                                .frame(maxWidth: .infinity)
                                .frame(minHeight: geo.size.height)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .clipped()
                        .animation(DSMotion.Spring.snappy, value: viewModel.currentStep)
                    }

                    Divider()

                    navigationBar
                        .padding(.horizontal, DSSpace.s8)
                        .padding(.vertical, DSSpace.s6)
                        .background(.regularMaterial)
                }
            }
        }
        .frame(
            width: AppConstants.OnboardingUI.windowWidth,
            height: AppConstants.OnboardingUI.windowHeight
        )
        .background(Color(nsColor: .windowBackgroundColor))
        .animation(.easeInOut(duration: DSMotion.Duration.slow), value: viewModel.showCompletion)
        .onChange(of: viewModel.currentStep) { _, _ in
            musicPermissionState = MusicPermissionChecker.currentState()
        }
    }

    // MARK: - Progress Dots

    private var progressDots: some View {
        HStack(spacing: 8) {
            ForEach(OnboardingViewModel.OnboardingStep.allCases, id: \.rawValue) { step in
                ZStack {
                    Circle()
                        .fill(step == viewModel.currentStep
                            ? Color.accentColor
                            : Color.secondary.opacity(0.3))
                        .frame(width: 8, height: 8)
                        .scaleEffect(step == viewModel.currentStep ? 1.3 : 1.0)
                        .shadow(
                            color: step == viewModel.currentStep ? Color.accentColor.opacity(0.40) : .clear,
                            radius: 3, x: 0, y: 1
                        )
                        .animation(DSMotion.Spring.gentle, value: viewModel.currentStep)
                }
                .frame(width: 12, height: 12)
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
            case .discordConnect:
                OnboardingDiscordStepView(presenceEnabled: $discordPresenceEnabled)
            case .twitchConnect:
                OnboardingTwitchStepView(twitchViewModel: twitchViewModel)
            case .obsWidget:
                OnboardingOBSWidgetStepView(websocketEnabled: $websocketEnabled)
            case .preferences:
                OnboardingPreferencesStepView(launchAtLogin: $launchAtLogin)
            case .appleMusicAccess:
                OnboardingAppleMusicStepView()
            case .menuBarPointer:
                OnboardingMenuBarPointerStepView()
            }
        }
        .id(viewModel.currentStep)
        .transition(reduceMotion
            ? AnyTransition.opacity
            : .asymmetric(
                insertion: .move(edge: navigationDirection).combined(with: .opacity),
                removal: .move(edge: navigationDirection == .trailing ? .leading : .trailing).combined(with: .opacity)
            )
        )
    }

    // MARK: - Navigation Bar

    private var navigationBar: some View {
        HStack {
            // Left: Back (≥step 2) + Skip All (when not on the last step).
            // Back is rendered as a hidden placeholder on step 1 so the rest of
            // the bar doesn't shift horizontally between steps.
            HStack(spacing: 8) {
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
                .accessibilityHidden(viewModel.isFirstStep)
                .accessibilityLabel("Go back")
                .accessibilityHint("Returns to the previous setup step")
                .accessibilityIdentifier("onboarding.back")

                Button("Skip All") {
                    finishOnboarding()
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .pointerCursor()
                .opacity(viewModel.isLastStep ? 0 : 1)
                .disabled(viewModel.isLastStep)
                .accessibilityHidden(viewModel.isLastStep)
                .accessibilityLabel("Skip all steps")
                .accessibilityHint("Skips the setup wizard and uses default settings")
                .accessibilityIdentifier("onboarding.skipAll")
            }

            Spacer()

            // Right: Skip (toggled via opacity to keep layout stable) + Next/Finish.
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
            .accessibilityIdentifier("onboarding.skip")

            if viewModel.isLastStep {
                Button("Finish") {
                    finishOnboarding()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)
                .pointerCursor()
                .accessibilityLabel("Finish setup")
                .accessibilityHint("Completes the setup wizard and starts using WolfWave")
                .accessibilityIdentifier("onboarding.finish")
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
                .accessibilityIdentifier("onboarding.next")
            }
        }
        .transaction { $0.animation = nil }
    }

    // MARK: - Helpers

    /// Returns `true` only for steps where Skip means something different from
    /// "Next with the toggle off" — i.e. OAuth and system permissions.
    private var shouldShowSkip: Bool {
        switch viewModel.currentStep {
        case .twitchConnect:
            return !twitchViewModel.credentialsSaved
        case .appleMusicAccess:
            return musicPermissionState != .granted
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

// MARK: - Previews

#Preview {
    OnboardingView(onComplete: {})
}
