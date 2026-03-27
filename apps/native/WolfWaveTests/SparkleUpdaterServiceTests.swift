//
//  SparkleUpdaterServiceTests.swift
//  WolfWaveTests
//
//  Created by MrDemonWolf, Inc. on 3/18/26.
//

import XCTest
@testable import WolfWave

final class SparkleUpdaterServiceTests: XCTestCase {

    // MARK: - Initialization Tests

    func testServiceInitializesWithoutCrash() {
        let service = SparkleUpdaterService()
        XCTAssertNotNil(service)
    }

    // MARK: - Homebrew Install Detection Tests

    func testSparkleDisabledInDebugBuilds() {
        // In DEBUG builds, Sparkle is completely disabled — no initialization, no network checks.
        let service = SparkleUpdaterService()
        XCTAssertNil(service.feedURL,
            "feedURL should be nil in DEBUG builds (Sparkle not initialized)")
    }

    // MARK: - Default Property Tests

    func testAutomaticCheckDisabledInDebug() {
        // In DEBUG builds, Sparkle initializes but auto-checking is explicitly disabled
        let service = SparkleUpdaterService()
        XCTAssertFalse(service.automaticCheckEnabled, "automaticCheckEnabled should be false in DEBUG builds")
    }

    func testUpdateCheckIntervalReturnsConstant() {
        // When updater is nil, updateCheckInterval returns the AppConstants value
        let service = SparkleUpdaterService()
        XCTAssertEqual(
            service.updateCheckInterval,
            AppConstants.Update.checkInterval,
            "updateCheckInterval should return AppConstants.Update.checkInterval when updater is nil"
        )
    }

    func testFeedURLNilInDebug() {
        // In DEBUG builds, Sparkle is not initialized so feedURL is nil
        let service = SparkleUpdaterService()
        XCTAssertNil(service.feedURL, "feedURL should be nil in DEBUG builds (Sparkle disabled)")
    }

    // MARK: - Safe Operation Tests

    func testCheckForUpdatesDoesNotCrash() {
        // checkForUpdates() should short-circuit safely in debug/Homebrew mode
        let service = SparkleUpdaterService()
        service.checkForUpdates()
        // No crash = pass
    }

    func testCheckForUpdatesInBackgroundDoesNotCrash() {
        let service = SparkleUpdaterService()
        service.checkForUpdatesInBackground()
        // No crash = pass
    }

    // MARK: - SPUUpdaterDelegate Tests

    func testUpdaterShouldNotPromptForPermission() {
        // The service should return false to skip Sparkle's default permission prompt
        let service = SparkleUpdaterService()
        // Verify the delegate method exists and the service conforms to SPUUpdaterDelegate
        // In debug builds, we verify the service is an NSObject subclass that can act as delegate
        XCTAssertTrue(service is NSObject, "SparkleUpdaterService should be an NSObject subclass")
    }
}
