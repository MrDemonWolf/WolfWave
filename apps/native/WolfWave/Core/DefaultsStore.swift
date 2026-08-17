//
//  DefaultsStore.swift
//  WolfWave
//
//  Created by Nathanial Henniges on 2026-08-13.
//  Copyright © 2026 MrDemonWolf, Inc. All rights reserved.
//

import Foundation

/// The `UserDefaults` instance every non-`@AppStorage` read and write goes
/// through.
///
/// Sibling of ``KeychainService/backend``, and it exists for the same reason.
/// The unit test bundle is *hosted*: `TEST_HOST` is `WolfWave Dev.app`, so a
/// test process's `UserDefaults.standard` is literally the dev app's live
/// preference domain (`com.mrdemonwolf.wolfwave.dev`). Tests that write
/// settings, and `WolfWaveTestCase.resetAllSettings()` which deletes every
/// known key, were therefore editing the developer's real app. That is not
/// hypothetical: it persisted a `voteSkipWindowSeconds` of `1`, which is not
/// one of the segmented picker's tags, and the Song Requests pane trapped
/// inside SwiftUI on the next launch.
///
/// Under test this resolves to a dedicated suite instead, so the live domain is
/// untouchable. In a normal launch it is `.standard` and nothing changes.
///
/// `@AppStorage` is deliberately *not* routed here: views are never rendered
/// against persisted values in the hosted unit bundle, and `store:` on 160-odd
/// property wrappers would be a large diff for no coverage. Do not drive
/// `@AppStorage` bindings from a hosted unit test.
nonisolated enum DefaultsStore {

    /// Suite that absorbs every defaults read and write in a test host.
    ///
    /// Deliberately not any bundle identifier in the project. The xctest bundle
    /// is itself `com.mrdemonwolf.wolfwave.tests`, and while reusing that name
    /// does work, a suite that doubles as a loaded bundle's own domain is a
    /// confusing thing to debug. This name belongs to nothing else.
    static let testSuiteName = "com.mrdemonwolf.wolfwave.test-defaults"

    /// Backing store for every non-`@AppStorage` defaults access.
    ///
    /// Resolved once on first touch and never reassigned, so unlike
    /// ``KeychainService/backend`` there is no swap to serialize.
    nonisolated(unsafe) static let store: UserDefaults = {
        let resolved = makeDefaultStore(isRunningTests: UITestMode.isUnderTestHarness)
        if UITestMode.isUnderTestHarness {
            // One wipe per test process: a clean slate, and it clears residue
            // from an aborted earlier run. Deliberately here and not in the
            // factory, so `makeDefaultStore` stays a pure branch the guard test
            // can call without destroying state a live suite already wrote.
            resolved.removePersistentDomain(forName: testSuiteName)
        }
        return resolved
    }()

    /// Kept internal so the test suite can pin both branches.
    ///
    /// Traps rather than falling back to `.standard` when the suite cannot be
    /// opened: a silent fallback would restore exactly the corruption this type
    /// exists to prevent, and the branch is unreachable outside a test host.
    static func makeDefaultStore(isRunningTests: Bool) -> UserDefaults {
        guard isRunningTests else { return .standard }
        guard let suite = UserDefaults(suiteName: testSuiteName) else {
            preconditionFailure("UserDefaults(suiteName: \(testSuiteName)) returned nil")
        }
        return suite
    }
}
