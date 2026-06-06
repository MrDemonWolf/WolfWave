//
//  BotCommandGlobalGateTests.swift
//  WolfWave
//
//  Created by Nathanial Henniges on 2026-06-05.
//  Copyright © 2026 MrDemonWolf, Inc. All rights reserved.
//

import Testing
import Foundation
@testable import WolfWave

/// Tests for the dispatcher-wide "commands only while live" gate
/// (`setGlobalGate`). The gate runs before any per-command enable check, so a
/// closed gate silences every command at once; an open gate restores normal
/// per-command behavior. `!stats` no longer carries its own live gate and is
/// expected to follow this global one like every other command.
@MainActor
@Suite("Bot Command Global Gate Tests")
struct BotCommandGlobalGateTests {

    /// A dispatcher with `!song` and `!stats` wired and both individually enabled.
    private func makeDispatcher() -> BotCommandDispatcher {
        let dispatcher = BotCommandDispatcher()
        dispatcher.setCurrentSongInfo { "🐺 Now: Howl" }
        dispatcher.setCurrentSongCommandEnabled { true }
        dispatcher.setStatsInfo { "🐺 Today: 47 plays" }
        dispatcher.setStatsCommandEnabled { true }
        return dispatcher
    }

    @Test("Default gate is open — commands reply")
    func testDefaultGateOpen() {
        let dispatcher = makeDispatcher()
        #expect(dispatcher.processMessage("!song", userID: "u1") == "🐺 Now: Howl")
    }

    @Test("Closed gate silences an otherwise-enabled command")
    func testClosedGateSilences() {
        let dispatcher = makeDispatcher()
        dispatcher.setGlobalGate { false }
        #expect(dispatcher.processMessage("!song", userID: "u1") == nil)
    }

    @Test("Open gate lets an enabled command reply")
    func testOpenGateReplies() {
        let dispatcher = makeDispatcher()
        dispatcher.setGlobalGate { true }
        #expect(dispatcher.processMessage("!song", userID: "u1") == "🐺 Now: Howl")
    }

    @Test("!stats follows the global gate, not a built-in live gate")
    func testStatsFollowsGlobalGate() {
        let dispatcher = makeDispatcher()

        dispatcher.setGlobalGate { false }
        #expect(dispatcher.processMessage("!stats", userID: "u1") == nil)

        dispatcher.setGlobalGate { true }
        #expect(dispatcher.processMessage("!stats", userID: "u2") == "🐺 Today: 47 plays")
    }

    @Test("Gate is re-evaluated every message (live toggle takes effect)")
    func testGateReevaluatedPerMessage() {
        let dispatcher = makeDispatcher()
        var live = false
        dispatcher.setGlobalGate { live }

        #expect(dispatcher.processMessage("!song", userID: "u1") == nil)
        live = true
        #expect(dispatcher.processMessage("!song", userID: "u2") == "🐺 Now: Howl")
        live = false
        #expect(dispatcher.processMessage("!song", userID: "u3") == nil)
    }
}
