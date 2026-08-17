//
//  UITestMode.swift
//  WolfWave
//
//  Created by Nathanial Henniges on 2026-08-17.
//  Copyright © 2026 MrDemonWolf, Inc. All rights reserved.
//

import Foundation

/// Whether this launch is being driven by the `WolfWaveUITests` XCUITest bundle.
///
/// Sibling of ``WolfWaveApp/isRunningTests``, and necessary because that flag
/// cannot see a UI test. In a UI test the app runs in its *own* process:
/// `XCTest.framework` is never loaded into it and none of the `XCTest*`
/// environment variables are set, so every isolation seam keyed on
/// `isRunningTests` (``DefaultsStore/store``, ``KeychainService/backend``)
/// would resolve to the live ones. A UI test toggling a setting would then edit
/// the developer's real `com.mrdemonwolf.wolfwave.dev` domain, which is the
/// exact corruption `DefaultsStore` was introduced to prevent.
///
/// The signal is an environment variable rather than a launch argument on
/// purpose: `UserDefaults` parses `-flag value` launch arguments into the
/// argument domain, so a bare `-flag` is a defaults key with confusing
/// semantics. `launchEnvironment` touches nothing.
nonisolated enum UITestMode {

    /// Set on `XCUIApplication.launchEnvironment` by the UI test bundle.
    static let environmentKey = "WOLFWAVE_UI_TEST"

    /// True when the app was launched by the UI test bundle.
    static let isActive = ProcessInfo.processInfo.environment[environmentKey] == "1"

    /// True when *any* test harness owns this process: the hosted unit bundle
    /// (in-process) or a UI test (out-of-process). Storage seams branch on this,
    /// never on `isRunningTests` alone.
    static var isUnderTestHarness: Bool { WolfWaveApp.isRunningTests || isActive }

    /// Set to `"1"` by a UI test that wants to land straight in the app rather
    /// than in the wizard. Every launch starts from a wiped suite, so without it
    /// each test would have to walk onboarding before reaching its subject.
    static let skipOnboardingKey = "WOLFWAVE_UI_TEST_ONBOARDED"

    /// Set to `"1"` to suppress the What's New window. A version-gated window
    /// appearing over the app mid-test is a focus race, not a finding.
    static let suppressWhatsNewKey = "WOLFWAVE_UI_TEST_NO_WHATS_NEW"

    /// True when the UI test asked to start past onboarding.
    static var startsOnboarded: Bool {
        isActive && ProcessInfo.processInfo.environment[skipOnboardingKey] == "1"
    }

    /// True when the UI test asked to suppress What's New.
    static var suppressesWhatsNew: Bool {
        isActive && ProcessInfo.processInfo.environment[suppressWhatsNewKey] == "1"
    }

    /// Writes the requested starting state into the (already wiped) isolated
    /// suite. Must run before anything reads onboarding state. No-op outside a
    /// UI test, so a normal launch never reaches the write.
    static func seedRequestedState() {
        guard startsOnboarded else { return }
        DefaultsStore.store.set(true, forKey: AppConstants.UserDefaults.hasCompletedOnboarding)
    }
}
