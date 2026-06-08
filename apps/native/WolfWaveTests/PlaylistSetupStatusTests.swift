//
//  PlaylistSetupStatusTests.swift
//  WolfWaveTests
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

    @Test("essential breaks vs the cosmetic link break")
    func essentialFlags() {
        #expect(PlaylistSetupStatus.playlistMissing.isEssential)
        #expect(PlaylistSetupStatus.musicAccessLost.isEssential)
        // A dead share link must never count as essential, so !sr keeps working.
        #expect(PlaylistSetupStatus.linkUnshared.isEssential == false)
    }

    @Test("every non-ok status has a banner message and an action label")
    func nonOkHasMessaging() {
        for status in [PlaylistSetupStatus.playlistMissing, .linkUnshared, .musicAccessLost] {
            #expect(status.bannerMessage?.isEmpty == false)
            #expect(status.actionLabel?.isEmpty == false)
        }
    }

    @Test("raw values round-trip for @AppStorage persistence")
    func rawValuesStable() {
        #expect(PlaylistSetupStatus(rawValue: "ok") == .ok)
        #expect(PlaylistSetupStatus(rawValue: "playlistMissing") == .playlistMissing)
        #expect(PlaylistSetupStatus(rawValue: "linkUnshared") == .linkUnshared)
        #expect(PlaylistSetupStatus(rawValue: "musicAccessLost") == .musicAccessLost)
    }

    @Test("user-facing copy uses no em dashes")
    func noEmDashes() {
        for status in [PlaylistSetupStatus.playlistMissing, .linkUnshared, .musicAccessLost] {
            #expect(status.bannerMessage?.contains("\u{2014}") == false)
        }
    }
}
