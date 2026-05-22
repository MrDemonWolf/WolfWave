//
//  MenuStatusFormatterTests.swift
//  WolfWaveTests
//
//  Created by MrDemonWolf, Inc. on 5/22/26.
//

import XCTest
@testable import WolfWave

final class MenuStatusFormatterTests: XCTestCase {

    // MARK: - Sync Music

    func testMusicStatusTracking() {
        XCTAssertEqual(MenuStatusFormatter.musicStatus(trackingEnabled: true), "Tracking")
    }

    func testMusicStatusPaused() {
        XCTAssertEqual(MenuStatusFormatter.musicStatus(trackingEnabled: false), "Paused")
    }

    // MARK: - Twitch

    func testTwitchStatusConnectedWithChannel() {
        XCTAssertEqual(
            MenuStatusFormatter.twitchStatus(isConnected: true, channelName: "wolf"),
            "@wolf"
        )
    }

    func testTwitchStatusDisconnectedWithChannel() {
        XCTAssertEqual(
            MenuStatusFormatter.twitchStatus(isConnected: false, channelName: "wolf"),
            "Not connected"
        )
    }

    func testTwitchStatusNoChannelSaved() {
        XCTAssertEqual(
            MenuStatusFormatter.twitchStatus(isConnected: false, channelName: nil),
            "No channel set"
        )
        XCTAssertEqual(
            MenuStatusFormatter.twitchStatus(isConnected: false, channelName: ""),
            "No channel set"
        )
    }

    // MARK: - Discord

    func testDiscordStatusOff() {
        XCTAssertEqual(
            MenuStatusFormatter.discordStatus(enabled: false, state: .connected),
            "Off"
        )
    }

    func testDiscordStatusConnected() {
        XCTAssertEqual(
            MenuStatusFormatter.discordStatus(enabled: true, state: .connected),
            "Connected"
        )
    }

    func testDiscordStatusConnecting() {
        XCTAssertEqual(
            MenuStatusFormatter.discordStatus(enabled: true, state: .connecting),
            "Reconnecting\u{2026}"
        )
    }

    func testDiscordStatusDisconnected() {
        XCTAssertEqual(
            MenuStatusFormatter.discordStatus(enabled: true, state: .disconnected),
            "Disconnected"
        )
    }

    // MARK: - Stream Widgets

    func testWidgetsStatusOff() {
        XCTAssertEqual(
            MenuStatusFormatter.widgetsStatus(enabled: false, widgetPort: 8766, clientCount: 5),
            "Off"
        )
    }

    func testWidgetsStatusZeroViewers() {
        XCTAssertEqual(
            MenuStatusFormatter.widgetsStatus(enabled: true, widgetPort: 8766, clientCount: 0),
            ":8766 · 0 viewers"
        )
    }

    func testWidgetsStatusOneViewer() {
        XCTAssertEqual(
            MenuStatusFormatter.widgetsStatus(enabled: true, widgetPort: 8766, clientCount: 1),
            ":8766 · 1 viewer"
        )
    }

    func testWidgetsStatusManyViewers() {
        XCTAssertEqual(
            MenuStatusFormatter.widgetsStatus(enabled: true, widgetPort: 9000, clientCount: 42),
            ":9000 · 42 viewers"
        )
    }

    // MARK: - Song Request Collapse Threshold

    func testCollapseEmptyQueue() {
        XCTAssertFalse(MenuStatusFormatter.shouldCollapseSongRequests(queueCount: 0, hasNowPlaying: false))
    }

    func testCollapseOnlyNowPlaying() {
        XCTAssertFalse(MenuStatusFormatter.shouldCollapseSongRequests(queueCount: 0, hasNowPlaying: true))
    }

    func testCollapseSingleQueuedNoCurrent() {
        XCTAssertFalse(MenuStatusFormatter.shouldCollapseSongRequests(queueCount: 1, hasNowPlaying: false))
    }

    func testCollapseSingleQueuedPlusCurrent() {
        XCTAssertTrue(MenuStatusFormatter.shouldCollapseSongRequests(queueCount: 1, hasNowPlaying: true))
    }

    func testCollapseTwoOrMoreQueued() {
        XCTAssertTrue(MenuStatusFormatter.shouldCollapseSongRequests(queueCount: 2, hasNowPlaying: false))
        XCTAssertTrue(MenuStatusFormatter.shouldCollapseSongRequests(queueCount: 5, hasNowPlaying: true))
    }
}
