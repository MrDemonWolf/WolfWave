//
//  AppConstantsTests.swift
//  WolfWaveTests
//
//  Created by Claude on 2/13/26.
//

import XCTest
@testable import WolfWave

final class AppConstantsTests: XCTestCase {

    // MARK: - App Info

    func testBundleIdentifier() {
        XCTAssertEqual(AppConstants.AppInfo.bundleIdentifier, "com.mrdemonwolf.wolfwave")
    }

    func testDisplayName() {
        XCTAssertEqual(AppConstants.AppInfo.displayName, "WolfWave")
    }

    // MARK: - Keychain

    func testKeychainServiceMatchesBundleID() {
        XCTAssertEqual(AppConstants.Keychain.service, AppConstants.AppInfo.bundleIdentifier)
    }

    // MARK: - Dock Visibility

    func testDockVisibilityDefaultIsBoth() {
        XCTAssertEqual(AppConstants.DockVisibility.default, "both")
    }

    func testDockVisibilityModesAreDifferent() {
        XCTAssertNotEqual(AppConstants.DockVisibility.menuOnly, AppConstants.DockVisibility.dockOnly)
        XCTAssertNotEqual(AppConstants.DockVisibility.menuOnly, AppConstants.DockVisibility.both)
        XCTAssertNotEqual(AppConstants.DockVisibility.dockOnly, AppConstants.DockVisibility.both)
    }

    // MARK: - Update Constants

    func testUpdateCheckIntervalIs24Hours() {
        XCTAssertEqual(AppConstants.Update.checkInterval, 86400)
    }

    func testUpdateRequestTimeout() {
        XCTAssertEqual(AppConstants.Update.requestTimeout, 15.0)
    }

    func testUpdateLaunchCheckDelay() {
        XCTAssertEqual(AppConstants.Update.launchCheckDelay, 10.0)
    }

    // MARK: - URL Validity

    func testGitHubReleasesAPIURLContainsAPIDomain() {
        XCTAssertTrue(AppConstants.URLs.githubReleasesAPI.contains("api.github.com"))
    }

    func testGitHubReleasesURLContainsGitHub() {
        XCTAssertTrue(AppConstants.URLs.githubReleases.contains("github.com"))
    }

    func testAllURLsAreValid() {
        let urls = [
            AppConstants.URLs.docs,
            AppConstants.URLs.privacyPolicy,
            AppConstants.URLs.termsOfService,
            AppConstants.URLs.github,
            AppConstants.URLs.githubReleasesAPI,
            AppConstants.URLs.githubReleases,
        ]
        for urlString in urls {
            XCTAssertNotNil(URL(string: urlString), "Invalid URL: \(urlString)")
        }
    }

    // MARK: - Onboarding UI

    func testOnboardingWindowWidthPositive() {
        XCTAssertGreaterThan(AppConstants.OnboardingUI.windowWidth, 0)
    }

    func testOnboardingWindowHeightPositive() {
        XCTAssertGreaterThan(AppConstants.OnboardingUI.windowHeight, 0)
    }

    // MARK: - Settings UI

    func testSettingsMinDimensionsPositive() {
        XCTAssertGreaterThan(AppConstants.SettingsUI.minWidth, 0)
        XCTAssertGreaterThan(AppConstants.SettingsUI.minHeight, 0)
    }

    func testSettingsIdealWithinBounds() {
        XCTAssertGreaterThanOrEqual(AppConstants.SettingsUI.idealWidth, AppConstants.SettingsUI.minWidth)
        XCTAssertLessThanOrEqual(AppConstants.SettingsUI.idealWidth, AppConstants.SettingsUI.maxWidth)
        XCTAssertGreaterThanOrEqual(AppConstants.SettingsUI.idealHeight, AppConstants.SettingsUI.minHeight)
        XCTAssertLessThanOrEqual(AppConstants.SettingsUI.idealHeight, AppConstants.SettingsUI.maxHeight)
    }

    // MARK: - Twitch Constants

    func testTwitchAPIBaseURL() {
        XCTAssertTrue(AppConstants.Twitch.apiBaseURL.contains("api.twitch.tv"))
    }

    // MARK: - Discord Constants

    func testDiscordIPCSocketSlots() {
        XCTAssertEqual(AppConstants.Discord.ipcSocketSlots, 10)
    }

    func testDiscordReconnectDelays() {
        XCTAssertGreaterThan(AppConstants.Discord.reconnectBaseDelay, 0)
        XCTAssertGreaterThan(AppConstants.Discord.reconnectMaxDelay, AppConstants.Discord.reconnectBaseDelay)
    }
}
