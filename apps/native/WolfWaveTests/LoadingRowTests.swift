//
//  LoadingRowTests.swift
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
final class LoadingRowTests: XCTestCase {

    func testRendersWithLabel() {
        let view = LoadingRow(text: "Testing\u{2026}")
        let host = NSHostingView(rootView: view)
        host.layoutSubtreeIfNeeded()
        XCTAssertGreaterThan(host.fittingSize.height, 0)
        XCTAssertGreaterThan(host.fittingSize.width, 0)
    }

    func testRendersWithEmptyText() {
        let view = LoadingRow(text: "")
        let host = NSHostingView(rootView: view)
        host.layoutSubtreeIfNeeded()
        // Even with empty text, the spinner has dimensions.
        XCTAssertGreaterThan(host.fittingSize.height, 0)
    }
}
