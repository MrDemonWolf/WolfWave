//
//  StreamDeckControlGateTests.swift
//  WolfWave
//
//  Created by Nathanial Henniges on 2026-08-17.
//  Copyright © 2026 MrDemonWolf, Inc. All rights reserved.
//

import Foundation
import Testing
@testable import WolfWave

/// The capability switch behind the Stream Deck pane.
///
/// `streamDeckControlEnabled` is the only preference in the app whose default is
/// "on" for a security-relevant capability, so the default itself is the thing
/// most worth pinning: it is `true` because the control token already shipped as
/// the gate, and flipping it to `false` would silently disarm every Stream Deck
/// in the field on the first launch after an update.
@Suite("Stream Deck Control Gate", .isolatedSharedTestState)
struct StreamDeckControlGateTests {

    private var store: UserDefaults { DefaultsStore.store }

    private func clear() {
        store.removeObject(forKey: AppConstants.UserDefaults.streamDeckControlEnabled)
    }

    @Test("An untouched install allows commands")
    func defaultsToEnabled() {
        clear()
        #expect(FeatureFlags.streamDeckControlEnabled)
    }

    @Test("Turning it off is honored, not treated as unset")
    func explicitFalseIsHonored() {
        store.set(false, forKey: AppConstants.UserDefaults.streamDeckControlEnabled)
        defer { clear() }
        #expect(FeatureFlags.streamDeckControlEnabled == false)
    }

    @Test("Turning it back on is honored")
    func explicitTrueIsHonored() {
        store.set(true, forKey: AppConstants.UserDefaults.streamDeckControlEnabled)
        defer { clear() }
        #expect(FeatureFlags.streamDeckControlEnabled)
    }

    /// The gate is independent of the server switch on purpose: turning Stream
    /// Deck off must not take the overlay off the air, so nothing in the read
    /// path may consult `websocketEnabled`.
    @Test("The gate does not depend on the shared server switch")
    func independentOfWebsocketEnabled() {
        store.set(true, forKey: AppConstants.UserDefaults.streamDeckControlEnabled)
        store.set(false, forKey: AppConstants.UserDefaults.websocketEnabled)
        defer {
            clear()
            store.removeObject(forKey: AppConstants.UserDefaults.websocketEnabled)
        }
        #expect(FeatureFlags.streamDeckControlEnabled)
    }

    /// A refusal has to be an ack the plugin can render. Dropping the frame
    /// would leave the key spinning, which reads as a broken connection rather
    /// than a setting the user chose.
    @Test("A refusal ack names the reason and is not a success")
    func refusalAckShape() {
        let ack = CommandAck.failure(StreamDeckAction.skip.rawValue, "disabled")
        #expect(ack.ok == false)
        #expect(ack.error == "disabled")
        #expect(ack.action == StreamDeckAction.skip.rawValue)

        let json = ack.jsonObject
        #expect(json["type"] as? String == "ack")
        #expect(json["ok"] as? Bool == false)
        #expect(json["error"] as? String == "disabled")
    }

    /// `disabled` and `unauthorized` are different diagnoses: one is a setting on
    /// this Mac, the other is a credential that may not drive the app at all.
    /// Collapsing them would send a user hunting for the wrong problem.
    @Test("Refused-by-setting is distinct from refused-by-credential")
    func disabledIsNotUnauthorized() {
        let disabled = CommandAck.failure(StreamDeckAction.skip.rawValue, "disabled")
        let unauthorized = CommandAck.failure(StreamDeckAction.skip.rawValue, "unauthorized")
        #expect(disabled != unauthorized)
    }
}
