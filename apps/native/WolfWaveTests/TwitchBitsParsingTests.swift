//
//  TwitchBitsParsingTests.swift
//  WolfWave
//
//  Created by Nathanial Henniges on 2026-05-22.
//  Copyright © 2026 MrDemonWolf, Inc. All rights reserved.
//

import XCTest

@testable import WolfWave

@MainActor
final class TwitchBitsParsingTests: XCTestCase {

    // MARK: - cleanBitsMessage with fragments

    func testCleanBitsMessageJoinsTextFragments() {
        let message: [String: Any] = [
            "text": "Cheer100 Bohemian Rhapsody",
            "fragments": [
                ["type": "cheermote", "text": "Cheer100"],
                ["type": "text", "text": " Bohemian Rhapsody"],
            ],
        ]
        XCTAssertEqual(
            TwitchChatService.cleanBitsMessage(message), "Bohemian Rhapsody")
    }

    func testCleanBitsMessageHandlesMultipleTextFragments() {
        let message: [String: Any] = [
            "text": "Cheer50 take Cheer100 on me",
            "fragments": [
                ["type": "cheermote", "text": "Cheer50"],
                ["type": "text", "text": " take "],
                ["type": "cheermote", "text": "Cheer100"],
                ["type": "text", "text": " on me"],
            ],
        ]
        XCTAssertEqual(
            TwitchChatService.cleanBitsMessage(message), "take  on me")
    }

    func testCleanBitsMessageReturnsEmptyForNil() {
        XCTAssertEqual(TwitchChatService.cleanBitsMessage(nil), "")
    }

    func testCleanBitsMessageFallsBackToStrippingWhenFragmentsMissing() {
        let message: [String: Any] = ["text": "Cheer250 Africa by Toto"]
        XCTAssertEqual(
            TwitchChatService.cleanBitsMessage(message), "Africa by Toto")
    }

    // MARK: - stripLeadingCheermotes

    func testStripLeadingCheermotesRemovesSingleToken() {
        XCTAssertEqual(
            TwitchChatService.stripLeadingCheermotes("Cheer100 Bohemian Rhapsody"),
            "Bohemian Rhapsody")
    }

    func testStripLeadingCheermotesRemovesMultipleTokens() {
        XCTAssertEqual(
            TwitchChatService.stripLeadingCheermotes("Cheer100 Cheer50 Africa"), "Africa")
    }

    func testStripLeadingCheermotesIsCaseInsensitive() {
        XCTAssertEqual(
            TwitchChatService.stripLeadingCheermotes("cheer250 Wonderwall"), "Wonderwall")
    }

    func testStripLeadingCheermotesLeavesNonCheermoteTextUnchanged() {
        XCTAssertEqual(
            TwitchChatService.stripLeadingCheermotes("Bohemian Rhapsody"), "Bohemian Rhapsody")
    }

    func testStripLeadingCheermotesDoesNotStripMidString() {
        // "U2 One" should NOT be treated as a cheermote — the strip only matches at the start.
        XCTAssertEqual(
            TwitchChatService.stripLeadingCheermotes("Beautiful Day by U2"), "Beautiful Day by U2")
    }
}
