//
//  AppConstantsEdgeCaseTests.swift
//  WolfWaveTests
//
//  Created by MrDemonWolf, Inc. on 3/19/26.
//

import XCTest
@testable import WolfWave

final class AppConstantsEdgeCaseTests: XCTestCase {

    // MARK: - GitHub URL Resolution Tests

    func testRepoOwnerReturnsFallback() {
        // In test environment without Info.plist keys, should fall back to "mrdemonwolf"
        let owner = AppConstants.URLs.repoOwner
        XCTAssertFalse(owner.isEmpty)
        XCTAssertNotEqual(owner, "$(GITHUB_REPO_OWNER)")
    }

    func testRepoNameReturnsFallback() {
        let name = AppConstants.URLs.repoName
        XCTAssertFalse(name.isEmpty)
        XCTAssertNotEqual(name, "$(GITHUB_REPO_NAME)")
    }

    func testGitHubURLIsValidAndParseable() {
        let url = URL(string: AppConstants.URLs.github)
        XCTAssertNotNil(url)
        XCTAssertEqual(url?.scheme, "https")
        XCTAssertEqual(url?.host, "github.com")
    }

    func testGitHubReleasesAPIIsValidAndParseable() throws {
        let url = try XCTUnwrap(URL(string: AppConstants.URLs.githubReleasesAPI))
        XCTAssertEqual(url.scheme, "https")
        XCTAssertEqual(url.host, "api.github.com")
        XCTAssertTrue(url.path.contains("releases/latest"))
    }

    func testGitHubReleasesURLIsValidAndParseable() throws {
        let url = try XCTUnwrap(URL(string: AppConstants.URLs.githubReleases))
        XCTAssertTrue(url.path.contains("releases"))
    }

    // MARK: - Widget Themes & Layouts Tests

    func testWidgetThemesArrayIsNonEmpty() {
        XCTAssertFalse(AppConstants.Widget.themes.isEmpty)
    }

    func testWidgetThemesContainsDefault() {
        XCTAssertTrue(AppConstants.Widget.themes.contains("Default"))
    }

    func testWidgetLayoutsArrayIsNonEmpty() {
        XCTAssertFalse(AppConstants.Widget.layouts.isEmpty)
    }

    func testWidgetLayoutsContainsHorizontal() {
        XCTAssertTrue(AppConstants.Widget.layouts.contains("Horizontal"))
    }

    // MARK: - SettingsUI Dimensions Tests

    func testSettingsUIDimensionsMinLessThanIdealLessThanMax() {
        XCTAssertLessThan(AppConstants.SettingsUI.minWidth, AppConstants.SettingsUI.idealWidth)
        XCTAssertLessThan(AppConstants.SettingsUI.idealWidth, AppConstants.SettingsUI.maxWidth)
        XCTAssertLessThan(AppConstants.SettingsUI.minHeight, AppConstants.SettingsUI.idealHeight)
        XCTAssertLessThan(AppConstants.SettingsUI.idealHeight, AppConstants.SettingsUI.maxHeight)
    }

    // MARK: - Power Management Tests

    func testReducedIntervalsGreaterThanNormalCounterparts() {
        // Music: reduced 15s vs normal polling (implied ~5s)
        XCTAssertGreaterThan(AppConstants.PowerManagement.reducedMusicCheckInterval, 5.0)

        // Discord: reduced 60s vs normal 15s
        XCTAssertGreaterThan(
            AppConstants.PowerManagement.reducedDiscordPollInterval,
            AppConstants.Discord.availabilityPollInterval
        )

        // WebSocket progress: reduced 3s vs normal 1s
        XCTAssertGreaterThan(
            AppConstants.PowerManagement.reducedProgressBroadcastInterval,
            AppConstants.WebSocketServer.progressBroadcastInterval
        )
    }

    // MARK: - Twitch Constants Edge Cases

    func testMaxReconnectionAttemptsPositive() {
        XCTAssertGreaterThan(AppConstants.Twitch.maxReconnectionAttempts, 0)
    }

    func testMaxMessageRetriesPositive() {
        XCTAssertGreaterThan(AppConstants.Twitch.maxMessageRetries, 0)
    }

    // MARK: - Discord Constants Edge Cases

    func testReconnectBaseDelayLessThanMaxDelay() {
        XCTAssertLessThan(
            AppConstants.Discord.reconnectBaseDelay,
            AppConstants.Discord.reconnectMaxDelay
        )
    }

    func testDiscordIpcSocketSlotsPositive() {
        XCTAssertGreaterThan(AppConstants.Discord.ipcSocketSlots, 0)
    }
}
