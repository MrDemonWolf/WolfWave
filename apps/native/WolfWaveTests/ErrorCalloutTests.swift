//
//  ErrorCalloutTests.swift
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
final class ErrorCalloutTests: XCTestCase {

    // MARK: - Fixtures

    private func makeError(
        id: String = "twitch.signInExpired",
        severity: UserFacingError.Severity = .warning,
        actions: [ErrorAction] = [.reconnectTwitch]
    ) -> UserFacingError {
        UserFacingError(
            id: id,
            title: "Twitch sign-in expired",
            cause: "Chat commands stopped working.",
            fix: "Reconnect and WolfWave picks up where it left off.",
            severity: severity,
            actions: actions
        )
    }

    // MARK: - Rendering

    func testRendersBannerWithActions() {
        let host = NSHostingView(rootView: ErrorCallout(error: makeError()))
        host.setFrameSize(NSSize(width: 480, height: 0))
        host.layoutSubtreeIfNeeded()
        XCTAssertGreaterThan(host.fittingSize.height, 0)
        XCTAssertGreaterThan(host.fittingSize.width, 0)
    }

    /// The action row is a sibling of the banner, so adding actions has to make
    /// the whole callout taller. If it did not, the buttons would be rendering
    /// inside the banner, which the catalog forbids.
    func testActionsAddHeightBelowTheBanner() {
        let without = NSHostingView(rootView: ErrorCallout(error: makeError(actions: [])))
        let with = NSHostingView(rootView: ErrorCallout(error: makeError(actions: [.reconnectTwitch])))
        for host in [without, with] {
            host.setFrameSize(NSSize(width: 480, height: 0))
            host.layoutSubtreeIfNeeded()
        }
        XCTAssertGreaterThan(with.fittingSize.height, without.fittingSize.height)
    }

    func testRendersEverySeverity() {
        for severity in UserFacingError.Severity.allCases {
            let host = NSHostingView(rootView: ErrorCallout(error: makeError(severity: severity)))
            host.setFrameSize(NSSize(width: 480, height: 0))
            host.layoutSubtreeIfNeeded()
            XCTAssertGreaterThan(host.fittingSize.height, 0, "\(severity) should render")
        }
    }

    func testRendersWithoutActions() {
        let host = NSHostingView(rootView: ErrorCallout(error: makeError(actions: [])))
        host.setFrameSize(NSSize(width: 480, height: 0))
        host.layoutSubtreeIfNeeded()
        XCTAssertGreaterThan(host.fittingSize.height, 0)
    }

    func testRendersMultipleActions() {
        let error = makeError(actions: [.retry, .reportBug, .openDocs(anchor: "twitch")])
        let host = NSHostingView(rootView: ErrorCallout(error: error))
        host.setFrameSize(NSSize(width: 560, height: 0))
        host.layoutSubtreeIfNeeded()
        XCTAssertGreaterThan(host.fittingSize.height, 0)
    }

    // MARK: - Action Dispatch

    func testInvokesHandlerWithTheChosenIntent() {
        var received: [ErrorAction] = []
        let callout = ErrorCallout(error: makeError(actions: [.retry, .reportBug])) { received.append($0) }

        // The component never performs the fix itself; it hands back intent.
        callout.onAction(.retry)
        callout.onAction(.reportBug)

        XCTAssertEqual(received, [.retry, .reportBug])
    }

    func testDefaultHandlerIsHarmless() {
        let callout = ErrorCallout(error: makeError())
        callout.onAction(.reconnectTwitch)
    }

    // MARK: - Retry Countdown

    /// A live rate limit renders the countdown and stays disabled.
    func testPendingWaitKeepsTheCountdownLabel() {
        let resolved = ErrorCallout.resolvedPrimary(.retryAfter(seconds: 30), remainingWait: 30)
        XCTAssertEqual(resolved, .retryAfter(seconds: 30))
        XCTAssertTrue(resolved?.isWaiting == true)
        XCTAssertEqual(resolved?.label, "Try Again in 30s")
    }

    func testCountdownTicksDownWithRemainingWait() {
        let resolved = ErrorCallout.resolvedPrimary(.retryAfter(seconds: 30), remainingWait: 7)
        XCTAssertEqual(resolved, .retryAfter(seconds: 7))
        XCTAssertEqual(resolved?.label, "Try Again in 7s")
    }

    /// The whole point of the countdown: when it expires the button becomes a
    /// plain, enabled retry. Before this, `isWaiting` was true for every
    /// `retryAfter`, so the button was disabled forever.
    func testExpiredWaitBecomesAnEnabledRetry() {
        let resolved = ErrorCallout.resolvedPrimary(.retryAfter(seconds: 30), remainingWait: 0)
        XCTAssertEqual(resolved, .retry)
        XCTAssertFalse(resolved?.isWaiting == true)
        XCTAssertEqual(resolved?.label, "Try Again")
    }

    /// A `Retry-After: 0` from Twitch is usable on arrival, before any tick.
    func testZeroDelayIsUsableWithoutWaitingForATick() {
        let resolved = ErrorCallout.resolvedPrimary(.retryAfter(seconds: 0), remainingWait: nil)
        XCTAssertEqual(resolved, .retry)
        XCTAssertFalse(resolved?.isWaiting == true)
    }

    func testNonWaitingActionsPassThroughUntouched() {
        XCTAssertEqual(
            ErrorCallout.resolvedPrimary(.reconnectTwitch, remainingWait: 12),
            .reconnectTwitch
        )
        XCTAssertNil(ErrorCallout.resolvedPrimary(nil, remainingWait: nil))
    }

    // MARK: - Expiry Instant

    /// The countdown is derived from a fixed instant, not counted down tick by
    /// tick, so a busy main actor cannot make it drift and a view that
    /// disappears and returns cannot restart it at the full delay.
    func testRemainingSecondsDerivesFromTheDeadline() {
        let start = ContinuousClock.now
        XCTAssertEqual(
            ErrorCallout.remainingSeconds(now: start, deadline: start.advanced(by: .seconds(30))),
            30
        )
        XCTAssertEqual(
            ErrorCallout.remainingSeconds(
                now: start.advanced(by: .seconds(25)),
                deadline: start.advanced(by: .seconds(30))
            ),
            5
        )
    }

    /// A partially elapsed second still reads as one, so the label never shows
    /// "0s" while the action is genuinely still disabled.
    func testPartialSecondRoundsUp() {
        let start = ContinuousClock.now
        XCTAssertEqual(
            ErrorCallout.remainingSeconds(
                now: start.advanced(by: .milliseconds(500)),
                deadline: start.advanced(by: .seconds(3))
            ),
            3
        )
    }

    func testPassedDeadlineClampsToZero() {
        let start = ContinuousClock.now
        XCTAssertEqual(
            ErrorCallout.remainingSeconds(now: start, deadline: start),
            0
        )
        XCTAssertEqual(
            ErrorCallout.remainingSeconds(
                now: start.advanced(by: .seconds(90)),
                deadline: start.advanced(by: .seconds(30))
            ),
            0,
            "An overshot deadline must not go negative"
        )
    }

    /// End to end through the resolver: a deadline in the past yields an
    /// enabled retry.
    func testExpiredDeadlineResolvesToEnabledRetry() {
        let start = ContinuousClock.now
        let left = ErrorCallout.remainingSeconds(
            now: start.advanced(by: .seconds(31)),
            deadline: start.advanced(by: .seconds(30))
        )
        let resolved = ErrorCallout.resolvedPrimary(.retryAfter(seconds: 30), remainingWait: left)
        XCTAssertEqual(resolved, .retry)
        XCTAssertFalse(resolved?.isWaiting == true)
    }

    func testRateLimitedCalloutRenders() {
        let error = UserFacingError(
            id: "twitch.rateLimited",
            title: "Your sign-in is fine, we're being rate limited",
            fix: "Try again shortly.",
            severity: .warning,
            actions: [.retryAfter(seconds: 30)]
        )
        let host = NSHostingView(rootView: ErrorCallout(error: error))
        host.setFrameSize(NSSize(width: 480, height: 0))
        host.layoutSubtreeIfNeeded()
        XCTAssertGreaterThan(host.fittingSize.height, 0)
    }

    // MARK: - Severity Mapping

    /// The model stays free of SwiftUI, so this mapping is the only place the
    /// two vocabularies meet. Drift here is invisible at the call site.
    func testSeverityMapsToBannerStyleTints() {
        let cases: [(UserFacingError.Severity, Color)] = [
            (.error, DSColor.error),
            (.warning, DSColor.warning),
            (.info, DSColor.info)
        ]
        for (severity, expected) in cases {
            let banner: CalloutBanner.Style
            switch severity {
            case .error: banner = .error
            case .warning: banner = .warning
            case .info: banner = .info
            }
            XCTAssertEqual(banner.tint, expected, "\(severity) should tint with its semantic token")
        }
    }
}
