//
//  TwitchConnectionStateHubTests.swift
//  WolfWave
//
//  Created by Nathanial Henniges on 2026-07-10.
//  Copyright © 2026 MrDemonWolf, Inc. All rights reserved.
//

import Foundation
import Testing

@testable import WolfWave

/// Contract tests for `TwitchChatService.ConnectionStateHub`, the fan-out
/// registry behind `connectionStateChanges()`. The old single `AsyncStream`
/// was unicast: the first consumer's cancellation (a settings window closing
/// its view model) finished the shared continuation and silently dropped every
/// later yield for the process lifetime. These tests pin the multicast
/// contract: every subscriber sees every yield, and one subscriber's
/// termination never affects the others.
@Suite("Twitch Connection State Hub Tests")
struct TwitchConnectionStateHubTests {

    @Test("Two subscribers both receive a yield")
    func twoSubscribersBothReceiveYield() async {
        let hub = TwitchChatService.ConnectionStateHub()
        let streamA = hub.subscribe()
        let streamB = hub.subscribe()

        // Subscribers register synchronously inside subscribe(), so this yield
        // is buffered for both even before either stream is iterated.
        hub.yield(true)

        var iteratorA = streamA.makeAsyncIterator()
        var iteratorB = streamB.makeAsyncIterator()
        #expect(await iteratorA.next() == true)
        #expect(await iteratorB.next() == true)
    }

    @Test("Terminating one subscriber does not stop the other")
    func terminatingOneSubscriberKeepsOthersAlive() async {
        let hub = TwitchChatService.ConnectionStateHub()
        let streamA = hub.subscribe()
        let streamB = hub.subscribe()

        // Cancel subscriber A's consuming task; awaiting its value guarantees
        // stream A has terminated (and deregistered) before we yield again.
        let taskA = Task {
            for await _ in streamA { }
        }
        taskA.cancel()
        _ = await taskA.value

        hub.yield(false)
        hub.yield(true)

        var iteratorB = streamB.makeAsyncIterator()
        #expect(await iteratorB.next() == false)
        #expect(await iteratorB.next() == true)
    }

    @Test("Subscribing after another stream terminated still works")
    func lateSubscriberAfterTerminationStillReceives() async {
        let hub = TwitchChatService.ConnectionStateHub()

        let earlyStream = hub.subscribe()
        let earlyTask = Task {
            for await _ in earlyStream { }
        }
        earlyTask.cancel()
        _ = await earlyTask.value

        // A fresh subscription made after a prior consumer died must be fully
        // functional (this is exactly the settings-window reopen case).
        let lateStream = hub.subscribe()
        hub.yield(true)

        var iterator = lateStream.makeAsyncIterator()
        #expect(await iterator.next() == true)
    }

    @Test("finish() ends every subscriber's stream")
    func finishEndsAllStreams() async {
        let hub = TwitchChatService.ConnectionStateHub()
        let streamA = hub.subscribe()
        let streamB = hub.subscribe()

        hub.finish()

        var iteratorA = streamA.makeAsyncIterator()
        var iteratorB = streamB.makeAsyncIterator()
        #expect(await iteratorA.next() == nil)
        #expect(await iteratorB.next() == nil)
    }
}
