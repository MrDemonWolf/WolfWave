//
//  LabeledSliderTests.swift
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
final class LabeledSliderTests: XCTestCase {

    func testRendersWithDefaultFormatter() {
        let view = LabeledSlider(
            label: "Everyone",
            value: .constant(15.0),
            range: 0.0...60.0
        )
        let host = NSHostingView(rootView: view)
        host.setFrameSize(NSSize(width: 360, height: 0))
        host.layoutSubtreeIfNeeded()
        XCTAssertGreaterThan(host.fittingSize.width, 0)
    }

    func testCustomFormatter() {
        let value: Double = 15
        let formatted = "\(Int(value))s"
        XCTAssertEqual(formatted, "15s")

        let view = LabeledSlider(
            label: "Cooldown",
            value: .constant(value),
            range: 0.0...60.0,
            format: { "\(Int($0))s" }
        )
        let host = NSHostingView(rootView: view)
        host.setFrameSize(NSSize(width: 360, height: 0))
        host.layoutSubtreeIfNeeded()
        XCTAssertGreaterThan(host.fittingSize.height, 0)
    }

    func testBindingPropagation() {
        var stored: Double = 10
        let binding = Binding<Double>(
            get: { stored },
            set: { stored = $0 }
        )
        binding.wrappedValue = 25
        XCTAssertEqual(stored, 25, accuracy: 0.001)
    }

    // MARK: - Corrupted stored values

    func testDisplayValueClampsIntoRange() {
        XCTAssertEqual(LabeledSlider<Double>.displayValue(45, in: 0...60), 45, accuracy: 0.001)
        XCTAssertEqual(LabeledSlider<Double>.displayValue(-10, in: 0...60), 0, accuracy: 0.001)
        XCTAssertEqual(LabeledSlider<Double>.displayValue(1e308, in: 0...60), 60, accuracy: 0.001)
    }

    func testDisplayValueRejectsNonFinite() {
        XCTAssertEqual(LabeledSlider<Double>.displayValue(.nan, in: 5...60), 5, accuracy: 0.001)
        XCTAssertEqual(LabeledSlider<Double>.displayValue(.infinity, in: 5...60), 5, accuracy: 0.001)
        XCTAssertEqual(LabeledSlider<Double>.displayValue(-.infinity, in: 5...60), 5, accuracy: 0.001)
    }

    /// Rendering a corrupted stored value used to trap: the default `format` is
    /// `Int($0)`, and `Int(Double.nan)` is a hard crash rather than a bad label.
    func testRendersNonFiniteValueWithoutTrapping() {
        for value in [Double.nan, .infinity, 1e308] {
            let view = LabeledSlider(
                label: "Cooldown",
                value: .constant(value),
                range: 0.0...60.0
            )
            let host = NSHostingView(rootView: view)
            host.setFrameSize(NSSize(width: 360, height: 0))
            host.layoutSubtreeIfNeeded()
            XCTAssertGreaterThan(host.fittingSize.height, 0)
        }
    }
}
