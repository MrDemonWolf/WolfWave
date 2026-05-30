//
//  StreamerModeMaskingSweepTests.swift
//  WolfWaveTests
//
//  Copyright © 2026 MrDemonWolf, Inc. All rights reserved.
//

import XCTest

@testable import WolfWave

/// Locks the masking contract that the settings/onboarding views rely on when
/// Streamer Mode is enabled. `StreamerModeTests` covers `mask(_:style:isOn:)`
/// in isolation; this suite asserts that realistic sensitive values (the actual
/// shapes shown on screen — Twitch account name, channel, WebSocket auth token,
/// LAN/overlay URLs) never leak through the masked output, so a regression in a
/// view that forwards the wrong value or style is caught.
final class StreamerModeMaskingSweepTests: XCTestCase {

    // MARK: - No leakage when on

    func testTwitchAccountNameFullyRedactedWhenOn() {
        let username = "mrdemonwolf"
        let masked = StreamerMode.mask(username, style: .channel, isOn: true)
        XCTAssertNotEqual(masked, username)
        XCTAssertFalse(masked.localizedCaseInsensitiveContains("mrdemonwolf"))
        XCTAssertFalse(masked.localizedCaseInsensitiveContains("wolf"))
    }

    func testWebSocketAuthTokenFullyRedactedWhenOn() {
        let token = "a1b2c3d4e5f6a7b8c9d0"
        let masked = StreamerMode.mask(token, style: .token, isOn: true)
        XCTAssertNotEqual(masked, token)
        XCTAssertFalse(masked.contains("a1b2c3"))
    }

    func testLANAndOverlayURLsFullyRedactedWhenOn() {
        for url in ["http://192.168.1.42:8766/", "ws://192.168.1.42:8765/?token=abc123"] {
            let masked = StreamerMode.mask(url, style: .url, isOn: true)
            XCTAssertNotEqual(masked, url)
            XCTAssertFalse(masked.contains("192.168"), "LAN IP must not leak: \(masked)")
            XCTAssertFalse(masked.contains("token=abc123"), "token query must not leak: \(masked)")
        }
    }

    // MARK: - Passthrough when off

    func testSensitiveValuesPassThroughWhenOff() {
        let samples: [(String, StreamerMode.Style)] = [
            ("mrdemonwolf", .channel),
            ("a1b2c3d4e5f6", .token),
            ("http://192.168.1.42:8766/", .url),
        ]
        for (value, style) in samples {
            XCTAssertEqual(StreamerMode.mask(value, style: style, isOn: false), value)
        }
    }

    // MARK: - Empty state preserved

    func testEmptyValueIsNeverMasked() {
        for style in [StreamerMode.Style.channel, .token, .url, .generic] {
            XCTAssertEqual(StreamerMode.mask("", style: style, isOn: true), "")
        }
    }
}

// MARK: - Onboarding step a11y

/// Verifies the onboarding progress indicator has a spoken title for every
/// step, backing the `accessibilityValue` ("Step N of 7: <title>") added to
/// the wizard's progress dots.
final class OnboardingStepAccessibilityTests: XCTestCase {

    func testEveryStepHasNonEmptyAccessibilityTitle() {
        for step in OnboardingViewModel.OnboardingStep.allCases {
            XCTAssertFalse(
                step.accessibilityTitle.trimmingCharacters(in: .whitespaces).isEmpty,
                "Step \(step) must have a spoken title")
        }
    }

    func testAccessibilityTitlesAreDistinct() {
        let titles = OnboardingViewModel.OnboardingStep.allCases.map(\.accessibilityTitle)
        XCTAssertEqual(Set(titles).count, titles.count, "Step titles must be unique")
    }

    func testTitlesMatchDocumentedStepOrder() {
        XCTAssertEqual(
            OnboardingViewModel.OnboardingStep.allCases.map(\.accessibilityTitle),
            ["Welcome", "Discord", "Twitch", "OBS Widget", "Preferences", "Permissions", "Menu Bar"]
        )
    }
}
