//
//  NowPlayingHeroCardTests.swift
//  WolfWave
//
//  Created by Nathanial Henniges on 2026-08-04.
//  Copyright © 2026 MrDemonWolf, Inc. All rights reserved.
//

import Testing
@testable import WolfWave

/// Copy rules for the now-playing card's empty state.
///
/// The card used to show "Nothing playing right now" whether Music was closed or
/// merely idle, which left users with no hint that the app they needed was shut.
/// These cases lock the three states apart.
@MainActor
struct NowPlayingHeroCardTests {

    // MARK: - Empty state headline

    @Test("Music closed reads as closed, not as idle")
    func closedMusicHasItsOwnHeadline() {
        let title = NowPlayingHeroCard.emptyStateTitle(trackingEnabled: true, musicNotRunning: true)
        #expect(title == "Apple Music isn't open")
    }

    @Test("Music open with nothing loaded still reads as idle")
    func idleMusicKeepsTheIdleHeadline() {
        let title = NowPlayingHeroCard.emptyStateTitle(trackingEnabled: true, musicNotRunning: false)
        #expect(title == "Nothing playing right now")
    }

    @Test("Tracking off wins over the Music-closed state")
    func trackingOffTakesPrecedence() {
        // Sync Music being off is the thing the user has to fix first, so it is
        // reported even when Music also happens to be closed.
        let offAndClosed = NowPlayingHeroCard.emptyStateTitle(trackingEnabled: false, musicNotRunning: true)
        let offAndOpen = NowPlayingHeroCard.emptyStateTitle(trackingEnabled: false, musicNotRunning: false)
        #expect(offAndClosed == "Sync Music is off")
        #expect(offAndOpen == "Sync Music is off")
    }

    @Test("The three states never share a headline")
    func headlinesAreDistinct() {
        let closed = NowPlayingHeroCard.emptyStateTitle(trackingEnabled: true, musicNotRunning: true)
        let idle = NowPlayingHeroCard.emptyStateTitle(trackingEnabled: true, musicNotRunning: false)
        let off = NowPlayingHeroCard.emptyStateTitle(trackingEnabled: false, musicNotRunning: false)
        #expect(Set([closed, idle, off]).count == 3)
    }

    // MARK: - Open Music affordance

    @Test("Open Music is offered only when Music is closed and tracking is on")
    func openMusicVisibility() {
        #expect(NowPlayingHeroCard.showsOpenMusic(trackingEnabled: true, musicNotRunning: true))
        // Nothing to fix by launching Music when it is already open.
        #expect(!NowPlayingHeroCard.showsOpenMusic(trackingEnabled: true, musicNotRunning: false))
        // Launching Music would do nothing while tracking is off.
        #expect(!NowPlayingHeroCard.showsOpenMusic(trackingEnabled: false, musicNotRunning: true))
        #expect(!NowPlayingHeroCard.showsOpenMusic(trackingEnabled: false, musicNotRunning: false))
    }
}
