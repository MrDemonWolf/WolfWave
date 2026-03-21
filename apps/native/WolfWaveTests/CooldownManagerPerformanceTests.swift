//
//  CooldownManagerPerformanceTests.swift
//  WolfWaveTests
//
//  Created by MrDemonWolf, Inc. on 3/19/26.
//

import XCTest
@testable import WolfWave

final class CooldownManagerPerformanceTests: XCTestCase {
    var manager: CooldownManager!

    override func setUp() {
        super.setUp()
        manager = CooldownManager()
    }

    override func tearDown() {
        manager = nil
        super.tearDown()
    }

    // MARK: - Performance Tests

    func testIsOnCooldownPerformance() {
        // Pre-populate some data
        for i in 0..<100 {
            manager.recordUse(trigger: "!trigger\(i)", userID: "user\(i)")
        }

        measure {
            for i in 0..<10_000 {
                _ = manager.isOnCooldown(
                    trigger: "!trigger\(i % 100)",
                    userID: "user\(i % 100)",
                    isModerator: false,
                    globalCooldown: 15.0,
                    userCooldown: 15.0
                )
            }
        }
    }

    func testRecordUsePerformance() {
        measure {
            for i in 0..<10_000 {
                manager.recordUse(trigger: "!trigger\(i % 100)", userID: "user\(i % 100)")
            }
        }
    }

    func testConcurrentReadWritePerformance() {
        // Pre-populate
        for i in 0..<50 {
            manager.recordUse(trigger: "!trigger\(i)", userID: "user\(i)")
        }

        measure {
            DispatchQueue.concurrentPerform(iterations: 1000) { i in
                if i % 2 == 0 {
                    _ = self.manager.isOnCooldown(
                        trigger: "!trigger\(i % 50)",
                        userID: "user\(i % 50)",
                        isModerator: false,
                        globalCooldown: 15.0,
                        userCooldown: 15.0
                    )
                } else {
                    self.manager.recordUse(trigger: "!trigger\(i % 50)", userID: "user\(i % 50)")
                }
            }
        }
    }

    func testUniqueTriggersLookupPerformance() {
        // Pre-populate with 100 unique triggers
        for i in 0..<100 {
            manager.recordUse(trigger: "!unique\(i)", userID: "user0")
        }

        measure {
            for i in 0..<100 {
                _ = manager.isOnCooldown(
                    trigger: "!unique\(i)",
                    userID: "user0",
                    isModerator: false,
                    globalCooldown: 15.0,
                    userCooldown: 15.0
                )
            }
        }
    }

    func testResetPerformance() {
        measure {
            // Populate
            for i in 0..<1000 {
                manager.recordUse(trigger: "!trigger\(i)", userID: "user\(i)")
            }
            // Reset
            manager.reset()
        }
    }
}
