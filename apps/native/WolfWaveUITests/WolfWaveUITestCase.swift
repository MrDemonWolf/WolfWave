//
//  WolfWaveUITestCase.swift
//  WolfWave
//
//  Created by Nathanial Henniges on 2026-08-17.
//  Copyright © 2026 MrDemonWolf, Inc. All rights reserved.
//

import XCTest

/// Base class for every UI test: owns the launch contract with the app.
///
/// The launch environment is the whole isolation story. `WOLFWAVE_UI_TEST`
/// routes the app's `UserDefaults` and Keychain to throwaway storage and keeps
/// Music, Twitch, Discord, and Sparkle from starting, so a UI test can drive
/// real toggles without touching the developer's live dev-app settings, real
/// credentials, or the TCC Automation prompt. Read `UITestMode` for why each
/// flag exists.
///
/// Subclasses declare what they need through ``launchOptions`` and get a
/// launched `app` in `setUp`.
@MainActor
class WolfWaveUITestCase: XCTestCase {

    /// Starting state a subclass wants. Defaults to a true first run.
    struct LaunchOptions {
        /// Skip the wizard and land in the app proper.
        var onboarded = false
        /// Suppress the version-gated What's New window.
        var suppressWhatsNew = true
    }

    /// Overridden by subclasses that need a different starting state.
    var launchOptions: LaunchOptions { LaunchOptions() }

    /// How long to wait for a window or element that should already be coming.
    /// One constant so no test invents its own number.
    static let timeout: TimeInterval = 20

    /// Non-optional: `XCUIApplication` is a proxy, not the process, so building
    /// it costs nothing and it is valid before `launch()`. Declaring it `!`
    /// bought nothing and would trap on any access ordered before `setUp`.
    let app = XCUIApplication()

    // `async` rather than the sync overload on purpose: this class is
    // `@MainActor` (XCUITest drives the UI, and `XCUIApplication` is
    // MainActor-isolated), and a MainActor-isolated sync `setUp()` cannot
    // override XCTest's nonisolated one. The async overload can.
    override func setUp() async throws {
        try await super.setUp()
        // A UI test that keeps running after its first failed assertion just
        // produces a cascade of downstream noise around one real cause.
        continueAfterFailure = false

        var environment = [UITestEnvironment.enabled: "1"]
        if launchOptions.onboarded {
            environment[UITestEnvironment.onboarded] = "1"
        }
        if launchOptions.suppressWhatsNew {
            environment[UITestEnvironment.suppressWhatsNew] = "1"
        }
        app.launchEnvironment = environment
        app.launch()
        // A launched app is not necessarily the frontmost one, and an inactive
        // macOS app reports its whole window tree as disabled: every element is
        // still findable, but nothing is `isHittable`. Activating here is what
        // makes clicks in the tests mean what they look like they mean.
        app.activate()
    }

    override func tearDown() async throws {
        app.terminate()
        try await super.tearDown()
    }

    // MARK: - Helpers

    /// Fails with a readable message instead of returning false, so a timeout
    /// names the element it was waiting on.
    func expect(
        _ element: XCUIElement,
        _ description: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertTrue(
            element.waitForExistence(timeout: Self.timeout),
            "Timed out waiting for \(description)",
            file: file,
            line: line
        )
    }
}

/// The launch-environment keys, mirrored from `UITestMode` in the app target.
///
/// A UI test bundle cannot `@testable import` the app (the app is a separate
/// process, and this target links no app code), so these strings exist twice by
/// necessity. They are the contract; change one side, change the other.
enum UITestEnvironment {
    static let enabled = "WOLFWAVE_UI_TEST"
    static let onboarded = "WOLFWAVE_UI_TEST_ONBOARDED"
    static let suppressWhatsNew = "WOLFWAVE_UI_TEST_NO_WHATS_NEW"
}

/// Window identifiers, mirrored from the app for the same reason as the
/// environment keys above: a UI test target links no app code.
///
/// These are identifiers, never titles. A window title is user-facing copy, so
/// matching on it makes a wording change fail the suite for no real reason.
/// `settings` is the SwiftUI scene id (`WolfWaveApp.settingsWindowID`);
/// `onboarding` is set on the AppKit window from `AppConstants.WindowID`.
enum UITestWindow {
    static let settings = "wolfwave-settings"
    static let onboarding = "onboarding"
}
