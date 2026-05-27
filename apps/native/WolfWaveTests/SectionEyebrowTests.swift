//
//  SectionEyebrowTests.swift
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
final class SectionEyebrowTests: XCTestCase {

    func testModifierRenders() {
        let view = Text("Recently played").sectionEyebrow()
        let host = NSHostingView(rootView: view)
        host.layoutSubtreeIfNeeded()
        XCTAssertGreaterThan(host.fittingSize.width, 0)
        XCTAssertGreaterThan(host.fittingSize.height, 0)
    }

    func testModifierComposable() {
        // Eyebrow modifier composes with other modifiers without breaking
        // layout — used in cardHeader helpers across History & Stats / Debug.
        let view = HStack(spacing: 6) {
            Image(systemName: "clock")
            Text("Top artists").sectionEyebrow()
        }
        let host = NSHostingView(rootView: view)
        host.layoutSubtreeIfNeeded()
        XCTAssertGreaterThan(host.fittingSize.width, 0)
    }
}
