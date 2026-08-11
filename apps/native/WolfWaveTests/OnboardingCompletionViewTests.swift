//
//  OnboardingCompletionViewTests.swift
//  WolfWave
//
//  Created by Nathanial Henniges on 2026-05-26.
//  Copyright © 2026 MrDemonWolf, Inc. All rights reserved.
//

import XCTest
import SwiftUI
@testable import WolfWave

@MainActor
final class OnboardingCompletionViewTests: XCTestCase {

    // MARK: - Dismiss Contract

    /// The view auto-dismisses after the animation window. Window is ~1.8s
    /// under normal motion (280ms hero + 1500ms text hold) and ~1.2s under
    /// Reduce Motion. Test the contract with a generous timeout.
    func testOnDismissFiresAfterAnimationWindow() async {
        let expectation = expectation(description: "onDismiss invoked")
        expectation.assertForOverFulfill = false

        let view = OnboardingCompletionView {
            expectation.fulfill()
        }

        // Render off-screen to trigger `.task`.
        let host = NSHostingView(rootView: view)
        host.frame = NSRect(x: 0, y: 0, width: 600, height: 400)
        // Force a layout pass so the task modifier fires.
        host.layoutSubtreeIfNeeded()

        await fulfillment(of: [expectation], timeout: 3.0)
    }

}
