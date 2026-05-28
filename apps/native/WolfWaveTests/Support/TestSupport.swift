//
//  TestSupport.swift
//  WolfWaveTests
//
//  Copyright © 2026 MrDemonWolf, Inc. All rights reserved.
//
//  Free helpers used by both XCTest and Swift Testing suites.
//

import Foundation
import Testing

/// Creates a fresh, unique temp directory and ensures it exists. Returns the URL.
///
/// Swift Testing suites don't have tearDown — callers are responsible for cleanup
/// (or rely on the OS reclaiming `tmp`). Prefer `WolfWaveTestCase.makeTempDir()`
/// for XCTest-based suites, which auto-cleans on tearDown.
func makeIsolatedTempDirectory(prefix: String = "wolfwave-test") -> URL {
    let dir = FileManager.default
        .temporaryDirectory
        .appendingPathComponent("\(prefix)-\(UUID().uuidString)", isDirectory: true)
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir
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
