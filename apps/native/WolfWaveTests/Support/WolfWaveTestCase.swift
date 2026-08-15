//
//  WolfWaveTestCase.swift
//  WolfWave
//
//  Created by Nathanial Henniges on 2026-05-28.
//  Copyright © 2026 MrDemonWolf, Inc. All rights reserved.
//
//  Shared base class for WolfWave unit tests. Provides helper methods for
//  UserDefaults reset and temp-directory plumbing so individual test files
//  stop reinventing the same boilerplate.
//
//  The base class is intentionally **not** annotated `@MainActor`. Tests in
//  this project come in two flavors: nonisolated suites that invoke private
//  static helpers from inside `@Sendable` `MockURLProtocol` handlers, and
//  `@MainActor`-annotated suites that touch view-model state directly. A
//  class-level isolation here would force one flavor or the other to fight the
//  compiler.
//
//  It does override `setUp`, solely to take the shared-state lock (see below).
//  Subclasses keep their own setUp/tearDown bodies unchanged.
//

import XCTest

@testable import WolfWave

/// Base test case providing shared-state isolation and cleanup helpers.
///
/// Subclassing is what puts an XCTest suite under ``SharedTestStateIsolation``,
/// so **any** suite that reads or writes `DefaultsStore.store`, the Keychain
/// backend, or `Preferences.twitchReauthNeeded` must subclass this rather than
/// `XCTestCase` directly. Without it the suite races every Swift Testing suite
/// running beside it in the same process.
///
/// `makeTempDir()` remains opt-in; subclasses that use it call
/// `cleanupTrackedTempDirs()` from their own `tearDown`.
class WolfWaveTestCase: XCTestCase {

    /// Temp directories registered for cleanup. Subclasses that call
    /// `makeTempDir()` are responsible for invoking `cleanupTrackedTempDirs()`
    /// from their own `tearDown`.
    private var trackedTempDirs: [URL] = []

    // MARK: - Shared state isolation

    /// Takes the shared-state lock and starts the test on a clean settings slate.
    ///
    /// Runs *before* `super.setUp()` on purpose. XCTest's async setUp chain ends
    /// up dispatching to a subclass's synchronous `setUp()` override, so calling
    /// super first would let a subclass seed its defaults and then have this
    /// wipe them.
    ///
    /// The lock is returned from a teardown block rather than a `tearDown()`
    /// override because XCTest runs teardown blocks itself, whether or not a
    /// subclass remembered `super.tearDown()`. A stranded semaphore would hang
    /// the whole test run, so the release path must not depend on subclass
    /// discipline.
    ///
    /// `acquireAsync()` and not `acquire()`: this class has `@MainActor`
    /// subclasses, and blocking the main thread here deadlocks whenever the
    /// current holder is a `@MainActor` test suspended mid-`await`.
    override func setUp() async throws {
        await SharedTestStateIsolation.acquireAsync()
        addTeardownBlock { SharedTestStateIsolation.release() }
        resetAllSettings()
        try await super.setUp()
    }

    // MARK: - UserDefaults

    /// Removes every key listed in `AppConstants.UserDefaults.allKeys` from the
    /// isolated test suite.
    ///
    /// Goes through ``DefaultsStore/store``, which is why a mass delete is safe
    /// here: before that seam existed this wiped ~393 keys out of the dev app's
    /// live domain, because the test bundle is hosted by `WolfWave Dev.app`.
    func resetAllSettings() {
        SharedTestStateIsolation.resetAllKnownSettings()
    }

    // MARK: - Temp directories

    /// Returns a fresh, unique temp directory. Pair with
    /// `cleanupTrackedTempDirs()` in `tearDown`.
    @discardableResult
    func makeTempDir() -> URL {
        let dir = FileManager.default
            .temporaryDirectory
            .appendingPathComponent("wolfwave-tests-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        trackedTempDirs.append(dir)
        return dir
    }

    /// Removes every directory previously returned by `makeTempDir()`.
    func cleanupTrackedTempDirs() {
        for url in trackedTempDirs {
            try? FileManager.default.removeItem(at: url)
        }
        trackedTempDirs.removeAll()
    }
}
