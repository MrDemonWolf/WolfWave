//
//  DefaultsStoreTests.swift
//  WolfWave
//
//  Created by Nathanial Henniges on 2026-08-13.
//  Copyright © 2026 MrDemonWolf, Inc. All rights reserved.
//

import Foundation
import Testing

@testable import WolfWave

/// Pins the isolation branch of ``DefaultsStore``, the way
/// `KeychainServiceTests` pins the in-memory Keychain backend.
///
/// This is the one file in the repo allowed to name `UserDefaults.standard`:
/// proving the seam does *not* resolve to it requires referring to it.
@Suite("DefaultsStore Isolation")
struct DefaultsStoreTests {

    @Test("A test host resolves to the isolated suite, never the live domain")
    func testHostUsesIsolatedSuite() {
        #expect(WolfWaveApp.isRunningTests)
        #expect(DefaultsStore.store !== UserDefaults.standard)
    }

    @Test("The factory branches on the test flag and nothing else")
    func factoryBranchesOnTestFlag() {
        // `UserDefaults.standard` is a singleton, so identity pins both branches.
        #expect(DefaultsStore.makeDefaultStore(isRunningTests: false) === UserDefaults.standard)
        #expect(DefaultsStore.makeDefaultStore(isRunningTests: true) !== UserDefaults.standard)
    }

    @Test("Writes through the seam never reach the live app domain")
    func writesDoNotReachStandardDomain() {
        let key = "defaultsStoreIsolationProbe-\(UUID().uuidString)"
        DefaultsStore.store.set("probe", forKey: key)
        defer { DefaultsStore.store.removeObject(forKey: key) }

        #expect(DefaultsStore.store.string(forKey: key) == "probe")
        #expect(UserDefaults.standard.object(forKey: key) == nil)
    }

    /// The regression that made this seam land twice.
    ///
    /// `Preferences` and `FeatureFlags` expose their store as a *computed*
    /// property (`{ .standard }`), not an assignment, so the first migration
    /// pass missed them: tests wrote to the isolated suite while the code under
    /// test still read the live domain. Nothing failed loudly. Reads simply
    /// returned defaults, one vote-skip test deadlocked waiting for a poll that
    /// was never created, and the run stalled 512 tests in.
    @Test("Preferences reads the same store tests write")
    func preferencesSharesTheSeam() {
        let key = "defaultsStoreSeamProbe-\(UUID().uuidString)"
        DefaultsStore.store.set(true, forKey: key)
        defer { DefaultsStore.store.removeObject(forKey: key) }

        #expect(Preferences.bool(key, default: false))
    }

    @Test("FeatureFlags reads the same store tests write")
    func featureFlagsSharesTheSeam() {
        let key = AppConstants.UserDefaults.discordPresenceEnabled
        let previous = DefaultsStore.store.object(forKey: key)
        defer {
            if let previous {
                DefaultsStore.store.set(previous, forKey: key)
            } else {
                DefaultsStore.store.removeObject(forKey: key)
            }
        }

        DefaultsStore.store.set(true, forKey: key)
        #expect(FeatureFlags.discordEnabled)
        DefaultsStore.store.set(false, forKey: key)
        #expect(!FeatureFlags.discordEnabled)
    }
}
