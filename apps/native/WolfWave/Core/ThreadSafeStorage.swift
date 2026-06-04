//
//  ThreadSafeStorage.swift
//  WolfWave
//
//  Created by Nathanial Henniges on 2026-06-03.
//  Copyright © 2026 MrDemonWolf, Inc. All rights reserved.
//

import Foundation

/// A lock-guarded box around a single value, safe to read and write from any
/// thread.
///
/// Use it for the small "mirror" values that an actor needs to expose to a
/// synchronous, nonisolated caller that cannot `await` back into the actor.
/// `DiscordRPCService.stateSnapshot` and the Twitch dispatcher's connection /
/// live-stream flags are the canonical cases: short-lived snapshots that the
/// sync command bridge reads without re-entering the actor.
///
/// Prefer an `actor` for anything richer than a single value. This is the
/// `@unchecked Sendable` + `NSLock` escape hatch for the bridge seams where an
/// actor hop is not possible, replacing the near-identical hand-rolled lock
/// wrappers those seams used to carry.
nonisolated final class Atomic<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var _value: Value

    /// Creates a box seeded with `value`.
    init(_ value: Value) {
        _value = value
    }

    /// The current value. Each read takes the lock.
    var value: Value {
        lock.withLock { _value }
    }

    /// Atomically replaces the stored value.
    func set(_ newValue: Value) {
        lock.withLock { _value = newValue }
    }
}
