//
//  InlineMarkdownTests.swift
//  WolfWave
//
//  Created by Nathanial Henniges on 2026-06-01.
//  Copyright © 2026 MrDemonWolf, Inc. All rights reserved.
//

import XCTest
@testable import WolfWave

@MainActor
final class InlineMarkdownTests: XCTestCase {

    func testParsesBoldAndStripsAsterisks() {
        let result = InlineMarkdown.attributed("Viewers type **!sr song name** in chat")
        let plain = String(result.characters)
        XCTAssertFalse(plain.contains("*"), "Markdown markers must be consumed, not rendered literally")
        XCTAssertTrue(plain.contains("!sr song name"))
        XCTAssertTrue(plain.contains("Viewers type"))
    }

    func testPreservesWhitespaceAndStripsMultipleBoldRuns() {
        let result = InlineMarkdown.attributed("Set **Width** and **Height** for best results.")
        XCTAssertEqual(String(result.characters), "Set Width and Height for best results.")
    }

    func testPlainStringRoundTrips() {
        let result = InlineMarkdown.attributed("No markdown here, just text.")
        XCTAssertEqual(String(result.characters), "No markdown here, just text.")
    }
}
