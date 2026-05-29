//
//  OnboardingViewModel.swift
//  WolfWave
//
//  Created by Nathanial Henniges on 2026-02-06.
//  Copyright © 2026 MrDemonWolf, Inc. All rights reserved.
//

import Foundation
import Observation

/// Manages step navigation and completion persistence for the onboarding wizard.
@MainActor
@Observable
final class OnboardingViewModel {

    // MARK: - Step Definition

    /// Ordered onboarding steps.
    ///
    /// Streaming-related steps (Twitch, OBS) are kept adjacent so the user mentally
    /// finishes "stream stuff" before moving to system-level prefs and Apple Music.
    enum OnboardingStep: Int, CaseIterable {
        case welcome = 0
        case discordConnect = 1
        case twitchConnect = 2
        case obsWidget = 3
        case preferences = 4
        case appleMusicAccess = 5
        case menuBarPointer = 6

        /// Short spoken name for VoiceOver, used in the progress indicator's
        /// accessibility value (e.g. "Step 3 of 7: Twitch").
        nonisolated var accessibilityTitle: String {
            switch self {
            case .welcome: return "Welcome"
            case .discordConnect: return "Discord"
            case .twitchConnect: return "Twitch"
            case .obsWidget: return "OBS Widget"
            case .preferences: return "Preferences"
            case .appleMusicAccess: return "Apple Music Access"
            case .menuBarPointer: return "Menu Bar"
            }
        }
    }

    // MARK: - Observable State

    var currentStep: OnboardingStep = .welcome
    var showCompletion = false

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
        showCompletion = true
        Log.info("OnboardingViewModel: Onboarding completed", category: "App")
    }

    /// Whether onboarding has been completed on a previous launch.
    static var hasCompletedOnboarding: Bool {
        UserDefaults.standard.bool(forKey: AppConstants.UserDefaults.hasCompletedOnboarding)
    }
}
