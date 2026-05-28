//
//  OnboardingViewModelTests.swift
//  WolfWave
//
//  Created by Nathanial Henniges on 2026-02-13.
//  Copyright © 2026 MrDemonWolf, Inc. All rights reserved.
//

import XCTest
@testable import WolfWave

@MainActor
final class OnboardingViewModelTests: WolfWaveTestCase {
    var viewModel: OnboardingViewModel!

    override func setUp() {
        super.setUp()
        viewModel = OnboardingViewModel()
        UserDefaults.standard.removeObject(forKey: AppConstants.UserDefaults.hasCompletedOnboarding)
    }

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: AppConstants.UserDefaults.hasCompletedOnboarding)
        viewModel = nil
        super.tearDown()
    }

    // MARK: - Initial State

    func testInitialStepIsWelcome() {
        XCTAssertEqual(viewModel.currentStep, .welcome)
    }

    func testTotalStepsEquals7() {
        XCTAssertEqual(viewModel.totalSteps, 7)
    }

    func testIsFirstStepAtWelcome() {
        XCTAssertTrue(viewModel.isFirstStep)
    }

    func testIsNotLastStepAtWelcome() {
        XCTAssertFalse(viewModel.isLastStep)
    }

    // MARK: - Forward Navigation

    func testGoToNextStepFromWelcomeReachesDiscord() {
        viewModel.goToNextStep()
        XCTAssertEqual(viewModel.currentStep, .discordConnect)
    }

    func testTwoNextStepsReachesTwitch() {
        viewModel.goToNextStep()
        viewModel.goToNextStep()
        XCTAssertEqual(viewModel.currentStep, .twitchConnect)
    }

    func testThreeNextStepsReachesOBS() {
        viewModel.goToNextStep()
        viewModel.goToNextStep()
        viewModel.goToNextStep()
        XCTAssertEqual(viewModel.currentStep, .obsWidget)
    }

    func testFourNextStepsReachesPreferences() {
        for _ in 0..<4 { viewModel.goToNextStep() }
        XCTAssertEqual(viewModel.currentStep, .preferences)
    }

    func testFiveNextStepsReachesAppleMusic() {
        for _ in 0..<5 { viewModel.goToNextStep() }
        XCTAssertEqual(viewModel.currentStep, .appleMusicAccess)
    }

    func testSixNextStepsReachesMenuBarPointer() {
        for _ in 0..<6 { viewModel.goToNextStep() }
        XCTAssertEqual(viewModel.currentStep, .menuBarPointer)
    }

    func testGoToNextStepAtLastStepStays() {
        for _ in 0..<10 { viewModel.goToNextStep() }
        XCTAssertEqual(viewModel.currentStep, .menuBarPointer)
    }

    // MARK: - Backward Navigation

    func testGoToPreviousStepAtFirstStepStays() {
        viewModel.goToPreviousStep()
        XCTAssertEqual(viewModel.currentStep, .welcome)
    }

    func testGoToPreviousStepFromDiscord() {
        viewModel.goToNextStep()
        viewModel.goToPreviousStep()
        XCTAssertEqual(viewModel.currentStep, .welcome)
    }

    func testGoToPreviousStepFromTwitch() {
        viewModel.goToNextStep()
        viewModel.goToNextStep()
        viewModel.goToPreviousStep()
        XCTAssertEqual(viewModel.currentStep, .discordConnect)
    }

    // MARK: - Step Properties

    func testIsNotFirstStepAtDiscord() {
        viewModel.goToNextStep()
        XCTAssertFalse(viewModel.isFirstStep)
    }

    func testIsNotLastStepInMiddle() {
        for _ in 0..<3 { viewModel.goToNextStep() }
        XCTAssertFalse(viewModel.isLastStep)
    }

    func testIsLastStepAtMenuBarPointer() {
        for _ in 0..<6 { viewModel.goToNextStep() }
        XCTAssertTrue(viewModel.isLastStep)
    }

    // MARK: - Completion

    func testCompleteOnboardingSetsFlag() {
        viewModel.completeOnboarding()
        XCTAssertTrue(UserDefaults.standard.bool(forKey: AppConstants.UserDefaults.hasCompletedOnboarding))
    }

    func testHasCompletedOnboardingReadsTrue() {
        UserDefaults.standard.set(true, forKey: AppConstants.UserDefaults.hasCompletedOnboarding)
        XCTAssertTrue(OnboardingViewModel.hasCompletedOnboarding)
    }

    func testHasCompletedOnboardingReadsFalse() {
        UserDefaults.standard.set(false, forKey: AppConstants.UserDefaults.hasCompletedOnboarding)
        XCTAssertFalse(OnboardingViewModel.hasCompletedOnboarding)
    }

    func testHasCompletedOnboardingDefaultsFalse() {
        UserDefaults.standard.removeObject(forKey: AppConstants.UserDefaults.hasCompletedOnboarding)
        XCTAssertFalse(OnboardingViewModel.hasCompletedOnboarding)
    }

    // MARK: - Full Navigation Cycle

    func testFullNavigationCycleForwardAndBack() {
        XCTAssertEqual(viewModel.currentStep, .welcome)

        let order: [OnboardingViewModel.OnboardingStep] = [
            .discordConnect, .twitchConnect, .obsWidget, .preferences, .appleMusicAccess, .menuBarPointer
        ]

        for expected in order {
            viewModel.goToNextStep()
            XCTAssertEqual(viewModel.currentStep, expected)
        }

        for expected in order.dropLast().reversed() + [.welcome] {
            viewModel.goToPreviousStep()
            XCTAssertEqual(viewModel.currentStep, expected)
        }
    }
}
