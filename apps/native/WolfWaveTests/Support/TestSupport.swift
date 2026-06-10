//
//  TestSupport.swift
//  WolfWave
//
//  Created by Nathanial Henniges on 2026-05-28.
//  Copyright © 2026 MrDemonWolf, Inc. All rights reserved.
//
//  Free helpers used by both XCTest and Swift Testing suites.
//

import Foundation
import Testing

/// Creates a fresh, unique temp directory and ensures it exists. Returns the URL.
///
/// Swift Testing suites don't have tearDown. Callers are responsible for cleanup
/// (or rely on the OS reclaiming `tmp`). Prefer `WolfWaveTestCase.makeTempDir()`
/// for XCTest-based suites, which auto-cleans on tearDown.
func makeIsolatedTempDirectory(prefix: String = "wolfwave-test") -> URL {
    let dir = FileManager.default
        .temporaryDirectory
        .appendingPathComponent("\(prefix)-\(UUID().uuidString)", isDirectory: true)
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir
}

/// Thread-safe value box for capturing state from inside `@Sendable` closures
/// (mock request handlers, actor callbacks) without violating strict
/// concurrency. NSLock is fine here; tests aren't measuring lock perf.
///
/// Shared by the suites that previously each declared a private copy
/// (`RequestCounter`, `TestValueBox`, `Box`). Deliberately not named `Atomic`
/// so it never shadows the production type in `Core/ThreadSafeStorage.swift`
/// (exercised directly by `AtomicTests`).
nonisolated final class ThreadSafeBox<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: Value

    init(_ value: Value) { stored = value }

    var value: Value {
        get { lock.withLock { stored } }
        set { lock.withLock { stored = newValue } }
    }

    /// Atomically replaces the stored value.
    func set(_ newValue: Value) { lock.withLock { stored = newValue } }

    /// Atomically transforms the stored value in place.
    func mutate(_ transform: (inout Value) -> Void) { lock.withLock { transform(&stored) } }
}

/// Polls `condition` until it returns true or the timeout elapses, returning
/// the final result. Avoids fixed sleeps when waiting on async work (disk I/O,
/// actor state), which are flaky under CI load.
///
/// The condition may be synchronous or `async`; non-async closures convert
/// implicitly. Shared by the suites that previously each declared a private
/// copy (ArtworkServiceNetworkTests, SkipVoteManagerTests,
/// SongRequestServiceTests).
@discardableResult
func waitUntil(
    timeout: Duration = .seconds(2),
    interval: Duration = .milliseconds(20),
    _ condition: () async -> Bool
) async -> Bool {
    let deadline = ContinuousClock.now + timeout
    while ContinuousClock.now < deadline {
        if await condition() { return true }
        try? await Task.sleep(for: interval)
    }
    return await condition()
}

/// Round-trips a credential through a save/load/delete cycle and asserts the
/// loaded value matches what was saved.
///
/// Collapses the save → assert → delete → assert-nil pattern repeated for
/// every credential variant in `KeychainServiceTests`. Pass save/load/delete
/// closures bound to the specific KeychainService API under test.
///
/// - Parameters:
///   - value: Value to round-trip. Must not be empty.
///   - save: Save closure (throwing).
///   - load: Load closure returning the persisted value or nil.
///   - delete: Delete closure.
///   - sourceLocation: Forwarded so Swift Testing reports the caller's line.
func assertKeychainRoundTrip(
    _ value: String,
    save: (String) throws -> Void,
    load: () -> String?,
    delete: () -> Void,
    sourceLocation: Testing.SourceLocation = #_sourceLocation
) throws {
    try save(value)
    #expect(load() == value, sourceLocation: sourceLocation)
    delete()
    #expect(load() == nil, sourceLocation: sourceLocation)
}
