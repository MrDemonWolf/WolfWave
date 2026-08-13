//
//  PreferencesResolvedDomainTests.swift
//  WolfWave
//
//  Created by Nathanial Henniges on 2026-08-13.
//  Copyright © 2026 MrDemonWolf, Inc. All rights reserved.
//

import Foundation
import SwiftUI
import Testing

@testable import WolfWave

/// Coverage for the domain-resolved preference reads.
///
/// The cases that matter are the ones no picker or slider can produce: a value
/// left by a hand-edited plist, `defaults write`, an older build, or a test
/// process. Those reached SwiftUI unfiltered and trapped the settings window,
/// so each one is pinned here rather than only the happy path.
///
/// Serialized because every case mutates a shared key.
@Suite("Preferences Resolved Domains", .serialized)
struct PreferencesResolvedDomainTests {

    /// Sets `value` for the duration of `body`, restoring whatever was there.
    ///
    /// Takes `Any?` rather than the `Int?` its sibling
    /// `PreferencesResolvedPortTests` uses, because the interesting inputs here
    /// include NaN, infinity, and doubles far past `Int.max`.
    private func withStoredValue(_ value: Any?, forKey key: String, body: () -> Void) {
        let defaults = DefaultsStore.store
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

    // MARK: - Pure resolution

    @Test("resolveAllowed snaps anything outside the allowlist")
    func resolveAllowedSnaps() {
        let allowed: Set<Int> = [30, 60, 90, 120]
        #expect(Preferences.resolveAllowed(90, allowed: allowed, default: 60) == 90)
        #expect(Preferences.resolveAllowed(1, allowed: allowed, default: 60) == 60)
        #expect(Preferences.resolveAllowed(0, allowed: allowed, default: 60) == 60)
        #expect(Preferences.resolveAllowed(-5, allowed: allowed, default: 60) == 60)
        #expect(Preferences.resolveAllowed(.max, allowed: allowed, default: 60) == 60)
        #expect(Preferences.resolveAllowed(.min, allowed: allowed, default: 60) == 60)
    }

    @Test("resolveClamped rejects non-finite and clamps the rest")
    func resolveClampedHandlesEveryDouble() {
        let range: ClosedRange<Double> = 0...120
        #expect(Preferences.resolveClamped(45, range: range, default: 30) == 45)
        #expect(Preferences.resolveClamped(-10, range: range, default: 30) == 0)
        #expect(Preferences.resolveClamped(1e308, range: range, default: 30) == 120)
        #expect(Preferences.resolveClamped(.nan, range: range, default: 30) == 30)
        #expect(Preferences.resolveClamped(.infinity, range: range, default: 30) == 30)
        #expect(Preferences.resolveClamped(-.infinity, range: range, default: 30) == 30)
    }

    // MARK: - resolvedInt

    @Test("voteSkipWindowSeconds resolves every stored shape")
    func windowSecondsResolution() {
        let key = AppConstants.UserDefaults.voteSkipWindowSeconds
        let fallback = AppConstants.UserDefaults.Defaults.voteSkipWindowSeconds

        // The exact value that shipped the crash: not one of [30, 60, 90, 120],
        // so the segmented picker had no tag for it.
        withStoredValue(1, forKey: key) {
            #expect(Preferences.resolvedInt(key, default: fallback) == fallback)
        }
        withStoredValue(nil, forKey: key) {
            #expect(Preferences.resolvedInt(key, default: fallback) == fallback)
        }
        withStoredValue(-5, forKey: key) {
            #expect(Preferences.resolvedInt(key, default: fallback) == fallback)
        }
        withStoredValue(Int.max, forKey: key) {
            #expect(Preferences.resolvedInt(key, default: fallback) == fallback)
        }
        withStoredValue(1e300, forKey: key) {
            #expect(Preferences.resolvedInt(key, default: fallback) == fallback)
        }
        withStoredValue("not a number", forKey: key) {
            #expect(Preferences.resolvedInt(key, default: fallback) == fallback)
        }
        withStoredValue(90, forKey: key) {
            #expect(Preferences.resolvedInt(key, default: fallback) == 90)
        }
    }

    @Test("voteSkipMinVotes snaps a value the picker cannot show")
    func minVotesResolution() {
        let key = AppConstants.UserDefaults.voteSkipMinVotes
        let fallback = AppConstants.UserDefaults.Defaults.voteSkipMinVotes

        withStoredValue(4, forKey: key) {
            #expect(Preferences.resolvedInt(key, default: fallback) == fallback)
        }
        withStoredValue(5, forKey: key) {
            #expect(Preferences.resolvedInt(key, default: fallback) == 5)
        }
    }

    @Test("A key with no declared domain keeps plain int semantics")
    func undeclaredKeyFallsBackToInt() {
        let key = "resolvedDomainProbe.undeclared"
        withStoredValue(4321, forKey: key) {
            #expect(Preferences.resolvedInt(key, default: 7) == 4321)
        }
        withStoredValue(0, forKey: key) {
            #expect(Preferences.resolvedInt(key, default: 7) == 7)
        }
    }

    // MARK: - resolvedDouble

    @Test("voteSkipSessionCooldown survives every stored double")
    func sessionCooldownResolution() {
        let key = AppConstants.UserDefaults.voteSkipSessionCooldown
        let fallback = AppConstants.UserDefaults.Defaults.voteSkipSessionCooldown

        withStoredValue(Double.nan, forKey: key) {
            #expect(Preferences.resolvedDouble(key, default: fallback) == fallback)
        }
        withStoredValue(Double.infinity, forKey: key) {
            #expect(Preferences.resolvedDouble(key, default: fallback) == fallback)
        }
        withStoredValue(-Double.infinity, forKey: key) {
            #expect(Preferences.resolvedDouble(key, default: fallback) == fallback)
        }
        withStoredValue(-10.0, forKey: key) {
            #expect(Preferences.resolvedDouble(key, default: fallback) == 0)
        }
        withStoredValue(1e308, forKey: key) {
            #expect(Preferences.resolvedDouble(key, default: fallback) == 120)
        }
        // Off-step but in range: step is import validation's job, not the
        // read path's, and clamping alone is what makes `Int(…)` total.
        withStoredValue(45.0, forKey: key) {
            #expect(Preferences.resolvedDouble(key, default: fallback) == 45)
        }
    }

    /// Every resolved cooldown must be safe to hand to `Int(_:)`, which is what
    /// the settings readout and `SkipVoteManager`'s `Int(ceil(…))` both do.
    @Test("A resolved cooldown is always a safe Int conversion")
    func resolvedCooldownIsAlwaysConvertible() {
        let key = AppConstants.UserDefaults.voteSkipSessionCooldown
        let fallback = AppConstants.UserDefaults.Defaults.voteSkipSessionCooldown

        for stored in [Double.nan, .infinity, -.infinity, 1e308, -1e308, 0, 120] {
            withStoredValue(stored, forKey: key) {
                let resolved = Preferences.resolvedDouble(key, default: fallback)
                #expect(resolved.isFinite)
                #expect(resolved >= 0 && resolved <= 120)
            }
        }
    }

    // MARK: - Sanitized bindings

    // `@MainActor` is required, not stylistic: the test target defaults to
    // `nonisolated`, and touching SwiftUI's `Binding` off the main actor trips
    // an executor assertion that takes down the whole xctest host.
    @MainActor
    @Test("snapped sanitizes on read and passes writes through")
    func snappedBinding() {
        var stored = 1
        let binding = Binding(get: { stored }, set: { stored = $0 })
        let snapped = binding.snapped(to: [30, 60, 90, 120], fallback: 60)

        #expect(snapped.wrappedValue == 60)
        // The raw value is deliberately left alone: drawing a view must not
        // rewrite what is on disk.
        #expect(stored == 1)

        snapped.wrappedValue = 90
        #expect(stored == 90)
        #expect(snapped.wrappedValue == 90)
    }

    @MainActor
    @Test("clamped sanitizes on read and passes writes through")
    func clampedBinding() {
        var stored = Double.nan
        let binding = Binding(get: { stored }, set: { stored = $0 })
        let clamped = binding.clamped(to: 0...120, fallback: 30)

        #expect(clamped.wrappedValue == 30)

        stored = 1e300
        #expect(clamped.wrappedValue == 120)

        clamped.wrappedValue = 45
        #expect(stored == 45)
    }
}
