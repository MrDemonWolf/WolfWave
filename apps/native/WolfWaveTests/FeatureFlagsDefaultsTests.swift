//
//  FeatureFlagsDefaultsTests.swift
//  WolfWave
//
//  Created by Nathanial Henniges on 2026-07-18.
//  Copyright © 2026 MrDemonWolf, Inc. All rights reserved.
//

import Foundation
import Testing
@testable import WolfWave

/// Locks the first-launch default semantics of the `FeatureFlags` toggles that
/// were migrated onto `Preferences.bool(_:default:)`: an unset key must resolve
/// to the documented default, and an explicitly-written value must win.
///
/// Serialized because every case mutates a shared `UserDefaults.standard` key.
@Suite("FeatureFlags Defaults", .serialized)
struct FeatureFlagsDefaultsTests {

    /// Runs `body` with `value` stored under `key` (or the key removed when
    /// `value` is nil), restoring the previous stored value afterwards so the
    /// suite never leaks state into other tests.
    private func withStoredBool(_ value: Bool?, forKey key: String, body: () -> Void) {
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

    @Test("trackingEnabled: unset defaults true, explicit value wins")
    func trackingEnabledDefault() {
        let key = AppConstants.UserDefaults.trackingEnabled
        withStoredBool(nil, forKey: key) { #expect(FeatureFlags.trackingEnabled) }
        withStoredBool(false, forKey: key) { #expect(!FeatureFlags.trackingEnabled) }
        withStoredBool(true, forKey: key) { #expect(FeatureFlags.trackingEnabled) }
    }

    @Test("discordShowIdleStatus: unset defaults true, explicit value wins")
    func discordShowIdleStatusDefault() {
        let key = AppConstants.UserDefaults.discordShowIdleStatus
        withStoredBool(nil, forKey: key) { #expect(FeatureFlags.discordShowIdleStatus) }
        withStoredBool(false, forKey: key) { #expect(!FeatureFlags.discordShowIdleStatus) }
        withStoredBool(true, forKey: key) { #expect(FeatureFlags.discordShowIdleStatus) }
    }

    @Test("widgetHTTPEnabled: unset defaults false, explicit value wins")
    func widgetHTTPEnabledDefault() {
        let key = AppConstants.UserDefaults.widgetHTTPEnabled
        withStoredBool(nil, forKey: key) { #expect(!FeatureFlags.widgetHTTPEnabled) }
        withStoredBool(true, forKey: key) { #expect(FeatureFlags.widgetHTTPEnabled) }
        withStoredBool(false, forKey: key) { #expect(!FeatureFlags.widgetHTTPEnabled) }
    }
}
