//
//  PreferencesResolvedPortTests.swift
//  WolfWave
//
//  Created by Nathanial Henniges on 2026-07-10.
//  Copyright © 2026 MrDemonWolf, Inc. All rights reserved.
//

import Foundation
import Testing
@testable import WolfWave

/// Covers the shared port resolution in `Preferences`:
/// unset/zero falls back to the default, and out-of-range stored values
/// (a hand-edited plist or corrupted settings backup) clamp instead of
/// trapping. Serialized because both tests mutate the same UserDefaults keys.
@Suite("Preferences Resolved Ports", .serialized)
struct PreferencesResolvedPortTests {

    /// Runs `body` with `value` stored under `key`, restoring the previous
    /// value afterwards so the suite never leaks state into other tests.
    private func withStoredValue(_ value: Int?, forKey key: String, body: () -> Void) {
        let defaults = UserDefaults.standard
        let previous = defaults.object(forKey: key)
        defer {
            if let previous {
                defaults.set(previous, forKey: key)
            } else {
                defaults.removeObject(forKey: key)
            }
        }
        if let value {
            defaults.set(value, forKey: key)
        } else {
            defaults.removeObject(forKey: key)
        }
        body()
    }

    @Test("Widget port: unset, zero, and negative resolve to the default")
    func widgetPortFallsBackToDefault() {
        let key = AppConstants.UserDefaults.widgetPort
        let defaultPort = AppConstants.WebSocketServer.widgetDefaultPort

        withStoredValue(nil, forKey: key) {
            #expect(Preferences.resolvedWidgetPort == defaultPort)
        }
        withStoredValue(0, forKey: key) {
            #expect(Preferences.resolvedWidgetPort == defaultPort)
        }
        withStoredValue(-1, forKey: key) {
            #expect(Preferences.resolvedWidgetPort == defaultPort)
        }
    }

    @Test("Widget port: in-range passes through, oversized clamps instead of trapping")
    func widgetPortClampsOutOfRange() {
        let key = AppConstants.UserDefaults.widgetPort

        withStoredValue(9000, forKey: key) {
            #expect(Preferences.resolvedWidgetPort == 9000)
        }
        // A corrupted backup or `defaults write` can persist > 65535; the
        // trapping `UInt16(Int)` initializer used to crash the pane here.
        withStoredValue(70000, forKey: key) {
            #expect(Preferences.resolvedWidgetPort == UInt16.max)
        }
    }

    @Test("WebSocket port: default fallback, pass-through, and clamping")
    func websocketServerPortResolution() {
        let key = AppConstants.UserDefaults.websocketServerPort
        let defaultPort = AppConstants.WebSocketServer.defaultPort

        withStoredValue(nil, forKey: key) {
            #expect(Preferences.resolvedWebSocketServerPort == defaultPort)
        }
        withStoredValue(0, forKey: key) {
            #expect(Preferences.resolvedWebSocketServerPort == defaultPort)
        }
        withStoredValue(-42, forKey: key) {
            #expect(Preferences.resolvedWebSocketServerPort == defaultPort)
        }
        withStoredValue(1024, forKey: key) {
            #expect(Preferences.resolvedWebSocketServerPort == 1024)
        }
        withStoredValue(70000, forKey: key) {
            #expect(Preferences.resolvedWebSocketServerPort == UInt16.max)
        }
    }
}
