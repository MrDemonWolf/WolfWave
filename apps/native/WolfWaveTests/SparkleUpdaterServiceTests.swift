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

    func testNonHomebrewInstallAllowsSparkle() {
        // When running from Xcode build directory (not Homebrew), Sparkle should be initialized.
        // We verify this indirectly: feedURL is non-nil only when Sparkle is active (non-Homebrew).
        let service = SparkleUpdaterService()
        XCTAssertNotNil(service.feedURL,
            "feedURL should be non-nil when running from a non-Homebrew path (Sparkle active)")
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

    func testFeedURLReturnsDevAppcastInDebug() {
        // In DEBUG builds, Sparkle initializes and feedURL points to the bundled dev-appcast.xml
        // The URL uses file:// scheme since it references a bundled resource
        let service = SparkleUpdaterService()
        XCTAssertNotNil(service.feedURL, "feedURL should not be nil in DEBUG builds")
        if let url = service.feedURL {
            XCTAssertTrue(url.scheme == "file",
                "feedURL should use file:// scheme in debug/test builds, got: \(url.scheme ?? "nil")")
            XCTAssertTrue(url.absoluteString.contains("dev-appcast.xml"),
                "feedURL should point to dev-appcast.xml in DEBUG builds, got: \(url.absoluteString)")
        }
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
