//
//  TrackInfoCommandAliasTests.swift
//  WolfWave
//
//  Created by Nathanial Henniges on 2026-05-28.
//  Copyright © 2026 MrDemonWolf, Inc. All rights reserved.
//

import XCTest
@testable import WolfWave

/// Verifies that user-configured aliases stored in UserDefaults extend the
/// trigger set of `!song`, `!last`, and `!stats` via the `BotCommand.allTriggers`
/// computed property.
@MainActor
final class TrackInfoCommandAliasTests: XCTestCase {

    private let testKey = "TrackInfoCommandAliasTests.aliases"

    override func tearDown() {
        Foundation.UserDefaults.standard.removeObject(forKey: testKey)
        super.tearDown()
    }

    private func makeCommand() -> TrackInfoCommand {
        TrackInfoCommand(
            triggers: ["!song"],
            description: "test",
            defaultMessage: "default",
            aliasesKey: testKey
        )
    }

    func testAliasesAppearInAllTriggers() {
        Foundation.UserDefaults.standard.set("np, track ", forKey: testKey)
        let cmd = makeCommand()
        XCTAssertEqual(cmd.allTriggers, ["!song", "!np", "!track"])
    }

    func testExecuteMatchesAlias() {
        Foundation.UserDefaults.standard.set("np", forKey: testKey)
        let cmd = makeCommand()
        cmd.getTrackInfo = { "Artist - Song" }
        XCTAssertEqual(cmd.execute(message: "!np"), "Artist - Song")
    }

    func testExecuteAsyncMatchesAlias() async {
        Foundation.UserDefaults.standard.set("track", forKey: testKey)
        let cmd = makeCommand()
        cmd.getTrackInfoAsync = { "Async Artist - Async Song" }
        let result = await cmd.executeAsync(message: "!track")
        XCTAssertEqual(result, "Async Artist - Async Song")
    }

    func testEmptyAliasesKeepsCanonicalTriggers() {
        Foundation.UserDefaults.standard.set("", forKey: testKey)
        let cmd = makeCommand()
        XCTAssertEqual(cmd.allTriggers, ["!song"])
    }

    func testMissingAliasesKeepsCanonicalTriggers() {
        Foundation.UserDefaults.standard.removeObject(forKey: testKey)
        let cmd = makeCommand()
        XCTAssertEqual(cmd.allTriggers, ["!song"])
    }

    func testAliasesHandleBangPrefixAndWhitespace() {
        Foundation.UserDefaults.standard.set(" !np ,  track,, !go ", forKey: testKey)
        let cmd = makeCommand()
        XCTAssertEqual(cmd.allTriggers, ["!song", "!np", "!track", "!go"])
    }

    func testExecute_ignoresAliasesWhenAliasesKeyMissing() {
        // Stored aliases under a *different* key should not leak into a command
        // initialized with `aliasesKey: nil`. Defends against future regressions
        // where someone wires the wrong key through TrackInfoCommand's init.
        Foundation.UserDefaults.standard.set("np, track", forKey: testKey)
        let cmd = TrackInfoCommand(
            triggers: ["!song"],
            description: "test",
            defaultMessage: "default",
            aliasesKey: nil
        )
        cmd.getTrackInfo = { "Artist - Song" }
        XCTAssertEqual(cmd.allTriggers, ["!song"])
        XCTAssertNil(cmd.execute(message: "!np"))
    }
}
