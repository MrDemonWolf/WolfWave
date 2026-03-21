//
//  BotCommandDispatcherPerformanceTests.swift
//  WolfWaveTests
//
//  Created by MrDemonWolf, Inc. on 3/19/26.
//

import XCTest
@testable import WolfWave

final class BotCommandDispatcherPerformanceTests: XCTestCase {

    override func setUp() {
        super.setUp()
        // Use zero cooldowns so performance tests aren't blocked
        let defaults = UserDefaults.standard
        defaults.set(0.0, forKey: AppConstants.UserDefaults.songCommandGlobalCooldown)
        defaults.set(0.0, forKey: AppConstants.UserDefaults.songCommandUserCooldown)
        defaults.set(0.0, forKey: AppConstants.UserDefaults.lastSongCommandGlobalCooldown)
        defaults.set(0.0, forKey: AppConstants.UserDefaults.lastSongCommandUserCooldown)
    }

    override func tearDown() {
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: AppConstants.UserDefaults.songCommandGlobalCooldown)
        defaults.removeObject(forKey: AppConstants.UserDefaults.songCommandUserCooldown)
        defaults.removeObject(forKey: AppConstants.UserDefaults.lastSongCommandGlobalCooldown)
        defaults.removeObject(forKey: AppConstants.UserDefaults.lastSongCommandUserCooldown)
        super.tearDown()
    }

    // MARK: - Performance Tests

    func testProcessMessagePerformance() {
        let dispatcher = BotCommandDispatcher()
        dispatcher.setCurrentSongInfo { "Artist - Song" }

        measure {
            for i in 0..<1000 {
                _ = dispatcher.processMessage("!song", userID: "user\(i)")
            }
        }
    }

    func testNonCommandShortCircuitPerformance() {
        let dispatcher = BotCommandDispatcher()
        dispatcher.setCurrentSongInfo { "Artist - Song" }

        measure {
            for _ in 0..<1000 {
                _ = dispatcher.processMessage("just a regular chat message")
            }
        }
    }

    func testOverLengthMessageRejectionPerformance() {
        let dispatcher = BotCommandDispatcher()
        dispatcher.setCurrentSongInfo { "Artist - Song" }
        let longMessage = String(repeating: "a", count: 501)

        measure {
            for _ in 0..<1000 {
                _ = dispatcher.processMessage(longMessage)
            }
        }
    }
}
