//
//  OnboardingViewModel.swift
//  wolfwave
//
//  Created by MrDemonWolf, Inc. on 2/6/26.
//

import Combine
import Foundation

/// View model for the first-launch onboarding wizard.
///
/// Manages step navigation, progress tracking, and onboarding completion persistence.
/// The wizard walks users through a welcome overview and optional Twitch connection.
///
/// Steps:
/// 1. Welcome — App overview with feature highlights
/// 2. Twitch Connection — Optional OAuth Device Code flow
@MainActor
final class OnboardingViewModel: ObservableObject {

    // MARK: - Step Definition

    /// Onboarding wizard steps, ordered by presentation sequence.
    enum OnboardingStep: Int, CaseIterable {
        case welcome = 0
        case twitchConnect = 1
        case discordConnect = 2
    }

    // MARK: - Published State

    /// The currently displayed onboarding step.
    @Published var currentStep: OnboardingStep = .welcome

    // MARK: - Navigation

    /// Whether the current step is the first step in the wizard.
    var isFirstStep: Bool {
        currentStep == OnboardingStep.allCases.first
    }

    /// Whether the current step is the last step in the wizard.
    var isLastStep: Bool {
        currentStep == OnboardingStep.allCases.last
    }

    /// Total number of steps in the wizard.
    var totalSteps: Int {
        OnboardingStep.allCases.count
    }

    /// Advances to the next step.
    ///
    /// Animation is driven by `.animation(_:value:)` on the view container
    /// to avoid competing animation drivers.
    func goToNextStep() {
        guard let next = OnboardingStep(rawValue: currentStep.rawValue + 1) else { return }
        currentStep = next
    }

    /// Returns to the previous step.
    ///
    /// Animation is driven by `.animation(_:value:)` on the view container
    /// to avoid competing animation drivers.
    func goToPreviousStep() {
        guard let prev = OnboardingStep(rawValue: currentStep.rawValue - 1) else { return }
        currentStep = prev
    }

    // MARK: - Completion

    /// Marks onboarding as completed and persists the flag.
    ///
    /// Called when the user clicks "Finish" or "Skip" in the wizard.
    /// After this, the onboarding window will not appear on subsequent launches.
    func completeOnboarding() {
        UserDefaults.standard.set(true, forKey: AppConstants.UserDefaults.hasCompletedOnboarding)
        Log.info("Onboarding completed", category: "Onboarding")
    }

    /// Whether the first-launch onboarding has been completed previously.
    ///
    /// Used by AppDelegate to decide whether to show the onboarding window on launch.
    static var hasCompletedOnboarding: Bool {
        UserDefaults.standard.bool(forKey: AppConstants.UserDefaults.hasCompletedOnboarding)
    }
}
