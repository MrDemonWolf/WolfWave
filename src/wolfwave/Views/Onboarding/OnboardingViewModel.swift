//
//  OnboardingViewModel.swift
//  wolfwave
//
//  Created by MrDemonWolf, Inc. on 2/6/26.
//

import Combine
import Foundation

/// Manages step navigation and completion persistence for the onboarding wizard.
@MainActor
final class OnboardingViewModel: ObservableObject {

    // MARK: - Step Definition

    /// Ordered onboarding steps.
    enum OnboardingStep: Int, CaseIterable {
        case welcome = 0
        case twitchConnect = 1
        case discordConnect = 2
        case obsWidget = 3
    }

    // MARK: - Published State

    @Published var currentStep: OnboardingStep = .welcome

    // MARK: - Navigation

    var isFirstStep: Bool {
        currentStep == OnboardingStep.allCases.first
    }

    var isLastStep: Bool {
        currentStep == OnboardingStep.allCases.last
    }

    var totalSteps: Int {
        OnboardingStep.allCases.count
    }

    /// Advances to the next step if one exists.
    func goToNextStep() {
        guard let next = OnboardingStep(rawValue: currentStep.rawValue + 1) else { return }
        currentStep = next
    }

    /// Returns to the previous step if one exists.
    func goToPreviousStep() {
        guard let prev = OnboardingStep(rawValue: currentStep.rawValue - 1) else { return }
        currentStep = prev
    }

    // MARK: - Completion

    /// Persists the onboarding-completed flag so the wizard won't show again.
    func completeOnboarding() {
        UserDefaults.standard.set(true, forKey: AppConstants.UserDefaults.hasCompletedOnboarding)
        Log.info("Onboarding completed", category: "Onboarding")
    }

    /// Whether onboarding has been completed on a previous launch.
    static var hasCompletedOnboarding: Bool {
        UserDefaults.standard.bool(forKey: AppConstants.UserDefaults.hasCompletedOnboarding)
    }
}
