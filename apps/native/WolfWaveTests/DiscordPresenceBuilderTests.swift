//
//  DiscordPresenceBuilderTests.swift
//  WolfWave
//
//  Created by Nathanial Henniges on 2026-05-16.
//  Copyright © 2026 MrDemonWolf, Inc. All rights reserved.
//

import XCTest
@testable import WolfWave

/// Tests the pure payload-building helpers in `DiscordRPCService`.
///
/// Uses an isolated `UserDefaults(suiteName:)` per test so settings can't leak
/// between tests or pollute the user's real defaults.
@MainActor
final class DiscordPresenceBuilderTests: XCTestCase {

    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        suiteName = "DiscordPresenceBuilderTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    // MARK: - resolveButton

    func test_resolveButton_omitted_whenURLNil() {
        let result = DiscordRPCService.resolveButton(index: 1, url: nil, defaults: defaults)
        XCTAssertNil(result)
    }

    func test_resolveButton_omitted_whenURLEmpty() {
        let result = DiscordRPCService.resolveButton(index: 1, url: "", defaults: defaults)
        XCTAssertNil(result)
    }

    func test_resolveButton_omitted_whenDisabled() {
        defaults.set(false, forKey: AppConstants.UserDefaults.discordButton1Enabled)
        let result = DiscordRPCService.resolveButton(
            index: 1, url: "https://example.com/song", defaults: defaults
        )
        XCTAssertNil(result)
    }

    func test_resolveButton_defaultLabel_whenStoredEmpty() {
        let result = DiscordRPCService.resolveButton(
            index: 1, url: "https://music.apple.com/x", defaults: defaults
        )
        XCTAssertEqual(result?["label"], AppConstants.Discord.defaultButton1Label)
        XCTAssertEqual(result?["url"], "https://music.apple.com/x")
    }

    func test_resolveButton_defaultLabel_forButton2() {
        let result = DiscordRPCService.resolveButton(
            index: 2, url: "https://song.link/i/1", defaults: defaults
        )
        XCTAssertEqual(result?["label"], AppConstants.Discord.defaultButton2Label)
    }

    func test_resolveButton_customLabelOverridesDefault() {
        defaults.set("Vibes 🎧", forKey: AppConstants.UserDefaults.discordButton1Label)
        let result = DiscordRPCService.resolveButton(
            index: 1, url: "https://music.apple.com/x", defaults: defaults
        )
        XCTAssertEqual(result?["label"], "Vibes 🎧")
    }

    func test_resolveButton_truncatesLabelTo32Chars() {
        let long = String(repeating: "A", count: 50)
        defaults.set(long, forKey: AppConstants.UserDefaults.discordButton1Label)
        let result = DiscordRPCService.resolveButton(
            index: 1, url: "https://x", defaults: defaults
        )
        XCTAssertEqual(result?["label"]?.count, AppConstants.Discord.buttonLabelMaxLength)
    }

    func test_resolveButton_trimsWhitespace() {
        defaults.set("   Hello   ", forKey: AppConstants.UserDefaults.discordButton1Label)
        let result = DiscordRPCService.resolveButton(
            index: 1, url: "https://x", defaults: defaults
        )
        XCTAssertEqual(result?["label"], "Hello")
    }

    func test_resolveButton_whitespaceOnlyFallsBackToDefault() {
        defaults.set("     ", forKey: AppConstants.UserDefaults.discordButton1Label)
        let result = DiscordRPCService.resolveButton(
            index: 1, url: "https://x", defaults: defaults
        )
        XCTAssertEqual(result?["label"], AppConstants.Discord.defaultButton1Label)
    }

    func test_resolveButton_invalidIndexReturnsNil() {
        let result = DiscordRPCService.resolveButton(
            index: 5, url: "https://x", defaults: defaults
        )
        XCTAssertNil(result)
    }

    // MARK: - buildActivity

    func test_buildActivity_stateIsArtistWithoutByPrefix() {
        let activity = DiscordRPCService.buildActivity(
            track: "Smooth Operator",
            artist: "Sade",
            album: "Diamond Life",
            artworkURL: nil,
            duration: 0,
            elapsed: 0,
            appleMusicURL: nil,
            songLinkURL: nil,
            defaults: defaults,
            now: Date()
        )
        XCTAssertEqual(activity["state"] as? String, "Sade")
        XCTAssertEqual(activity["details"] as? String, "Smooth Operator")
    }

    func test_buildActivity_typeIsListening() {
        let activity = DiscordRPCService.buildActivity(
            track: "T", artist: "A", album: "Al",
            artworkURL: nil, duration: 0, elapsed: 0,
            appleMusicURL: nil, songLinkURL: nil,
            defaults: defaults, now: Date()
        )
        XCTAssertEqual(activity["type"] as? Int, AppConstants.Discord.listeningActivityType)
    }

    func test_buildActivity_omitsButtonsKey_whenBothDisabled() {
        defaults.set(false, forKey: AppConstants.UserDefaults.discordButton1Enabled)
        defaults.set(false, forKey: AppConstants.UserDefaults.discordButton2Enabled)
        let activity = DiscordRPCService.buildActivity(
            track: "T", artist: "A", album: "Al",
            artworkURL: nil, duration: 0, elapsed: 0,
            appleMusicURL: "https://music.apple.com/x",
            songLinkURL: "https://song.link/i/1",
            defaults: defaults, now: Date()
        )
        XCTAssertNil(activity["buttons"])
    }

    func test_buildActivity_includesBothButtons_whenURLsAndEnabled() {
        let activity = DiscordRPCService.buildActivity(
            track: "T", artist: "A", album: "Al",
            artworkURL: nil, duration: 0, elapsed: 0,
            appleMusicURL: "https://music.apple.com/x",
            songLinkURL: "https://song.link/i/1",
            defaults: defaults, now: Date()
        )
        let buttons = activity["buttons"] as? [[String: String]]
        XCTAssertEqual(buttons?.count, 2)
        XCTAssertEqual(buttons?[0]["label"], AppConstants.Discord.defaultButton1Label)
        XCTAssertEqual(buttons?[1]["label"], AppConstants.Discord.defaultButton2Label)
    }

    func test_buildActivity_skipsButton_whenURLMissing() {
        let activity = DiscordRPCService.buildActivity(
            track: "T", artist: "A", album: "Al",
            artworkURL: nil, duration: 0, elapsed: 0,
            appleMusicURL: "https://music.apple.com/x",
            songLinkURL: nil,
            defaults: defaults, now: Date()
        )
        let buttons = activity["buttons"] as? [[String: String]]
        XCTAssertEqual(buttons?.count, 1)
        XCTAssertEqual(buttons?[0]["url"], "https://music.apple.com/x")
    }

    func test_buildActivity_timestampsOmittedWhenDurationZero() {
        let activity = DiscordRPCService.buildActivity(
            track: "T", artist: "A", album: "Al",
            artworkURL: nil, duration: 0, elapsed: 0,
            appleMusicURL: nil, songLinkURL: nil,
            defaults: defaults, now: Date()
        )
        XCTAssertNil(activity["timestamps"])
    }

    func test_buildActivity_timestampsIncludedWhenDurationKnown() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let activity = DiscordRPCService.buildActivity(
            track: "T", artist: "A", album: "Al",
            artworkURL: nil, duration: 180, elapsed: 30,
            appleMusicURL: nil, songLinkURL: nil,
            defaults: defaults, now: now
        )
        let stamps = activity["timestamps"] as? [String: Int]
        // start = now - elapsed = 1_700_000_000 - 30 = 1_699_999_970, in ms.
        XCTAssertEqual(stamps?["start"], 1_699_999_970_000)
        // end = start + duration = 1_700_000_150 in ms.
        XCTAssertEqual(stamps?["end"], 1_700_000_150_000)
    }

    // MARK: - buildActivity + paused state

    func test_buildActivity_paused_omitsTimestamps() {
        let activity = DiscordRPCService.buildActivity(
            track: "T", artist: "A", album: "Al",
            artworkURL: nil, duration: 180, elapsed: 30,
            appleMusicURL: nil, songLinkURL: nil,
            isPaused: true,
            defaults: defaults, now: Date()
        )
        // Discord has no paused flag. We stop the live ticker by dropping
        // `timestamps` entirely while paused.
        XCTAssertNil(activity["timestamps"])
    }

    func test_buildActivity_paused_swapsSmallImageAndTooltip() {
        let activity = DiscordRPCService.buildActivity(
            track: "T", artist: "A", album: "Al",
            artworkURL: nil, duration: 180, elapsed: 30,
            appleMusicURL: nil, songLinkURL: nil,
            isPaused: true,
            defaults: defaults, now: Date()
        )
        let assets = activity["assets"] as? [String: String]
        XCTAssertEqual(assets?["small_image"], "pause")
        XCTAssertEqual(assets?["small_text"], "Paused")
        // Album art / large image untouched.
        XCTAssertEqual(assets?["large_image"], "apple_music")
    }

    func test_buildActivity_playing_keepsTimestamps() {
        let activity = DiscordRPCService.buildActivity(
            track: "T", artist: "A", album: "Al",
            artworkURL: nil, duration: 180, elapsed: 30,
            appleMusicURL: nil, songLinkURL: nil,
            isPaused: false,
            defaults: defaults, now: Date()
        )
        XCTAssertNotNil(activity["timestamps"])
        let assets = activity["assets"] as? [String: String]
        XCTAssertEqual(assets?["small_image"], "apple_music")
    }

    func test_buildActivity_assetsAlwaysIncludeFallbackImage() {
        let activity = DiscordRPCService.buildActivity(
            track: "T", artist: "A", album: "Album Name",
            artworkURL: nil, duration: 0, elapsed: 0,
            appleMusicURL: nil, songLinkURL: nil,
            defaults: defaults, now: Date()
        )
        let assets = activity["assets"] as? [String: String]
        XCTAssertEqual(assets?["large_image"], "apple_music")
        XCTAssertEqual(assets?["large_text"], "Album Name")
        XCTAssertEqual(assets?["small_image"], "apple_music")
        XCTAssertEqual(assets?["small_text"], "Apple Music")
    }

    func test_buildActivity_assetsPreferArtworkURL() {
        let activity = DiscordRPCService.buildActivity(
            track: "T", artist: "A", album: "Al",
            artworkURL: "https://example.com/art.jpg",
            duration: 0, elapsed: 0,
            appleMusicURL: nil, songLinkURL: nil,
            defaults: defaults, now: Date()
        )
        let assets = activity["assets"] as? [String: String]
        XCTAssertEqual(assets?["large_image"], "https://example.com/art.jpg")
    }

    // MARK: - resolvePlaylistDisplay

    /// Enables the playlist feature on the isolated suite with the given options.
    private func enablePlaylist(showName: Bool = true, style: DiscordPlaylistStyle = .artistLine) {
        defaults.set(true, forKey: AppConstants.UserDefaults.discordPlaylistEnabled)
        defaults.set(showName, forKey: AppConstants.UserDefaults.discordPlaylistShowName)
        defaults.set(style.rawValue, forKey: AppConstants.UserDefaults.discordPlaylistStyle)
    }

    func test_resolvePlaylistDisplay_nil_whenFeatureDisabled() {
        let result = DiscordRPCService.resolvePlaylistDisplay(
            playlist: "Chill Saturday", album: "Diamond Life", defaults: defaults
        )
        XCTAssertNil(result)
    }

    func test_resolvePlaylistDisplay_nil_whenEmpty() {
        defaults.set(true, forKey: AppConstants.UserDefaults.discordPlaylistEnabled)
        let result = DiscordRPCService.resolvePlaylistDisplay(
            playlist: "   ", album: "Al", defaults: defaults
        )
        XCTAssertNil(result)
    }

    func test_resolvePlaylistDisplay_nil_whenGenericName() {
        defaults.set(true, forKey: AppConstants.UserDefaults.discordPlaylistEnabled)
        for generic in ["Library", "music", "Apple Music"] {
            let result = DiscordRPCService.resolvePlaylistDisplay(
                playlist: generic, album: "Al", defaults: defaults
            )
            XCTAssertNil(result, "\(generic) should be treated as a generic container")
        }
    }

    func test_resolvePlaylistDisplay_nil_whenEqualsAlbum() {
        defaults.set(true, forKey: AppConstants.UserDefaults.discordPlaylistEnabled)
        let result = DiscordRPCService.resolvePlaylistDisplay(
            playlist: "diamond life", album: "Diamond Life", defaults: defaults
        )
        XCTAssertNil(result, "Playlist matching the album name should be hidden")
    }

    func test_resolvePlaylistDisplay_named_whenEnabledAndShowNameOn() {
        defaults.set(true, forKey: AppConstants.UserDefaults.discordPlaylistEnabled)
        let result = DiscordRPCService.resolvePlaylistDisplay(
            playlist: "  Chill Saturday  ", album: "Al", defaults: defaults
        )
        XCTAssertEqual(result, .named("Chill Saturday"))
    }

    func test_resolvePlaylistDisplay_anonymous_whenShowNameOff() {
        defaults.set(true, forKey: AppConstants.UserDefaults.discordPlaylistEnabled)
        defaults.set(false, forKey: AppConstants.UserDefaults.discordPlaylistShowName)
        let result = DiscordRPCService.resolvePlaylistDisplay(
            playlist: "Chill Saturday", album: "Al", defaults: defaults
        )
        XCTAssertEqual(result, .anonymous)
    }

    // MARK: - buildActivity + playlist

    func test_buildActivity_styleArtistLine_appendsPlaylistToState() {
        enablePlaylist()
        let activity = DiscordRPCService.buildActivity(
            track: "Smooth Operator", artist: "Sade", album: "Diamond Life",
            playlist: "Chill Saturday",
            artworkURL: nil, duration: 0, elapsed: 0,
            appleMusicURL: nil, songLinkURL: nil,
            defaults: defaults, now: Date()
        )
        XCTAssertEqual(activity["state"] as? String, "Sade · Chill Saturday")
        let assets = activity["assets"] as? [String: String]
        XCTAssertEqual(assets?["small_text"], "Apple Music")
    }

    func test_buildActivity_styleArtistLine_genericLabelWhenNameHidden() {
        enablePlaylist(showName: false)
        let activity = DiscordRPCService.buildActivity(
            track: "T", artist: "Sade", album: "Al",
            playlist: "Chill Saturday",
            artworkURL: nil, duration: 0, elapsed: 0,
            appleMusicURL: nil, songLinkURL: nil,
            defaults: defaults, now: Date()
        )
        XCTAssertEqual(activity["state"] as? String, "Sade · From a playlist")
    }

    func test_buildActivity_styleIconTooltip_setsSmallText() {
        enablePlaylist(style: .iconTooltip)
        let activity = DiscordRPCService.buildActivity(
            track: "T", artist: "Sade", album: "Al",
            playlist: "Chill Saturday",
            artworkURL: nil, duration: 0, elapsed: 0,
            appleMusicURL: nil, songLinkURL: nil,
            defaults: defaults, now: Date()
        )
        XCTAssertEqual(activity["state"] as? String, "Sade", "icon-tooltip style leaves the state line untouched")
        let assets = activity["assets"] as? [String: String]
        XCTAssertEqual(assets?["small_text"], "Playlist · Chill Saturday")
    }

    func test_buildActivity_styleIconTooltip_genericTooltipWhenNameHidden() {
        enablePlaylist(showName: false, style: .iconTooltip)
        let activity = DiscordRPCService.buildActivity(
            track: "T", artist: "Sade", album: "Al",
            playlist: "Chill Saturday",
            artworkURL: nil, duration: 0, elapsed: 0,
            appleMusicURL: nil, songLinkURL: nil,
            defaults: defaults, now: Date()
        )
        let assets = activity["assets"] as? [String: String]
        XCTAssertEqual(assets?["small_text"], "Playing from a playlist")
    }

    func test_buildActivity_noPlaylist_whenFeatureDisabled() {
        let activity = DiscordRPCService.buildActivity(
            track: "T", artist: "Sade", album: "Al",
            playlist: "Chill Saturday",
            artworkURL: nil, duration: 0, elapsed: 0,
            appleMusicURL: nil, songLinkURL: nil,
            defaults: defaults, now: Date()
        )
        XCTAssertEqual(activity["state"] as? String, "Sade")
        let assets = activity["assets"] as? [String: String]
        XCTAssertEqual(assets?["small_text"], "Apple Music")
    }

    func test_stateLine_truncatesToActivityTextMax() {
        let longPlaylist = String(repeating: "P", count: 200)
        let line = DiscordRPCService.stateLine(
            artist: "Sade", playlist: .named(longPlaylist), style: .artistLine
        )
        XCTAssertEqual(line.count, AppConstants.Discord.activityTextMaxLength)
    }
}
