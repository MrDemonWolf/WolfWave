//
//  HintRowTests.swift
//  WolfWave
//
//  Created by Nathanial Henniges on 2026-06-01.
//  Copyright © 2026 MrDemonWolf, Inc. All rights reserved.
//

import XCTest
import SwiftUI
import AppKit
@testable import WolfWave

@MainActor
final class HintRowTests: XCTestCase {

    func testRendersWithDefaultSymbol() {
        let host = NSHostingView(rootView: HintRow("Cooldowns don't apply to you or your mods."))
        host.layoutSubtreeIfNeeded()
        XCTAssertGreaterThan(host.fittingSize.height, 0)
        XCTAssertGreaterThan(host.fittingSize.width, 0)
    }

    func testRendersWithCustomSymbol() {
        let host = NSHostingView(rootView: HintRow("Everything stays on this Mac.", systemImage: "lock.fill"))
        host.layoutSubtreeIfNeeded()
        XCTAssertGreaterThan(host.fittingSize.height, 0)
    }

    func testRendersMultilineText() {
        let long = String(repeating: "This is a long inline tip. ", count: 6)
        let host = NSHostingView(rootView: HintRow(long))
        host.setFrameSize(NSSize(width: 280, height: 0))
        host.layoutSubtreeIfNeeded()
        XCTAssertGreaterThan(host.fittingSize.height, 0)
    }
}
