//
//  InMemoryKeychainBackend.swift
//  WolfWaveTests
//
//  Created by Nathanial Henniges on 2026-06-02.
//  Copyright © 2026 MrDemonWolf, Inc. All rights reserved.
//

import Foundation
@testable import WolfWave

/// In-memory `KeychainBackend` for unit tests.
///
/// Exercises `KeychainService`'s credential logic (account routing, overwrite,
/// delete semantics) without touching the real Keychain. The real Keychain
/// prompts for an ACL grant under ad-hoc test signing, which blocks cold reads
/// and fails CI — so the suite injects this instead.
///
/// Thread-safe so the concurrent-access stress test exercises real contention.
final class InMemoryKeychainBackend: KeychainBackend, @unchecked Sendable {
    private var store: [String: String] = [:]
    private let lock = NSLock()

    /// Stores `value` for `account`, overwriting any existing entry.
    func save(account: String, value: String) throws {
        lock.lock()
        defer { lock.unlock() }
        store[account] = value
    }

    /// Returns the stored string for `account`, or nil if absent.
    func load(account: String) -> String? {
        lock.lock()
        defer { lock.unlock() }
        return store[account]
    }

    /// Removes the entry for `account`. Succeeds silently if absent.
    func delete(account: String) {
        lock.lock()
        defer { lock.unlock() }
        store[account] = nil
    }
}
