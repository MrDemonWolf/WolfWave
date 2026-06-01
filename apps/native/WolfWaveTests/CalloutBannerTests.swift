//
//  CalloutBannerTests.swift
//  WolfWave
//
//  Created by Nathanial Henniges on 2026-05-26.
//  Copyright © 2026 MrDemonWolf, Inc. All rights reserved.
//

import XCTest
import SwiftUI
import AppKit
@testable import WolfWave

@MainActor
final class CalloutBannerTests: XCTestCase {

    // MARK: - Rendering

    func testRendersWithDefaultStyle() {
        let view = CalloutBanner("Heads up.")
        let host = NSHostingView(rootView: view)
        host.layoutSubtreeIfNeeded()
        XCTAssertGreaterThan(host.fittingSize.height, 0)
        XCTAssertGreaterThan(host.fittingSize.width, 0)
    }

    func testRendersErrorStyleWithStroke() {
        let view = CalloutBanner("Cannot undo.", style: .error, strokeVisible: true)
        let host = NSHostingView(rootView: view)
        host.layoutSubtreeIfNeeded()
        XCTAssertGreaterThan(host.fittingSize.height, 0)
    }

    func testRendersWithTitleAndMarkdown() {
        let view = CalloutBanner("Viewers type **!sr song name**.", title: "How it works", style: .info)
        let host = NSHostingView(rootView: view)
        host.setFrameSize(NSSize(width: 360, height: 0))
        host.layoutSubtreeIfNeeded()
        XCTAssertGreaterThan(host.fittingSize.height, 0)
    }

    func testRendersMultilineText() {
        let long = String(repeating: "WolfWave needs Apple Music access. ", count: 5)
        let view = CalloutBanner(long, style: .warning)
        let host = NSHostingView(rootView: view)
        host.setFrameSize(NSSize(width: 320, height: 0))
        host.layoutSubtreeIfNeeded()
        XCTAssertGreaterThan(host.fittingSize.height, 0)
    }

    /// A titled banner adds a lead line, so it must be at least as tall as the
    /// same body without a title.
    func testTitledBannerIsTallerThanPlain() {
        let plain = NSHostingView(rootView: CalloutBanner("Same body text here.", style: .info))
        let titled = NSHostingView(rootView: CalloutBanner("Same body text here.", title: "Lead line", style: .info))
        plain.setFrameSize(NSSize(width: 360, height: 0))
        titled.setFrameSize(NSSize(width: 360, height: 0))
        plain.layoutSubtreeIfNeeded()
        titled.layoutSubtreeIfNeeded()
        XCTAssertGreaterThan(titled.fittingSize.height, plain.fittingSize.height)
    }

    // MARK: - Style Mapping

    func testStyleDefaultSymbols() {
        XCTAssertEqual(CalloutBanner.Style.info.defaultSymbol, "info.circle.fill")
        XCTAssertEqual(CalloutBanner.Style.success.defaultSymbol, "checkmark.circle.fill")
        XCTAssertEqual(CalloutBanner.Style.warning.defaultSymbol, "exclamationmark.triangle.fill")
        XCTAssertEqual(CalloutBanner.Style.error.defaultSymbol, "exclamationmark.octagon.fill")
        XCTAssertEqual(CalloutBanner.Style.neutral.defaultSymbol, "info.circle.fill")
    }

    func testStyleTintsMapToDesignSystemSemantics() {
        let tints: [Color] = [
            CalloutBanner.Style.info.tint,
            CalloutBanner.Style.success.tint,
            CalloutBanner.Style.warning.tint,
            CalloutBanner.Style.error.tint
        ]
        XCTAssertEqual(tints, [DSColor.info, DSColor.success, DSColor.warning, DSColor.error])
    }
}
