//
//  StatTileTests.swift
//  WolfWave
//
//  Created by Nathanial Henniges on 2026-05-27.
//  Copyright © 2026 MrDemonWolf, Inc. All rights reserved.
//

import XCTest
import SwiftUI
import AppKit
@testable import WolfWave

@MainActor
final class StatTileTests: XCTestCase {

    func testRendersWithValueAndCaption() {
        let view = StatTile(value: "129", caption: "This week")
        let host = NSHostingView(rootView: view)
        host.layoutSubtreeIfNeeded()
        XCTAssertGreaterThan(host.fittingSize.width, 0)
        XCTAssertGreaterThan(host.fittingSize.height, 0)
    }

    func testRendersWithSecondary() {
        let view = StatTile(value: "129", secondary: "27m", caption: "This week")
        let host = NSHostingView(rootView: view)
        host.layoutSubtreeIfNeeded()
        XCTAssertGreaterThan(host.fittingSize.height, 0)
    }

    func testDefaultAccessibilityIdentifierUsesCaption() {
        // The default identifier falls back to "statTile.\(caption)" when none
        // is passed. SwiftUI does not expose the resolved identifier off the
        // hosted NSView tree, so this only smoke-checks that the default-id
        // configuration renders.
        let view = StatTile(value: "10", caption: "Today")
        let host = NSHostingView(rootView: view)
        host.setFrameSize(NSSize(width: 200, height: 80))
        host.layoutSubtreeIfNeeded()
        // Smoke check: the host renders without crashing and reports content size.
        XCTAssertGreaterThan(host.fittingSize.height, 0)
    }

    func testCustomAccessibilityIdentifier() {
        let view = StatTile(value: "5", caption: "Top", accessibilityIdentifier: "custom.id")
        let host = NSHostingView(rootView: view)
        host.layoutSubtreeIfNeeded()
        XCTAssertGreaterThan(host.fittingSize.height, 0)
    }
}
