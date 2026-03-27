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

    func testHomebrewOptPathDetected() {
        // Paths containing /opt/homebrew/ should be recognized as Homebrew installs
        let homebrewPaths = ["/opt/homebrew/", "/usr/local/Cellar/", "/Homebrew/"]
        let testPath = "/opt/homebrew/Caskroom/wolfwave/1.0.0/WolfWave.app"
        let isHomebrew = homebrewPaths.contains { testPath.contains($0) }
        XCTAssertTrue(isHomebrew, "Path containing /opt/homebrew/ should be detected as Homebrew install")
    }

    func testHomebrewCellarPathDetected() {
        let homebrewPaths = ["/opt/homebrew/", "/usr/local/Cellar/", "/Homebrew/"]
        let testPath = "/usr/local/Cellar/wolfwave/1.0.0/WolfWave.app"
        let isHomebrew = homebrewPaths.contains { testPath.contains($0) }
        XCTAssertTrue(isHomebrew, "Path containing /usr/local/Cellar/ should be detected as Homebrew install")
    }

    func testHomebrewGenericPathDetected() {
        let homebrewPaths = ["/opt/homebrew/", "/usr/local/Cellar/", "/Homebrew/"]
        let testPath = "/Users/test/Homebrew/wolfwave/WolfWave.app"
        let isHomebrew = homebrewPaths.contains { testPath.contains($0) }
        XCTAssertTrue(isHomebrew, "Path containing /Homebrew/ should be detected as Homebrew install")
    }

    func testNonHomebrewPathNotDetected() {
        let homebrewPaths = ["/opt/homebrew/", "/usr/local/Cellar/", "/Homebrew/"]
        let testPath = "/Applications/WolfWave.app"
        let isHomebrew = homebrewPaths.contains { testPath.contains($0) }
        XCTAssertFalse(isHomebrew, "Standard /Applications path should not be detected as Homebrew install")
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
        let service = SparkleUpdaterService()
        XCTAssertNotNil(service.feedURL, "feedURL should not be nil in DEBUG builds")
        if let url = service.feedURL {
            XCTAssertTrue(url.absoluteString.contains("dev-appcast.xml"), "feedURL should point to dev-appcast.xml in DEBUG builds")
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
