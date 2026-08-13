//
//  PlaylistSetupStatusTests.swift
//  WolfWave
//
//  Created by Nathanial Henniges on 2026-06-08.
//  Copyright © 2026 MrDemonWolf, Inc. All rights reserved.
//

import Testing
@testable import WolfWave

/// Covers the `PlaylistSetupStatus` banner copy and the essential/cosmetic split
/// that decides whether a broken playlist stops the feature or just `!playlist`.
@MainActor
@Suite("PlaylistSetupStatus")
struct PlaylistSetupStatusTests {

    @Test("ok is silent: no banner, no action, not essential")
    func okIsSilent() {
        #expect(PlaylistSetupStatus.ok.bannerMessage == nil)
        #expect(PlaylistSetupStatus.ok.actionLabel == nil)
        #expect(PlaylistSetupStatus.ok.isEssential == false)
        #expect(PlaylistSetupStatus.ok.isError == false)
    }

    @Test("essential breaks vs the cosmetic ones")
    func essentialFlags() {
        #expect(PlaylistSetupStatus.playlistMissing.isEssential)
        #expect(PlaylistSetupStatus.musicAccessLost.isEssential)
        // A dead share link must never count as essential, so !sr keeps working.
        #expect(PlaylistSetupStatus.linkUnshared.isEssential == false)
        // Neither may a sync gap: it can clear itself, and only the streamer can
        // turn Sync Library on, so holding the feature would strand them.
        #expect(PlaylistSetupStatus.playlistNotInMusic.isEssential == false)
    }

    @Test("the sync-gap banner names the exact toggle to flip")
    func syncGapNamesTheToggle() throws {
        let message = try #require(PlaylistSetupStatus.playlistNotInMusic.bannerMessage)
        #expect(message.contains("Sync Library"))
        #expect(PlaylistSetupStatus.playlistNotInMusic.actionLabel == "Check Again")
    }

    /// Swept over `allCases` rather than a hand-listed array so a new status
    /// cannot ship with an empty banner or a missing button label.
    @Test("every non-ok status has a banner message and an action label")
    func nonOkHasMessaging() {
        for status in PlaylistSetupStatus.allCases where status != .ok {
            #expect(status.bannerMessage?.isEmpty == false)
            #expect(status.actionLabel?.isEmpty == false)
        }
    }

    @Test("raw values round-trip for @AppStorage persistence")
    func rawValuesStable() {
        for status in PlaylistSetupStatus.allCases {
            #expect(PlaylistSetupStatus(rawValue: status.rawValue) == status)
        }
        // Pin the stored spellings: these strings live in user defaults.
        #expect(PlaylistSetupStatus(rawValue: "ok") == .ok)
        #expect(PlaylistSetupStatus(rawValue: "playlistMissing") == .playlistMissing)
        #expect(PlaylistSetupStatus(rawValue: "linkUnshared") == .linkUnshared)
        #expect(PlaylistSetupStatus(rawValue: "musicAccessLost") == .musicAccessLost)
        #expect(PlaylistSetupStatus(rawValue: "playlistNotInMusic") == .playlistNotInMusic)
    }

    @Test("user-facing copy uses no em dashes")
    func noEmDashes() {
        for status in PlaylistSetupStatus.allCases where status != .ok {
            #expect(status.bannerMessage?.contains("\u{2014}") == false)
        }
    }
}
