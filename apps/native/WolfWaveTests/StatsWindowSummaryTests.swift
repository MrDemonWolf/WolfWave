//
//  StatsWindowSummaryTests.swift
//  WolfWave
//
//  Created by Nathanial Henniges on 2026-06-08.
//  Copyright © 2026 MrDemonWolf, Inc. All rights reserved.
//

import Testing
import Foundation
@testable import WolfWave

/// Tests for `StatsAggregator.windowSummary` — the window-scoped rollup that
/// backs the `!stats` command across today / this-stream / 7-day / all-time.
@MainActor
@Suite("Stats Window Summary Tests")
struct StatsWindowSummaryTests {

    // MARK: - Fixtures

    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    /// Plays: Howl×2 + Bay recent, OldSong two days ago.
    /// Artists: Timber Wolf×3 (incl. OldSong), Grey Wolf×1.
    private func records() -> [PlayRecord] {
        let recent = now.addingTimeInterval(-60)
        let older = now.addingTimeInterval(-48 * 3600)
        return [
            PlayRecord(timestamp: recent, track: "Howl", artist: "Timber Wolf", album: "Pack", duration: 200, playedSeconds: 200),
            PlayRecord(timestamp: recent, track: "Howl", artist: "Timber Wolf", album: "Pack", duration: 200, playedSeconds: 200),
            PlayRecord(timestamp: recent, track: "Bay", artist: "Grey Wolf", album: "Moon", duration: 100, playedSeconds: 100),
            PlayRecord(timestamp: older, track: "OldSong", artist: "Timber Wolf", album: "Pack", duration: 300, playedSeconds: 300),
        ]
    }

    /// A non-empty lifetime tally (one trimmed play by a different artist).
    private func lifetime() -> LifetimeTally {
        var tally = LifetimeTally()
        tally.fold(PlayRecord(track: "Legacy", artist: "Ancient Wolf", album: "", duration: 500, playedSeconds: 500))
        return tally
    }

    // MARK: - Tests

    @Test("Empty records and empty lifetime produce an empty summary")
    func emptyInputs() {
        let summary = StatsAggregator.windowSummary(from: [], since: nil)
        #expect(!summary.hasData)
        #expect(summary.plays == 0)
        #expect(summary.topTrack == nil)
    }

    @Test("Unbounded window counts every record")
    func unboundedAllRecords() {
        let summary = StatsAggregator.windowSummary(from: records(), since: nil)
        #expect(summary.plays == 4)
        #expect(summary.listeningSeconds == 800)
        #expect(summary.topTrack?.name == "Howl")
        #expect(summary.topTrack?.count == 2)
        #expect(summary.topArtist?.name == "Timber Wolf")
        #expect(summary.topArtist?.count == 3)
    }

    @Test("A lower time bound filters out older plays")
    func boundedFiltersOlder() {
        let oneHourAgo = now.addingTimeInterval(-3600)
        let summary = StatsAggregator.windowSummary(from: records(), since: oneHourAgo)
        // OldSong (two days ago) drops out.
        #expect(summary.plays == 3)
        #expect(summary.listeningSeconds == 500)
        #expect(summary.topTrack?.name == "Howl")
        #expect(summary.topArtist?.name == "Timber Wolf")
        #expect(summary.topArtist?.count == 2)
    }

    @Test("Lifetime tally is folded only for the unbounded window")
    func lifetimeFoldedOnlyWhenUnbounded() {
        let unbounded = StatsAggregator.windowSummary(from: records(), since: nil, lifetime: lifetime())
        #expect(unbounded.plays == 5) // 4 live + 1 trimmed
        #expect(unbounded.listeningSeconds == 1300) // 800 + 500
        // Timber Wolf (3) still outranks the trimmed Ancient Wolf (1).
        #expect(unbounded.topArtist?.name == "Timber Wolf")

        let oneHourAgo = now.addingTimeInterval(-3600)
        let bounded = StatsAggregator.windowSummary(from: records(), since: oneHourAgo, lifetime: lifetime())
        // Bounded windows ignore the (timestamp-less) lifetime tally.
        #expect(bounded.plays == 3)
        #expect(bounded.listeningSeconds == 500)
    }

    @Test("A bound after every record yields an empty summary")
    func boundAfterEverythingIsEmpty() {
        let future = now.addingTimeInterval(3600)
        let summary = StatsAggregator.windowSummary(from: records(), since: future)
        #expect(!summary.hasData)
    }
}
