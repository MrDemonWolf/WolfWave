//
//  DestructiveButtonTests.swift
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
final class DestructiveButtonTests: XCTestCase {

    func testRendersWithTitle() {
        let view = DestructiveButton(title: "Reset", action: {})
        let host = NSHostingView(rootView: view)
        host.layoutSubtreeIfNeeded()
        XCTAssertGreaterThan(host.fittingSize.width, 0)
    }

    func testRendersWithIcon() {
        let view = DestructiveButton(title: "Clear Logs", systemImage: "trash", action: {})
        let host = NSHostingView(rootView: view)
        host.layoutSubtreeIfNeeded()
        XCTAssertGreaterThan(host.fittingSize.width, 0)
    }

    func testActionWiringSmokeCheck() {
        // We can't synthesize a click in unit tests without a window — verify
        // the action closure is captured without invocation.
        var fired = 0
        let view = DestructiveButton(title: "Delete", action: { fired += 1 })
        let host = NSHostingView(rootView: view)
        host.layoutSubtreeIfNeeded()
        XCTAssertEqual(fired, 0)
        XCTAssertGreaterThan(host.fittingSize.height, 0)
    }
}
