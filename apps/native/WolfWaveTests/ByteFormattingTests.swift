//
//  ByteFormattingTests.swift
//  WolfWave
//
//  Created by Nathanial Henniges on 2026-06-01.
//  Copyright © 2026 MrDemonWolf, Inc. All rights reserved.
//

import XCTest
@testable import WolfWave

@MainActor
final class ByteFormattingTests: XCTestCase {

    func testNeverReturnsEmpty() {
        XCTAssertFalse(ByteFormatting.string(0).isEmpty)
        XCTAssertFalse(ByteFormatting.string(1_024).isEmpty)
        XCTAssertFalse(ByteFormatting.string(5_000_000).isEmpty)
    }

    /// `allowedUnits = [.useKB, .useMB]` floors small sizes at KB so log / cache
    /// sizes never flip to raw bytes between the Advanced and Debug panes.
    func testSmallSizesReportInKilobytes() {
        XCTAssertTrue(ByteFormatting.string(10).contains("KB"))
        XCTAssertTrue(ByteFormatting.string(160_000).contains("KB"))
    }

    func testLargeSizesReportInMegabytes() {
        XCTAssertTrue(ByteFormatting.string(5_000_000).contains("MB"))
    }

    func testIntAndInt64OverloadsAgree() {
        XCTAssertEqual(ByteFormatting.string(160_000), ByteFormatting.string(Int64(160_000)))
    }

    func testZeroIsStableAndKilobyteBased() {
        let zero = ByteFormatting.string(0)
        XCTAssertEqual(zero, ByteFormatting.string(Int64(0)))
        XCTAssertTrue(zero.contains("KB"))
    }
}
