//
//  OnboardingUITests.swift
//  WolfWave
//
//  Created by Nathanial Henniges on 2026-08-17.
//  Copyright © 2026 MrDemonWolf, Inc. All rights reserved.
//

import XCTest

/// Drives the first-launch wizard end to end through its real windows.
///
/// The unit suite already covers `OnboardingViewModel`'s step order and its
/// persistence. What it cannot see is whether the wizard is reachable at all:
/// the window opening, the buttons being hit-testable, and the flag actually
/// closing the loop so the next launch skips it. That whole path is what breaks
/// in practice, and only a real launch exercises it.
final class OnboardingUITests: WolfWaveUITestCase {

    /// Identifiers declared by the wizard's navigation bar. Behaviour, not
    /// decoration: renaming one here without renaming it in the app is a test
    /// that silently stops testing.
    private enum ID {
        static let next = "onboarding.next"
        static let finish = "onboarding.finish"
        static let back = "onboarding.back"
        static let skipAll = "onboarding.skipAll"
    }

    /// Upper bound on wizard steps. Guards the walk loop against an infinite
    /// spin if `finish` never appears; the failure then names the real problem
    /// rather than hanging the run until the scheme timeout.
    private static let maxSteps = 20

    func testFirstLaunchOpensTheWizard() {
        let window = app.windows["Welcome to WolfWave"]
        expect(window, "the onboarding window on a first launch")
        expect(app.buttons[ID.next], "the wizard's Next button")
    }

    func testWalkingEveryStepFinishesOnboarding() {
        expect(app.buttons[ID.next], "the wizard's Next button")

        var steps = 0
        while !app.buttons[ID.finish].exists {
            XCTAssertLessThan(
                steps, Self.maxSteps,
                "Walked \(Self.maxSteps) steps without reaching the last one. "
                    + "Either a step stopped advancing or `onboarding.finish` is gone."
            )
            let next = app.buttons[ID.next]
            XCTAssertTrue(next.isHittable, "Next was not hittable on step \(steps + 1)")
            next.click()
            steps += 1
        }

        // The wizard has more than a couple of steps; reaching `finish`
        // immediately would mean the walk never actually advanced.
        XCTAssertGreaterThan(steps, 1, "Reached the last step without advancing through the wizard")

        app.buttons[ID.finish].click()
        XCTAssertTrue(
            app.windows["Welcome to WolfWave"].waitForNonExistence(timeout: Self.timeout),
            "The onboarding window stayed open after Finish"
        )
    }

    func testBackReturnsToThePreviousStep() {
        expect(app.buttons[ID.next], "the wizard's Next button")

        // The wizard keeps Back mounted on step one for layout stability but
        // marks it `accessibilityHidden`, so it is genuinely absent from the
        // tree until step two. Its appearing and disappearing IS the signal
        // that the step changed.
        XCTAssertFalse(app.buttons[ID.back].exists, "Back was exposed on the first step")
        app.buttons[ID.next].click()

        let back = app.buttons[ID.back]
        XCTAssertTrue(back.waitForExistence(timeout: Self.timeout), "Back never appeared on step two")
        back.click()
        XCTAssertTrue(
            app.buttons[ID.back].waitForNonExistence(timeout: Self.timeout),
            "Back stayed exposed after returning to the first step"
        )
    }

    func testSkipAllClosesTheWizard() {
        let skipAll = app.buttons[ID.skipAll]
        expect(skipAll, "the wizard's Skip All button")
        skipAll.click()
        XCTAssertTrue(
            app.windows["Welcome to WolfWave"].waitForNonExistence(timeout: Self.timeout),
            "The onboarding window stayed open after Skip All"
        )
    }
}

