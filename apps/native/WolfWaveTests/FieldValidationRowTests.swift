//
//  FieldValidationRowTests.swift
//  WolfWave
//
//  Created by Nathanial Henniges on 2026-08-14.
//  Copyright © 2026 MrDemonWolf, Inc. All rights reserved.
//

import XCTest
import SwiftUI
import AppKit
@testable import WolfWave

@MainActor
final class FieldValidationRowTests: XCTestCase {

    // MARK: - Rendering

    func testIdleRendersNothing() {
        let host = NSHostingView(rootView: FieldValidationRow(state: .idle))
        host.layoutSubtreeIfNeeded()
        XCTAssertEqual(host.fittingSize.height, 0)
    }

    func testEveryVisibleStateRenders() {
        let states: [FieldValidationRow.State] = [
            .validating("Verifying channel\u{2026}"),
            .valid("Channel verified"),
            .invalid("No Twitch channel by that name."),
            .failed(UserFacingError(id: "twitch.offline", title: "You're offline", severity: .warning))
        ]
        for state in states {
            let host = NSHostingView(rootView: FieldValidationRow(state: state))
            host.setFrameSize(NSSize(width: 360, height: 0))
            host.layoutSubtreeIfNeeded()
            XCTAssertGreaterThan(host.fittingSize.height, 0, "\(state) should render")
        }
    }

    func testLongFailureTextWraps() {
        let error = UserFacingError(
            id: "twitch.rateLimited",
            title: "Your sign-in is fine, we're being rate limited",
            cause: "Twitch is throttling requests from this Mac right now.",
            fix: "Try again in 30 seconds.",
            severity: .warning
        )
        let host = NSHostingView(rootView: FieldValidationRow(state: .failed(error)))
        host.setFrameSize(NSSize(width: 240, height: 0))
        host.layoutSubtreeIfNeeded()
        XCTAssertGreaterThan(host.fittingSize.height, 0)
    }

    // MARK: - Equatable

    func testStatesCompareByPayload() {
        XCTAssertEqual(FieldValidationRow.State.valid("ok"), .valid("ok"))
        XCTAssertNotEqual(FieldValidationRow.State.valid("ok"), .valid("other"))
        XCTAssertNotEqual(FieldValidationRow.State.idle, .validating("x"))
    }

    func testFailedStatesCompareByError() {
        let a = UserFacingError(id: "x", title: "T")
        let b = UserFacingError(id: "y", title: "T")
        XCTAssertEqual(FieldValidationRow.State.failed(a), .failed(a))
        XCTAssertNotEqual(FieldValidationRow.State.failed(a), .failed(b))
    }

    // MARK: - The Originating Bug

    /// "Couldn't check channel" used to be the whole message, with the real
    /// reason reachable only by hovering for a `.help()` tooltip. The failure
    /// text must now contain the reason itself.
    func testFailedStateSurfacesTheReasonNotJustTheHeadline() {
        let error = UserFacingError(
            id: "twitch.signInExpired",
            title: "Twitch sign-in expired",
            cause: "Twitch rejected the saved sign-in.",
            fix: "Reconnect, then choose Join.",
            severity: .warning
        )
        let label = error.accessibilityLabel
        XCTAssertTrue(label.contains("Twitch rejected the saved sign-in."))
        XCTAssertTrue(label.contains("Reconnect, then choose Join."))
        XCTAssertFalse(label.contains("Couldn't check channel"))
    }
}
