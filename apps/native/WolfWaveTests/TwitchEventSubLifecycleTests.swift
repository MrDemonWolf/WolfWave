//
//  TwitchEventSubLifecycleTests.swift
//  WolfWave
//
//  Created by Nathanial Henniges on 2026-06-06.
//  Copyright © 2026 MrDemonWolf, Inc. All rights reserved.
//

import Testing
import Foundation
@testable import WolfWave

/// Covers the `nonisolated` EventSub decision helpers added for the session
/// lifecycle work (B2): `reconnect_url` extraction, the keepalive deadline /
/// timeout parse, and the revocation `(type, status)` mapping. These are pure
/// functions, so the live socket orchestration around them stays untested here
/// by design (it cannot be integration-tested without a real Twitch session).
@Suite("Twitch EventSub Lifecycle Helpers")
struct TwitchEventSubLifecycleTests {

    // MARK: - reconnectURL

    private func reconnectMessage(url: Any?) -> [String: Any] {
        var session: [String: Any] = ["id": "abc"]
        if let url { session["reconnect_url"] = url }
        return ["payload": ["session": session]]
    }

    @Test("reconnectURL extracts a valid wss reconnect_url")
    func testReconnectURLValid() {
        let json = reconnectMessage(
            url: "wss://eventsub.wss.twitch.tv/ws?challenge=xyz")
        #expect(
            TwitchChatService.reconnectURL(from: json)
                == "wss://eventsub.wss.twitch.tv/ws?challenge=xyz")
    }

    @Test("reconnectURL accepts ws scheme")
    func testReconnectURLWsScheme() {
        let json = reconnectMessage(url: "ws://localhost:8080/ws")
        #expect(TwitchChatService.reconnectURL(from: json) == "ws://localhost:8080/ws")
    }

    @Test("reconnectURL trims surrounding whitespace")
    func testReconnectURLTrims() {
        let json = reconnectMessage(url: "  wss://eventsub.wss.twitch.tv/ws  ")
        #expect(
            TwitchChatService.reconnectURL(from: json)
                == "wss://eventsub.wss.twitch.tv/ws")
    }

    @Test("reconnectURL returns nil when field is missing")
    func testReconnectURLMissing() {
        #expect(TwitchChatService.reconnectURL(from: reconnectMessage(url: nil)) == nil)
    }

    @Test("reconnectURL returns nil for empty string")
    func testReconnectURLEmpty() {
        #expect(TwitchChatService.reconnectURL(from: reconnectMessage(url: "   ")) == nil)
    }

    @Test("reconnectURL rejects non-websocket schemes")
    func testReconnectURLRejectsHTTP() {
        #expect(
            TwitchChatService.reconnectURL(from: reconnectMessage(url: "https://twitch.tv")) == nil)
    }

    @Test("reconnectURL rejects a host-less URL")
    func testReconnectURLRejectsHostless() {
        #expect(TwitchChatService.reconnectURL(from: reconnectMessage(url: "wss://")) == nil)
    }

    @Test("reconnectURL returns nil when payload is absent")
    func testReconnectURLNoPayload() {
        #expect(TwitchChatService.reconnectURL(from: ["metadata": ["x": 1]]) == nil)
    }

    // MARK: - keepaliveTimeoutSeconds

    private func welcome(keepalive: Any?) -> [String: Any] {
        var session: [String: Any] = ["id": "abc"]
        if let keepalive { session["keepalive_timeout_seconds"] = keepalive }
        return ["payload": ["session": session]]
    }

    @Test("keepaliveTimeoutSeconds reads an integer value")
    func testKeepaliveInt() {
        #expect(TwitchChatService.keepaliveTimeoutSeconds(from: welcome(keepalive: 30)) == 30)
    }

    @Test("keepaliveTimeoutSeconds tolerates a numeric string")
    func testKeepaliveString() {
        #expect(TwitchChatService.keepaliveTimeoutSeconds(from: welcome(keepalive: "45")) == 45)
    }

    @Test("keepaliveTimeoutSeconds returns nil when missing")
    func testKeepaliveMissing() {
        #expect(TwitchChatService.keepaliveTimeoutSeconds(from: welcome(keepalive: nil)) == nil)
    }

    @Test("keepaliveTimeoutSeconds returns nil for non-positive values")
    func testKeepaliveNonPositive() {
        #expect(TwitchChatService.keepaliveTimeoutSeconds(from: welcome(keepalive: 0)) == nil)
        #expect(TwitchChatService.keepaliveTimeoutSeconds(from: welcome(keepalive: -5)) == nil)
    }

    // MARK: - keepaliveDeadline

    @Test("keepaliveDeadline sums timeout and grace")
    func testKeepaliveDeadlineSum() {
        #expect(
            TwitchChatService.keepaliveDeadline(timeoutSeconds: 10, grace: 10) == 20)
    }

    @Test("keepaliveDeadline clamps degenerate input to a positive minimum")
    func testKeepaliveDeadlineClamp() {
        #expect(
            TwitchChatService.keepaliveDeadline(timeoutSeconds: -100, grace: -100) == 1)
    }

    @Test("keepaliveDeadline ignores negative grace but keeps positive timeout")
    func testKeepaliveDeadlineNegativeGrace() {
        #expect(
            TwitchChatService.keepaliveDeadline(timeoutSeconds: 30, grace: -5) == 30)
    }

    // MARK: - revocationDisposition

    @Test("revocationDisposition maps authorization_revoked to reauth")
    func testRevocationReauth() {
        #expect(
            TwitchChatService.revocationDisposition(
                type: "channel.chat.message", status: "authorization_revoked") == .reauth)
    }

    @Test("revocationDisposition maps user_removed and version_removed to resubscribe")
    func testRevocationResubscribe() {
        #expect(
            TwitchChatService.revocationDisposition(
                type: "channel.chat.message", status: "user_removed") == .resubscribe)
        #expect(
            TwitchChatService.revocationDisposition(
                type: "channel.chat.message", status: "version_removed") == .resubscribe)
    }

    @Test("revocationDisposition ignores unknown statuses")
    func testRevocationIgnore() {
        #expect(
            TwitchChatService.revocationDisposition(
                type: "channel.chat.message", status: "something_else") == .ignore)
        #expect(
            TwitchChatService.revocationDisposition(type: "", status: "") == .ignore)
    }
}
