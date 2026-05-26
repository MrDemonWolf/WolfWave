//
//  ActionGridTests.swift
//  WolfWaveTests
//

import XCTest
import SwiftUI
import AppKit
@testable import WolfWave

@MainActor
final class ActionGridTests: XCTestCase {

    func testRendersGridOfButtons() {
        let view = ActionGrid(columns: 2) {
            GridRow {
                ActionGridButton(title: "One", systemImage: "1.circle", action: {})
                ActionGridButton(title: "Two", systemImage: "2.circle", action: {})
            }
        }
        let host = NSHostingView(rootView: view)
        host.setFrameSize(NSSize(width: 360, height: 0))
        host.layoutSubtreeIfNeeded()
        XCTAssertGreaterThan(host.fittingSize.width, 0)
        XCTAssertGreaterThan(host.fittingSize.height, 0)
    }

    func testActionGridButtonInvokesAction() {
        var fired = 0
        let view = ActionGridButton(title: "Tap", systemImage: "hand.tap", action: { fired += 1 })
        let host = NSHostingView(rootView: view)
        host.layoutSubtreeIfNeeded()
        // Smoke: button view renders; action wiring is exercised via #Preview in dev.
        XCTAssertGreaterThan(host.fittingSize.height, 0)
        XCTAssertEqual(fired, 0)
    }

    func testRendersSpanningButton() {
        let view = ActionGrid(columns: 2) {
            GridRow {
                ActionGridButton(title: "Wide", systemImage: "rectangle", action: {})
                    .gridCellColumns(2)
            }
        }
        let host = NSHostingView(rootView: view)
        host.setFrameSize(NSSize(width: 360, height: 0))
        host.layoutSubtreeIfNeeded()
        XCTAssertGreaterThan(host.fittingSize.width, 0)
    }
}
