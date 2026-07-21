//
//  TwitchConnectionNoticeTests.swift
//  WolfWave
//
//  Created by Nathanial Henniges on 2026-06-05.
//  Copyright © 2026 MrDemonWolf, Inc. All rights reserved.
//

import Testing

@testable import WolfWave

/// Covers `TwitchConnectionNotice.State.resolve`, the pure mapping from the two
/// Twitch auth flags to which gate banner renders. The reauth flag must win over
/// the connection flag so an expired-but-still-socketed state shows the warning.
@Suite("TwitchConnectionNotice State")
struct TwitchConnectionNoticeTests {

    @Test("Expired sign-in resolves to .expired regardless of connection")
    func expiredWinsOverConnection() {
        #expect(
            TwitchConnectionNotice.State.resolve(isConnected: false, reauthNeeded: true) == .expired)
        #expect(
            TwitchConnectionNotice.State.resolve(isConnected: true, reauthNeeded: true) == .expired)
    }

    @Test("Not connected and not expired resolves to .disconnected")
    func disconnectedWhenNotConnected() {
        #expect(
            TwitchConnectionNotice.State.resolve(isConnected: false, reauthNeeded: false)
                == .disconnected)
    }

    @Test("Connected and not expired resolves to .ready (no banner)")
    func readyWhenConnected() {
        #expect(
            TwitchConnectionNotice.State.resolve(isConnected: true, reauthNeeded: false) == .ready)
    }
}
