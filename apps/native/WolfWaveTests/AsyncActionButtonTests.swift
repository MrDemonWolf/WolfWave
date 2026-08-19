//
//  AsyncActionButtonTests.swift
//  WolfWave
//
//  Created by Nathanial Henniges on 2026-08-18.
//  Copyright © 2026 MrDemonWolf, Inc. All rights reserved.
//

import XCTest
import SwiftUI
import AppKit
@testable import WolfWave

@MainActor
final class AsyncActionButtonTests: XCTestCase {

    func testRendersWithTitle() {
        let view = AsyncActionButton(title: "Join Channel") {}
        let host = NSHostingView(rootView: view)
        host.layoutSubtreeIfNeeded()
        XCTAssertGreaterThan(host.fittingSize.width, 0)
        XCTAssertGreaterThan(host.fittingSize.height, 0)
    }

    func testRendersWithIcon() {
        let view = AsyncActionButton(
            title: "Fetch link",
            systemImage: "arrow.down.circle",
            style: .borderedProminent
        ) {}
        let host = NSHostingView(rootView: view)
        host.layoutSubtreeIfNeeded()
        XCTAssertGreaterThan(host.fittingSize.width, 0)
    }

    func testRendersDestructiveRole() {
        let view = AsyncActionButton(title: "Clear Queue", role: .destructive) {}
        let host = NSHostingView(rootView: view)
        host.layoutSubtreeIfNeeded()
        XCTAssertGreaterThan(host.fittingSize.width, 0)
    }

    func testRendersDisabled() {
        let view = AsyncActionButton(title: "Apply", isDisabled: true) {}
        let host = NSHostingView(rootView: view)
        host.layoutSubtreeIfNeeded()
        XCTAssertGreaterThan(host.fittingSize.width, 0)
    }

    func testActionNotInvokedAtConstruction() {
        // We can't synthesize a click in unit tests without a window, so this
        // pins the other half of the contract: constructing and laying out the
        // button must never run the action.
        let ran = Ran()
        let view = AsyncActionButton(title: "Export Logs") { ran.value = true }
        let host = NSHostingView(rootView: view)
        host.layoutSubtreeIfNeeded()
        XCTAssertFalse(ran.value)
        XCTAssertGreaterThan(host.fittingSize.height, 0)
    }

    func testStableWidthIsWiderThanBareSpinner() {
        // The width lock must measure the idle label, not just whatever state
        // is showing, or the button would shrink to spinner width mid-action.
        let button = AsyncActionButton(title: "A very long action title") {}
        let buttonHost = NSHostingView(rootView: button)
        buttonHost.layoutSubtreeIfNeeded()

        let spinnerHost = NSHostingView(
            rootView: ProgressView().progressViewStyle(.circular).controlSize(.mini)
        )
        spinnerHost.layoutSubtreeIfNeeded()

        XCTAssertGreaterThan(buttonHost.fittingSize.width, spinnerHost.fittingSize.width)
    }

    // MARK: - Helpers

    /// Reference box so the escaping action closure can record a call without
    /// capturing a `var` in a way the compiler rejects.
    private final class Ran {
        var value = false
    }
}
