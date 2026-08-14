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
