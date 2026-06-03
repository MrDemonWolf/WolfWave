//
//  OnboardingFlowIntegrationTests.swift
//  WolfWave
//
//  Created by Nathanial Henniges on 2026-05-29.
//  Copyright © 2026 MrDemonWolf, Inc. All rights reserved.
//

import XCTest

@testable import WolfWave

/// End-to-end traversal of the onboarding wizard: drives `OnboardingViewModel`
/// through every step in order (Welcome → Discord → Twitch → OBS Widget →
/// Preferences → Permissions → Notifications → Menu Bar Pointer → Completion)
/// and confirms the completed flag lands in UserDefaults. Per-step navigation
/// and boundary conditions are covered by `OnboardingViewModelTests`; this
/// suite is the full-walk integration check.
@MainActor
final class OnboardingFlowIntegrationTests: WolfWaveTestCase {

    private var viewModel: OnboardingViewModel!

    override func setUp() {
        super.setUp()
        resetAllSettings()
        viewModel = OnboardingViewModel()
    }

    override func tearDown() {
        resetAllSettings()
        viewModel = nil
        super.tearDown()
    }

    func testWalkingEveryStepReachesMenuBarPointer() {
        let expectedOrder: [OnboardingViewModel.OnboardingStep] = [
            .welcome, .discordConnect, .twitchConnect, .obsWidget,
            .preferences, .permissions, .notifications, .menuBarPointer,
        ]

        var visited: [OnboardingViewModel.OnboardingStep] = [viewModel.currentStep]
        while !viewModel.isLastStep {
            viewModel.goToNextStep()
            visited.append(viewModel.currentStep)
        }

        XCTAssertEqual(visited, expectedOrder, "must visit all 8 steps in order")
        XCTAssertEqual(viewModel.currentStep, .menuBarPointer)
        XCTAssertTrue(viewModel.isLastStep)
    }

    func testGoingForwardThenBackwardLandsOnWelcome() {
        while !viewModel.isLastStep { viewModel.goToNextStep() }
        while !viewModel.isFirstStep { viewModel.goToPreviousStep() }

        XCTAssertEqual(viewModel.currentStep, .welcome)
        XCTAssertTrue(viewModel.isFirstStep)
    }

    func testCompletingAfterFullWalkPersistsFlag() {
        XCTAssertFalse(OnboardingViewModel.hasCompletedOnboarding, "precondition: not completed")

        while !viewModel.isLastStep { viewModel.goToNextStep() }
        viewModel.completeOnboarding()

        XCTAssertTrue(viewModel.showCompletion, "completion screen must be shown")
        XCTAssertTrue(
            UserDefaults.standard.bool(forKey: AppConstants.UserDefaults.hasCompletedOnboarding),
            "completed flag must persist to UserDefaults"
        )
        XCTAssertTrue(OnboardingViewModel.hasCompletedOnboarding)
    }

    func testFreshViewModelReflectsPersistedCompletion() {
        while !viewModel.isLastStep { viewModel.goToNextStep() }
        viewModel.completeOnboarding()

        // A brand-new view model on the next launch should see the flag.
        let relaunched = OnboardingViewModel()
        XCTAssertEqual(relaunched.currentStep, .welcome, "fresh model still starts at welcome")
        XCTAssertTrue(OnboardingViewModel.hasCompletedOnboarding, "persisted flag survives re-init")
    }

    func testNextStepStopsAtLastStep() {
        while !viewModel.isLastStep { viewModel.goToNextStep() }
        let last = viewModel.currentStep
        viewModel.goToNextStep()  // no-op past the end
        XCTAssertEqual(viewModel.currentStep, last)
    }
}
