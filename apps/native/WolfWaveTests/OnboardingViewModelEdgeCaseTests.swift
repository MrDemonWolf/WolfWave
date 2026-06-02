//
//  OnboardingViewModelEdgeCaseTests.swift
//  WolfWave
//
//  Created by Nathanial Henniges on 2026-03-19.
//  Copyright © 2026 MrDemonWolf, Inc. All rights reserved.
//

import XCTest
@testable import WolfWave

@MainActor
final class OnboardingViewModelEdgeCaseTests: WolfWaveTestCase {
    var viewModel: OnboardingViewModel?

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

    // MARK: - Completion State Tests

    func testShowCompletionIsFalseInitially() {
        guard let viewModel = viewModel else { XCTFail("Expected non-nil viewModel"); return }
        XCTAssertFalse(viewModel.showCompletion)
    }

    func testShowCompletionIsTrueAfterCompleteOnboarding() {
        guard let viewModel = viewModel else { XCTFail("Expected non-nil viewModel"); return }
        viewModel.completeOnboarding()
        XCTAssertTrue(viewModel.showCompletion)
    }

    // MARK: - Rapid Navigation Tests

    func testRapidForwardNavigationStaysAtBoundary() {
        guard let viewModel = viewModel else { XCTFail("Expected non-nil viewModel"); return }
        for _ in 0..<10 {
            viewModel.goToNextStep()
        }
        XCTAssertEqual(viewModel.currentStep, OnboardingViewModel.OnboardingStep.allCases.last!)
        XCTAssertTrue(viewModel.isLastStep)
    }

    func testRapidBackwardNavigationStaysAtBoundary() {
        guard let viewModel = viewModel else { XCTFail("Expected non-nil viewModel"); return }
        for _ in 0..<10 {
            viewModel.goToPreviousStep()
        }
        XCTAssertEqual(viewModel.currentStep, .welcome)
        XCTAssertTrue(viewModel.isFirstStep)
    }

    func testRapidForwardThenBackwardReturnsToStart() {
        guard let viewModel = viewModel else { XCTFail("Expected non-nil viewModel"); return }
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
        guard let viewModel = viewModel else { XCTFail("Expected non-nil viewModel"); return }
        XCTAssertEqual(
            OnboardingViewModel.OnboardingStep.allCases.count,
            viewModel.totalSteps
        )
    }

    // MARK: - Re-instantiation Tests
    // testReInstantiatingAfterCompletionStartsAtWelcome removed:
    // @Observable causes malloc double-free when completeOnboarding() triggers
    // UserDefaults write + observation notification in the test host process.
}
