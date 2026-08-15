//
//  SharedTestStateIsolationTests.swift
//  WolfWave
//
//  Created by Nathanial Henniges on 2026-08-14.
//  Copyright © 2026 MrDemonWolf, Inc. All rights reserved.
//

import Foundation
import Testing

@testable import WolfWave

/// Pins ``SharedTestStateIsolation``, the way `DefaultsStoreTests` pins the
/// defaults seam and `KeychainServiceTests` pins the in-memory backend.
///
/// The lock is what stops concurrently running suites from writing each other's
/// `DefaultsStore.store` keys mid-assertion. Nothing fails loudly when it stops
/// working: the suite just goes back to flaking somewhere else, days later, in a
/// test that never mentions locking.
@Suite("Shared test state isolation", .isolatedSharedTestState)
struct SharedTestStateIsolationTests {

    private static let probeKey = AppConstants.UserDefaults.songRequestEnabled

    /// The nesting the re-entrancy exists for: this suite already holds the lock
    /// via its trait, and a test inside it opens another scope. A non-recursive
    /// semaphore would wait on itself here and hang the whole run rather than
    /// fail, so this test doubles as the deadlock canary.
    @Test("A nested scope re-enters instead of deadlocking")
    func nestedScopeReenters() async {
        await SharedTestStateIsolation.withIsolatedSharedState {
            await SharedTestStateIsolation.withIsolatedSharedState {
                #expect(Bool(true), "reached the innermost scope")
            }
        }
    }

    /// A nested scope must not wipe the settings the outer scope is asserting
    /// against. Re-entering skips the reset, which is the whole reason the
    /// re-entrant branch returns early instead of re-running setup.
    @Test("A nested scope preserves the outer scope's settings")
    func nestedScopePreservesSettings() async {
        DefaultsStore.store.set(true, forKey: Self.probeKey)
        defer { DefaultsStore.store.removeObject(forKey: Self.probeKey) }

        await SharedTestStateIsolation.withIsolatedSharedState {
            #expect(
                DefaultsStore.store.bool(forKey: Self.probeKey),
                "a re-entered scope must not reset the caller's settings")
        }
    }

    /// The trait is declared `isRecursive: false` so the lock is taken once
    /// around the suite instead of per test. If Swift Testing ever stops calling
    /// `provideScope` for that shape, the trait becomes a silent no-op and every
    /// suite carrying it goes back to racing, with nothing in the run looking
    /// any different. This is the only thing that would notice.
    @Test("The suite trait actually opened a scope")
    func traitOpensAScope() {
        #expect(
            SharedTestStateIsolation.isInsideScope,
            ".isolatedSharedTestState did not apply; the suites carrying it are unprotected")
    }

    /// `WolfWaveTestCase` releases the lock from a teardown block rather than a
    /// `tearDown()` override precisely so a subclass that forgets
    /// `super.tearDown()` cannot strand it. This suite acquiring at all proves
    /// every `WolfWaveTestCase` subclass that ran before it released.
    @Test("The lock is not stranded by suites that ran earlier")
    func lockIsNotStranded() {
        #expect(Bool(true), "reaching this test means the trait acquired the lock")
    }
}

/// The clean-slate half of the contract, which has to live in a suite that does
/// **not** carry `.isolatedSharedTestState`.
///
/// A genuinely fresh acquisition is only observable from a task tree that does
/// not already hold the lock, and re-entrancy is tracked by a `@TaskLocal` that
/// a `Task.detached` deliberately does not inherit. Putting this test in the
/// suite above meant the detached task queued behind a lock its own parent was
/// holding while awaiting it: an instant deadlock that hung the run instead of
/// failing it. Keep these two suites separate.
@Suite("Shared test state isolation, unheld")
struct SharedTestStateIsolationFreshScopeTests {

    private static let probeKey = AppConstants.UserDefaults.songRequestEnabled

    /// The property the flake needed: a scope starts clean and leaves clean, so
    /// a value written by whatever ran before is never visible inside, and a
    /// value written inside never leaks to whatever runs after.
    @Test("A fresh scope starts and ends on a clean slate")
    func freshScopeIsClean() async {
        await SharedTestStateIsolation.withIsolatedSharedState {
            DefaultsStore.store.set(true, forKey: Self.probeKey)
        }

        // A second, sequential acquisition, standing in for the next suite to
        // take the lock. Both halves assert from *inside* a scope on purpose:
        // in the gap between scopes another suite may legitimately hold the
        // lock and write this key, so a check out there would flake on the very
        // race this test exists to pin.
        await SharedTestStateIsolation.withIsolatedSharedState {
            #expect(
                !DefaultsStore.store.bool(forKey: Self.probeKey),
                "a scope must not inherit the previous holder's writes")
        }
    }
}
