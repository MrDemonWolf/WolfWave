//
//  SparkleUpdaterServiceTests.swift
//  WolfWaveTests
//
//  Created by MrDemonWolf, Inc. on 3/18/26.
//

import XCTest
@testable import WolfWave

@MainActor
final class SparkleUpdaterServiceTests: XCTestCase {

    // MARK: - Initialization Tests

    func testServiceInitializesWithoutCrash() {
        let service = SparkleUpdaterService()
        XCTAssertNotNil(service)
    }

    // MARK: - Feed URL Tests

    func testFeedURLPointsAtBundledDevAppcastInDebug() {
        // DEBUG builds route Sparkle at the bundled dev-appcast.xml so manual
        // "Check for Updates" exercises the real Sparkle UI against a dummy entry.
        let service = SparkleUpdaterService()
        let url = service.feedURL
        XCTAssertNotNil(url, "feedURL should point at the bundled dev-appcast.xml in DEBUG builds")
        XCTAssertEqual(url?.lastPathComponent, "dev-appcast.xml")
    }

    // MARK: - Default Property Tests

    func testAutomaticCheckDefaultsToTrueWhenUpdaterNil() {
        // The getter falls back to true when the underlying updater is unset.
        let service = SparkleUpdaterService()
        XCTAssertTrue(service.automaticCheckEnabled, "automaticCheckEnabled getter should default to true when updater is nil")
    }

    func testUpdateCheckIntervalReturnsConstantWhenUpdaterNil() {
        let service = SparkleUpdaterService()
        XCTAssertEqual(
            service.updateCheckInterval,
            AppConstants.Update.checkInterval,
            "updateCheckInterval should return AppConstants.Update.checkInterval when updater is nil"
        )
    }

    // MARK: - Safe Operation Tests

    func testCheckForUpdatesDoesNotCrash() {
        let service = SparkleUpdaterService()
        _ = service.checkForUpdates()
    }

    func testCheckForUpdatesInBackgroundDoesNotCrash() {
        let service = SparkleUpdaterService()
        service.checkForUpdatesInBackground()
    }

    // MARK: - Availability Signal Tests

    func testIsAvailableReflectsUpdaterAndHomebrewState() {
        // In a unit-test host bundle Sparkle's `SPUStandardUpdaterController`
        // typically does not produce an `SPUUpdater` (no main bundle Info.plist
        // appcast wiring), so `isAvailable` should be false. Either way, the
        // boolean must agree with the `checkForUpdates()` return so callers
        // can rely on a single signal to decide whether to open the fallback.
        let service = SparkleUpdaterService()
        XCTAssertEqual(
            service.isAvailable,
            service.checkForUpdates(),
            "isAvailable and checkForUpdates() must agree on whether Sparkle handled the call"
        )
    }

    // MARK: - SPUUpdaterDelegate Tests

    func testServiceIsNSObjectForDelegateConformance() {
        let service = SparkleUpdaterService()
        XCTAssertTrue(service is NSObject, "SparkleUpdaterService should be an NSObject subclass to satisfy SPUUpdaterDelegate")
    }
}
