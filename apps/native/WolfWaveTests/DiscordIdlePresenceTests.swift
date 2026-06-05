//
//  DiscordIdlePresenceTests.swift
//  WolfWave
//
//  Created by Nathanial Henniges on 2026-06-01.
//  Copyright © 2026 MrDemonWolf, Inc. All rights reserved.
//

import XCTest
@testable import WolfWave

/// Covers the opt-in idle activity payload and the preview card's mode helpers
/// that gate what renders when nothing is playing.
@MainActor
final class DiscordIdlePresenceTests: XCTestCase {

    // MARK: - buildIdleActivity

    func test_idleActivity_isListeningType() {
        let activity = DiscordRPCService.buildIdleActivity()
        XCTAssertEqual(activity["type"] as? Int, AppConstants.Discord.listeningActivityType)
    }

    func test_idleActivity_usesIdleCopy() {
        let activity = DiscordRPCService.buildIdleActivity()
        XCTAssertEqual(activity["details"] as? String, AppConstants.Discord.idleDetails)
        XCTAssertEqual(activity["state"] as? String, AppConstants.Discord.idleState)
    }

    func test_idleActivity_hasNoButtonsOrTimestamps() {
        let activity = DiscordRPCService.buildIdleActivity()
        // Idle is a static marker. No clickable buttons and no live ticker.
        XCTAssertNil(activity["buttons"])
        XCTAssertNil(activity["timestamps"])
    }

    func test_idleActivity_usesWolfWaveLogoWithAppleMusicBadge() {
        let activity = DiscordRPCService.buildIdleActivity()
        let assets = activity["assets"] as? [String: String]
        // Idle: WolfWave logo as the large image, Apple Music demoted to the
        // small source badge, so idle reads distinctly from active playback.
        XCTAssertEqual(assets?["large_image"], "wolfwave")
        XCTAssertEqual(assets?["large_text"], "WolfWave")
        XCTAssertEqual(assets?["small_image"], "apple_music")
        XCTAssertEqual(assets?["small_text"], "Apple Music")
    }

    // MARK: - Mode helpers

    func test_mode_showsTrack_onlyForPlayingAndPaused() {
        XCTAssertTrue(DiscordPreviewCard.Mode.playing.showsTrack)
        XCTAssertTrue(DiscordPreviewCard.Mode.paused.showsTrack)
        XCTAssertFalse(DiscordPreviewCard.Mode.stopped.showsTrack)
        XCTAssertFalse(DiscordPreviewCard.Mode.musicClosed.showsTrack)
        XCTAssertFalse(DiscordPreviewCard.Mode.discordOffline.showsTrack)
        XCTAssertFalse(DiscordPreviewCard.Mode.idleActivity.showsTrack)
    }

    func test_mode_showsListeningHeader_forActivityModes() {
        // "Listening to WolfWave" only when an activity is actually on the
        // profile: playing, paused, or the opt-in idle marker.
        XCTAssertTrue(DiscordPreviewCard.Mode.playing.showsListeningHeader)
        XCTAssertTrue(DiscordPreviewCard.Mode.paused.showsListeningHeader)
        XCTAssertTrue(DiscordPreviewCard.Mode.idleActivity.showsListeningHeader)
        XCTAssertFalse(DiscordPreviewCard.Mode.stopped.showsListeningHeader)
        XCTAssertFalse(DiscordPreviewCard.Mode.musicClosed.showsListeningHeader)
        XCTAssertFalse(DiscordPreviewCard.Mode.discordOffline.showsListeningHeader)
    }
}
