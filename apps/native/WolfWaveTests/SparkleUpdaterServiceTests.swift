//
//  SparkleUpdaterServiceTests.swift
//  WolfWave
//
//  Created by Nathanial Henniges on 2026-03-19.
//  Copyright © 2026 MrDemonWolf, Inc. All rights reserved.
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

    // MARK: - Feed Resolver Tests (channel selection)

    private let nightlyURL = "https://example.com/appcast-nightly.xml"
    private let devURL = "file:///tmp/dev-appcast.xml"

    func testResolverDebugAlwaysUsesDevAppcastRegardlessOfChannel() {
        // DEBUG builds must always exercise the bundled dev appcast, even if the
        // stored channel is Nightly. The DEBUG branch wins.
        for channel in UpdateChannel.allCases {
            let resolved = SparkleUpdaterService.resolveFeedURLString(
                channel: channel,
                isDebug: true,
                nightlyURL: nightlyURL,
                devAppcastURL: devURL
            )
            XCTAssertEqual(resolved, devURL, "DEBUG should use dev appcast for channel \(channel.rawValue)")
        }
    }

    func testResolverReleaseNightlyUsesNightlyFeed() {
        let resolved = SparkleUpdaterService.resolveFeedURLString(
            channel: .nightly,
            isDebug: false,
            nightlyURL: nightlyURL,
            devAppcastURL: devURL
        )
        XCTAssertEqual(resolved, nightlyURL)
    }

    func testResolverReleaseStableFallsBackToInfoPlistFeed() {
        // nil signals Sparkle to use SUFeedURL from Info.plist.
        let resolved = SparkleUpdaterService.resolveFeedURLString(
            channel: .stable,
            isDebug: false,
            nightlyURL: nightlyURL,
            devAppcastURL: devURL
        )
        XCTAssertNil(resolved)
    }

    // MARK: - Channel Persistence Tests

    func testChannelDefaultsToStable() {
        UserDefaults.standard.removeObject(forKey: AppConstants.UserDefaults.updateChannel)
        let service = SparkleUpdaterService()
        XCTAssertEqual(service.channel, .stable)
    }

    func testChannelPersistsRawValue() {
        let service = SparkleUpdaterService()
        defer { UserDefaults.standard.removeObject(forKey: AppConstants.UserDefaults.updateChannel) }

        service.channel = .nightly
        XCTAssertEqual(
            UserDefaults.standard.string(forKey: AppConstants.UserDefaults.updateChannel),
            UpdateChannel.nightly.rawValue
        )
        XCTAssertEqual(service.channel, .nightly)

        service.channel = .stable
        XCTAssertEqual(service.channel, .stable)
    }
}
