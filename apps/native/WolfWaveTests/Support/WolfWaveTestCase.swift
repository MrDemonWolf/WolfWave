//
//  WolfWaveTestCase.swift
//  WolfWaveTests
//
//  Copyright © 2026 MrDemonWolf, Inc. All rights reserved.
//
//  Shared base class for WolfWave unit tests. Provides helper methods for
//  UserDefaults reset and temp-directory plumbing so individual test files
//  stop reinventing the same boilerplate.
//
//  The base class is intentionally **not** annotated `@MainActor` and does
//  **not** override `setUp` / `tearDown`. Tests in this project come in two
//  flavors — nonisolated suites that invoke private static helpers from
//  inside `@Sendable` `MockURLProtocol` handlers, and `@MainActor`-annotated
//  suites that touch view-model state directly. A class-level isolation here
//  would force one flavor or the other to fight the compiler. Keeping the
//  base nonisolated and free of overrides lets subclasses keep their existing
//  setUp/tearDown bodies and simply opt in to the helpers below.
//

import XCTest

@testable import WolfWave

/// Base test case providing shared cleanup helpers.
///
/// Subclasses call `resetAllSettings()` and/or `makeTempDir()` from their own
/// `setUp` / `tearDown` overrides. Adopt incrementally — there is no harm in
/// existing tests continuing to remove individual keys explicitly.
class WolfWaveTestCase: XCTestCase {

    /// Temp directories registered for cleanup. Subclasses that call
    /// `makeTempDir()` are responsible for invoking `cleanupTrackedTempDirs()`
    /// from their own `tearDown`.
    private var trackedTempDirs: [URL] = []

    // MARK: - UserDefaults

    /// Removes every key listed in `AppConstants.UserDefaults.allKeys`.
    func resetAllSettings() {
        let defaults = Foundation.UserDefaults.standard
        for key in AppConstants.UserDefaults.allKeys {
            defaults.removeObject(forKey: key)
        }
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
