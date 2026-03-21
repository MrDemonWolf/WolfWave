//
//  OnboardingViewModelTests.swift
//  WolfWaveTests
//
//  Created by MrDemonWolf, Inc. on 2/13/26.
//

import XCTest
@testable import WolfWave

@MainActor
final class OnboardingViewModelTests: XCTestCase {
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

    func testTotalStepsEquals4() {
        XCTAssertEqual(viewModel.totalSteps, 4)
    }

    func testIsFirstStepAtWelcome() {
        XCTAssertTrue(viewModel.isFirstStep)
    }

    func testIsNotLastStepAtWelcome() {
        XCTAssertFalse(viewModel.isLastStep)
    }

    // MARK: - Forward Navigation

    func testGoToNextStepFromWelcome() {
        viewModel.goToNextStep()
        XCTAssertEqual(viewModel.currentStep, .twitchConnect)
    }

    func testGoToNextStepTwiceReachesDiscord() {
        viewModel.goToNextStep()
        viewModel.goToNextStep()
        XCTAssertEqual(viewModel.currentStep, .discordConnect)
    }

    func testGoToNextStepThreeTimesReachesOBSWidget() {
        viewModel.goToNextStep()
        viewModel.goToNextStep()
        viewModel.goToNextStep()
        XCTAssertEqual(viewModel.currentStep, .obsWidget)
    }

    func testGoToNextStepAtLastStepStays() {
        viewModel.goToNextStep()
        viewModel.goToNextStep()
        viewModel.goToNextStep()
        viewModel.goToNextStep()
        XCTAssertEqual(viewModel.currentStep, .obsWidget)
    }

    // MARK: - Backward Navigation

    func testGoToPreviousStepAtFirstStepStays() {
        viewModel.goToPreviousStep()
        XCTAssertEqual(viewModel.currentStep, .welcome)
    }

    func testGoToPreviousStepFromTwitchConnect() {
        viewModel.goToNextStep()
        viewModel.goToPreviousStep()
        XCTAssertEqual(viewModel.currentStep, .welcome)
    }

    func testGoToPreviousStepFromDiscordConnect() {
        viewModel.goToNextStep()
        viewModel.goToNextStep()
        viewModel.goToPreviousStep()
        XCTAssertEqual(viewModel.currentStep, .twitchConnect)
    }

    // MARK: - Step Properties

    func testIsNotFirstStepAtTwitchConnect() {
        viewModel.goToNextStep()
        XCTAssertFalse(viewModel.isFirstStep)
    }

    func testIsNotLastStepAtDiscordConnect() {
        viewModel.goToNextStep()
        viewModel.goToNextStep()
        XCTAssertFalse(viewModel.isLastStep)
    }

    func testIsLastStepAtOBSWidget() {
        viewModel.goToNextStep()
        viewModel.goToNextStep()
        viewModel.goToNextStep()
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

        viewModel.goToNextStep()
        XCTAssertEqual(viewModel.currentStep, .twitchConnect)

        viewModel.goToNextStep()
        XCTAssertEqual(viewModel.currentStep, .discordConnect)

        viewModel.goToNextStep()
        XCTAssertEqual(viewModel.currentStep, .obsWidget)

        viewModel.goToPreviousStep()
        XCTAssertEqual(viewModel.currentStep, .discordConnect)

        viewModel.goToPreviousStep()
        XCTAssertEqual(viewModel.currentStep, .twitchConnect)

        viewModel.goToPreviousStep()
        XCTAssertEqual(viewModel.currentStep, .welcome)
    }
}
