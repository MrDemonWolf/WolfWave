//
//  MonthlyWrapExportTests.swift
//  WolfWaveTests
//
//  Created by Nathanial Henniges on 2026-06-01.
//  Copyright © 2026 MrDemonWolf, Inc. All rights reserved.
//

import XCTest
@testable import WolfWave

/// Covers the pure export-file-name logic behind the Monthly Wrap save / share
/// actions. The rendering + NSSavePanel / NSSharingServicePicker paths need a
/// live service and UI and aren't unit-tested here.
@MainActor
final class MonthlyWrapExportTests: XCTestCase {

    func testExportFileNameWrapsMonthLabel() {
        XCTAssertEqual(
            MonthlyWrapView.exportFileName(forMonthLabel: "May 2026"),
            "WolfWave-Wrap-May 2026.png"
        )
    }

    func testExportFileNameHasPNGExtension() {
        let name = MonthlyWrapView.exportFileName(forMonthLabel: "April 2026")
        XCTAssertTrue(name.hasSuffix(".png"))
    }

    func testExportFileNameKeepsBrandPrefix() {
        let name = MonthlyWrapView.exportFileName(forMonthLabel: "December 2025")
        XCTAssertTrue(name.hasPrefix("WolfWave-Wrap-"))
    }

    func testExportFileNameVariesByMonth() {
        XCTAssertNotEqual(
            MonthlyWrapView.exportFileName(forMonthLabel: "May 2026"),
            MonthlyWrapView.exportFileName(forMonthLabel: "June 2026")
        )
    }
}
