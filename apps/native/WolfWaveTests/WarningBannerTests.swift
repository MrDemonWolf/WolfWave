//
//  WarningBannerTests.swift
//  WolfWaveTests
//

import XCTest
import SwiftUI
import AppKit
@testable import WolfWave

@MainActor
final class WarningBannerTests: XCTestCase {

    func testRendersWithDefaultTint() {
        let view = WarningBanner(text: "Heads up.")
        let host = NSHostingView(rootView: view)
        host.layoutSubtreeIfNeeded()
        XCTAssertGreaterThan(host.fittingSize.height, 0)
        XCTAssertGreaterThan(host.fittingSize.width, 0)
    }

    func testRendersWithRedTintAndStroke() {
        let view = WarningBanner(text: "Cannot undo.", tint: .red, strokeVisible: true)
        let host = NSHostingView(rootView: view)
        host.layoutSubtreeIfNeeded()
        XCTAssertGreaterThan(host.fittingSize.height, 0)
    }

    func testRendersMultilineText() {
        let long = String(repeating: "WolfWave needs Apple Music access. ", count: 5)
        let view = WarningBanner(text: long)
        let host = NSHostingView(rootView: view)
        host.setFrameSize(NSSize(width: 320, height: 0))
        host.layoutSubtreeIfNeeded()
        XCTAssertGreaterThan(host.fittingSize.height, 0)
    }
}
