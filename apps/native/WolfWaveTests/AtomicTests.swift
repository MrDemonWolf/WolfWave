//
//  AtomicTests.swift
//  WolfWave
//
//  Created by Nathanial Henniges on 2026-06-06.
//  Copyright © 2026 MrDemonWolf, Inc. All rights reserved.
//

import XCTest
@testable import WolfWave

/// Exercises the production `Atomic` lock-guarded box in
/// `Core/ThreadSafeStorage.swift` directly.
///
/// Test files previously carried their own `Atomic`/`Box` lookalikes that
/// shadowed this type, so the real one shipped untested. Those copies were
/// renamed; this suite pins the production box's get/set contract and its
/// thread safety under concurrent writers and readers.
final class AtomicTests: XCTestCase {

    // MARK: - Basic get / set

    func testInitialValueIsReadable() {
        let box = Atomic(42)
        XCTAssertEqual(box.value, 42)
    }

    func testSetReplacesValue() {
        let box = Atomic("first")
        box.set("second")
        XCTAssertEqual(box.value, "second")
    }

    func testHoldsOptionalValue() {
        let box = Atomic<String?>(nil)
        XCTAssertNil(box.value)
        box.set("present")
        XCTAssertEqual(box.value, "present")
        box.set(nil)
        XCTAssertNil(box.value)
    }

    func testHoldsReferenceType() {
        let first = NSObject()
        let second = NSObject()
        let box = Atomic(first)
        XCTAssertTrue(box.value === first)
        box.set(second)
        XCTAssertTrue(box.value === second)
    }

    // MARK: - Concurrency

    /// Many concurrent writers each setting a distinct value: the final read must
    /// land on one of the written values (never a torn or default value), and the
    /// box must not crash or deadlock under contention.
    func testConcurrentSettersLeaveValidValue() async {
        let box = Atomic(-1)
        let iterations = 1_000

        await withTaskGroup(of: Void.self) { group in
            for i in 0..<iterations {
                group.addTask { box.set(i) }
            }
            await group.waitForAll()
        }

        let final = box.value
        XCTAssertTrue((0..<iterations).contains(final),
                      "Final value \(final) must be one of the concurrently written values")
    }

    /// Interleaved concurrent reads and writes must each observe a consistent
    /// value from the valid set, proving every access takes the lock. A failure
    /// here would surface as a crash, a hang, or a sanitizer data-race report.
    func testConcurrentReadersAndWritersAreConsistent() async {
        let valid = Set(0..<256)
        let box = Atomic(0)
        let observed = Atomic(Set<Int>())

        await withTaskGroup(of: Void.self) { group in
            for i in 0..<2_000 {
                group.addTask {
                    if i.isMultiple(of: 2) {
                        box.set(i % 256)
                    } else {
                        let snapshot = box.value
                        observed.set(observed.value.union([snapshot]))
                    }
                }
            }
            await group.waitForAll()
        }

        XCTAssertTrue(observed.value.isSubset(of: valid),
                      "Every observed value must come from the written set; saw \(observed.value.subtracting(valid))")
    }
}
