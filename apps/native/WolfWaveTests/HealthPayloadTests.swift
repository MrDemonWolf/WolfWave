//
//  HealthPayloadTests.swift
//  WolfWave
//
//  Created by Nathanial Henniges on 2026-08-21.
//  Copyright © 2026 MrDemonWolf, Inc. All rights reserved.
//

import Testing
@testable import WolfWave

/// Pins the `health` frame shape the Stream Deck Status key reads. `discord`
/// stays the legacy boolean; `discordState` is additive and keeps "off"
/// distinguishable from "disconnected".
@Suite("Health payload")
struct HealthPayloadTests {
    private func data(discord: Bool, discordState: String) -> [String: Any] {
        let payload = WebSocketServerService.healthPayload(
            music: true, twitch: false, discord: discord,
            discordState: discordState, overlay: true)
        #expect(payload["type"] as? String == "health")
        return payload["data"] as? [String: Any] ?? [:]
    }

    @Test("carries every flag plus discordState")
    func shape() {
        let data = data(discord: true, discordState: "connected")
        #expect(data["music"] as? Bool == true)
        #expect(data["twitch"] as? Bool == false)
        #expect(data["discord"] as? Bool == true)
        #expect(data["discordState"] as? String == "connected")
        #expect(data["overlay"] as? Bool == true)
    }

    @Test("off and disconnected both read false but stay distinguishable")
    func offVersusDisconnected() {
        let off = data(discord: false, discordState: "off")
        let down = data(discord: false, discordState: "disconnected")
        #expect(off["discord"] as? Bool == false)
        #expect(down["discord"] as? Bool == false)
        #expect(off["discordState"] as? String != down["discordState"] as? String)
    }

    @Test("discordState raw values match the service enum")
    func rawValues() {
        #expect(DiscordRPCService.ConnectionState.connected.rawValue == "connected")
        #expect(DiscordRPCService.ConnectionState.connecting.rawValue == "connecting")
        #expect(DiscordRPCService.ConnectionState.disconnected.rawValue == "disconnected")
    }
}
