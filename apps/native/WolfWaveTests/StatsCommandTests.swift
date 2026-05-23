//
//  StatsCommandTests.swift
//  wolfwave
//
//  Created by MrDemonWolf, Inc. on 5/22/26.
//

import Testing
import Foundation
@testable import WolfWave

/// Tests for the `!stats` Twitch command: trigger matching, the enabled gate
/// (which folds in stream-live state), and dispatcher routing.
@MainActor
@Suite("Stats Command Tests")
struct StatsCommandTests {

    // MARK: - Helpers

    /// A dispatcher with `!stats` wired to fixed info + enabled closures.
    private func makeDispatcher(
        info: @escaping () -> String,
        enabled: @escaping () -> Bool
    ) -> BotCommandDispatcher {
        let dispatcher = BotCommandDispatcher()
        dispatcher.setStatsInfo(callback: info)
        dispatcher.setStatsCommandEnabled(callback: enabled)
        return dispatcher
    }

    // MARK: - Tests

    @Test("!stats replies with the stats string when enabled and live")
    func testRepliesWhenEnabled() {
        let dispatcher = makeDispatcher(
            info: { "🐺 Today: 47 plays" },
            enabled: { true }
        )
        let reply = dispatcher.processMessage("!stats", userID: "u1")
        #expect(reply == "🐺 Today: 47 plays")
    }

    @Test("!stats stays silent when the gate is closed (offline or disabled)")
    func testSilentWhenDisabled() {
        let dispatcher = makeDispatcher(
            info: { "🐺 Today: 47 plays" },
            enabled: { false }
        )
        let reply = dispatcher.processMessage("!stats", userID: "u1")
        #expect(reply == nil)
    }

    @Test("The !musicstats alias also works")
    func testAliasTrigger() {
        let dispatcher = makeDispatcher(
            info: { "🐺 stats here" },
            enabled: { true }
        )
        #expect(dispatcher.processMessage("!musicstats", userID: "u1") == "🐺 stats here")
    }

    @Test("Unrelated messages do not trigger !stats")
    func testNoFalseTrigger() {
        let dispatcher = makeDispatcher(
            info: { "🐺 stats here" },
            enabled: { true }
        )
        #expect(dispatcher.processMessage("just chatting", userID: "u1") == nil)
        #expect(dispatcher.processMessage("!song", userID: "u1") != "🐺 stats here")
    }

    @Test("A very long stats string is truncated for chat")
    func testTruncation() {
        let long = String(repeating: "x", count: 800)
        let dispatcher = makeDispatcher(info: { long }, enabled: { true })
        let reply = dispatcher.processMessage("!stats", userID: "u1")
        #expect((reply?.count ?? 0) <= AppConstants.Twitch.maxMessageLength)
    }
}
