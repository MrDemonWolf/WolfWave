//
//  ActionGridTests.swift
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
final class ActionGridTests: XCTestCase {

    func testGridHasNonzeroIntrinsicSize() {
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


}
