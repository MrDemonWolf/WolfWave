//
//  SongListCommandTests.swift
//  WolfWaveTests
//
//  Created by Nathanial Henniges on 2026-06-08.
//  Copyright © 2026 MrDemonWolf, Inc. All rights reserved.
//

import XCTest

@testable import WolfWave

/// Covers `SongListCommand` (`!playlist`): opt-in gating, the configured-link
/// reply, silence when unset, alias support, and that it does not hijack the
/// `!songlist` trigger owned by `QueueCommand`.
///
/// Follows the `TrackInfoCommandTests` pattern of no `setUp`/`tearDown`
/// overrides (those fight `@MainActor` isolation on an `XCTestCase` subclass);
/// each test primes UserDefaults itself via `clearKeys()` / `enable(url:)`.
@MainActor
final class SongListCommandTests: XCTestCase {

    private let command = SongListCommand()

    private func clearKeys() {
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: AppConstants.UserDefaults.songListCommandEnabled)
        defaults.removeObject(forKey: AppConstants.UserDefaults.songListCommandAliases)
        defaults.removeObject(forKey: AppConstants.UserDefaults.songRequestSongListURL)
    }

    /// Resets keys, then enables the command with a configured link.
    private func enable(url: String) {
        clearKeys()
        let defaults = UserDefaults.standard
        defaults.set(true, forKey: AppConstants.UserDefaults.songListCommandEnabled)
        defaults.set(url, forKey: AppConstants.UserDefaults.songRequestSongListURL)
    }

    func testDisabledByDefaultReturnsNil() {
        // A link is set, but the toggle defaults off, so the command stays silent.
        clearKeys()
        UserDefaults.standard.set(
            "https://music.apple.com/x",
            forKey: AppConstants.UserDefaults.songRequestSongListURL
        )
        XCTAssertNil(command.execute(message: "!playlist"))
    }

    func testEnabledWithLinkPostsIt() {
        let url = "https://music.apple.com/us/playlist/wolfwave-requests/pl.u-abc"
        enable(url: url)
        XCTAssertEqual(command.execute(message: "!playlist"), "Song list: \(url)")
    }

    func testEnabledButBlankLinkReturnsNil() {
        clearKeys()
        UserDefaults.standard.set(true, forKey: AppConstants.UserDefaults.songListCommandEnabled)
        UserDefaults.standard.set("   ", forKey: AppConstants.UserDefaults.songRequestSongListURL)
        XCTAssertNil(command.execute(message: "!playlist"))
    }

    func testNonTriggerReturnsNil() {
        enable(url: "https://music.apple.com/x")
        XCTAssertNil(command.execute(message: "!queue"))
    }

    func testTriggerIsCaseInsensitive() {
        enable(url: "https://music.apple.com/x")
        XCTAssertEqual(command.execute(message: "!PlayList"), "Song list: https://music.apple.com/x")
    }

    func testCustomAliasResolves() {
        enable(url: "https://music.apple.com/x")
        UserDefaults.standard.set("list", forKey: AppConstants.UserDefaults.songListCommandAliases)
        XCTAssertEqual(command.execute(message: "!list"), "Song list: https://music.apple.com/x")
    }

    func testDoesNotHijackSonglistTrigger() {
        // !songlist belongs to QueueCommand (the in-chat text queue); the link
        // command must not respond to it.
        enable(url: "https://music.apple.com/x")
        XCTAssertNil(command.execute(message: "!songlist"))
    }
}
