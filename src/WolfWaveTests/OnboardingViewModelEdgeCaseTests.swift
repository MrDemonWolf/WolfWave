//
//  OnboardingViewModelEdgeCaseTests.swift
//  WolfWaveTests
//
//  Created by MrDemonWolf, Inc. on 3/19/26.
//

import XCTest
@testable import WolfWave

@MainActor
final class OnboardingViewModelEdgeCaseTests: XCTestCase {
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

    // MARK: - Completion State Tests

    func testShowCompletionIsFalseInitially() {
        XCTAssertFalse(viewModel.showCompletion)
    }

    func testShowCompletionIsTrueAfterCompleteOnboarding() {
        viewModel.completeOnboarding()
        XCTAssertTrue(viewModel.showCompletion)
    }

    // MARK: - Rapid Navigation Tests

    func testRapidForwardNavigationStaysAtBoundary() {
        for _ in 0..<10 {
            viewModel.goToNextStep()
        }
        XCTAssertEqual(viewModel.currentStep, .obsWidget)
        XCTAssertTrue(viewModel.isLastStep)
    }

    func testRapidBackwardNavigationStaysAtBoundary() {
        for _ in 0..<10 {
            viewModel.goToPreviousStep()
        }
        XCTAssertEqual(viewModel.currentStep, .welcome)
        XCTAssertTrue(viewModel.isFirstStep)
    }

    func testRapidForwardThenBackwardReturnsToStart() {
        for _ in 0..<10 {
            viewModel.goToNextStep()
        }
        for _ in 0..<10 {
            viewModel.goToPreviousStep()
        }
        XCTAssertEqual(viewModel.currentStep, .welcome)
    }

    // MARK: - Step Enum Tests

    func testStepRawValuesAreContiguous() {
        let allCases = OnboardingViewModel.OnboardingStep.allCases
        for (index, step) in allCases.enumerated() {
            XCTAssertEqual(step.rawValue, index, "Step \(step) should have rawValue \(index)")
        }
    }

    func testAllCasesCountEqualsTotalSteps() {
        XCTAssertEqual(
            OnboardingViewModel.OnboardingStep.allCases.count,
            viewModel.totalSteps
        )
    }

    // MARK: - Re-instantiation Tests

    func testReInstantiatingAfterCompletionStartsAtWelcome() {
        viewModel.completeOnboarding()
        XCTAssertTrue(viewModel.showCompletion)

        // Create a new instance
        let newViewModel = OnboardingViewModel()
        XCTAssertEqual(newViewModel.currentStep, .welcome)
        XCTAssertFalse(newViewModel.showCompletion)
    }
}
