//
//  StatsCommandFormatTests.swift
//  WolfWave
//
//  Created by Nathanial Henniges on 2026-06-08.
//  Copyright © 2026 MrDemonWolf, Inc. All rights reserved.
//

import Testing
import Foundation
@testable import WolfWave

/// Tests for the `!stats` command configuration types: the window + facts
/// enums (resolution, parsing, round-tripping) and the pure chat-line renderer.
@MainActor
@Suite("Stats Command Format Tests")
struct StatsCommandFormatTests {

    // MARK: - Helpers

    /// A throwaway, empty UserDefaults store so tests never touch `.standard`.
    private func makeDefaults() -> UserDefaults {
        let suite = "StatsCommandFormatTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    private func track(_ name: String, by artist: String, count: Int) -> CountedItem {
        CountedItem(id: "\(name)|\(artist)".lowercased(), name: name, detail: artist, count: count)
    }

    private func artist(_ name: String, count: Int) -> CountedItem {
        CountedItem(id: name.lowercased(), name: name, detail: nil, count: count)
    }

    // MARK: - StatsWindow

    @Test("StatsWindow default is today")
    func windowDefault() {
        #expect(StatsWindow.default == .today)
    }

    @Test("StatsWindow.current falls back to default when unset or garbage")
    func windowCurrentFallback() {
        let defaults = makeDefaults()
        #expect(StatsWindow.current(defaults) == .today)

        defaults.set("not-a-window", forKey: AppConstants.UserDefaults.statsCommandWindow)
        #expect(StatsWindow.current(defaults) == .today)
    }

    @Test("StatsWindow.current resolves a stored value")
    func windowCurrentStored() {
        let defaults = makeDefaults()
        defaults.set(StatsWindow.session.rawValue, forKey: AppConstants.UserDefaults.statsCommandWindow)
        #expect(StatsWindow.current(defaults) == .session)
    }

    @Test("Every StatsWindow has labels")
    func windowLabels() {
        for window in StatsWindow.allCases {
            #expect(!window.pickerLabel.isEmpty)
            #expect(!window.chatLabel.isEmpty)
        }
    }

    // MARK: - StatsPart

    @Test("StatsPart defaults are plays + top track, in canonical order")
    func partDefaults() {
        #expect(StatsPart.defaults == [.plays, .topTrack])
    }

    @Test("decode parses a comma list into canonical order")
    func partDecodeOrder() {
        // Selection order should not matter; output is always canonical.
        #expect(StatsPart.decode("topArtist,plays") == [.plays, .topArtist])
        #expect(StatsPart.decode("topTrack, listeningTime , plays")
            == [.plays, .listeningTime, .topTrack])
    }

    @Test("decode drops unknowns and dedups, falling back when nothing parses")
    func partDecodeResilience() {
        #expect(StatsPart.decode("plays,plays,bogus") == [.plays])
        #expect(StatsPart.decode("") == StatsPart.defaults)
        #expect(StatsPart.decode("garbage,nonsense") == StatsPart.defaults)
    }

    @Test("encode + decode round-trips in canonical order")
    func partRoundTrip() {
        let raw = StatsPart.encode([.topArtist, .plays, .listeningTime])
        #expect(StatsPart.decode(raw) == [.plays, .listeningTime, .topArtist])
    }

    @Test("StatsPart.current reads stored parts, defaults when unset")
    func partCurrent() {
        let defaults = makeDefaults()
        #expect(StatsPart.current(defaults) == StatsPart.defaults)

        defaults.set("topArtist", forKey: AppConstants.UserDefaults.statsCommandParts)
        #expect(StatsPart.current(defaults) == [.topArtist])
    }

    @Test("Every StatsPart has a label")
    func partLabels() {
        for part in StatsPart.allCases {
            #expect(!part.label.isEmpty)
        }
    }

    // MARK: - StatsChatLine.render

    @Test("Empty summary returns the friendly nothing-yet line")
    func renderEmpty() {
        let line = StatsChatLine.render(label: "Today", summary: .empty, parts: StatsPart.defaults)
        #expect(line == "🐺 Today: nothing logged yet. The music's just getting started!")
    }

    @Test("Default facts render plays + top track like the classic reply")
    func renderDefault() {
        let summary = WindowSummary(
            plays: 47,
            listeningSeconds: 3 * 3600,
            topTrack: track("Howl", by: "Timber Wolf", count: 12),
            topArtist: artist("Timber Wolf", count: 20)
        )
        let line = StatsChatLine.render(label: "Today", summary: summary, parts: [.plays, .topTrack])
        #expect(line == "🐺 Today: 47 plays · top track Howl by Timber Wolf (12×)")
    }

    @Test("Render is independent of selection order")
    func renderOrderIndependent() {
        let summary = WindowSummary(
            plays: 5,
            listeningSeconds: 600,
            topTrack: track("Howl", by: "Timber Wolf", count: 3),
            topArtist: artist("Timber Wolf", count: 5)
        )
        let a = StatsChatLine.render(label: "This stream", summary: summary, parts: [.topArtist, .plays])
        let b = StatsChatLine.render(label: "This stream", summary: summary, parts: [.plays, .topArtist])
        #expect(a == b)
        #expect(a == "🐺 This stream: 5 plays · top artist Timber Wolf (5×)")
    }

    @Test("All four facts render in canonical order")
    func renderAllParts() {
        let summary = WindowSummary(
            plays: 100,
            listeningSeconds: 6 * 3600 + 12 * 60,
            topTrack: track("Howl", by: "Timber Wolf", count: 30),
            topArtist: artist("Timber Wolf", count: 55)
        )
        let line = StatsChatLine.render(
            label: "All time",
            summary: summary,
            parts: StatsPart.allCases
        )
        #expect(line == "🐺 All time: 100 plays · 6h 12m · top track Howl by Timber Wolf (30×) · top artist Timber Wolf (55×)")
    }

    @Test("Listening time alone renders the compact duration")
    func renderListeningTime() {
        let summary = WindowSummary(plays: 8, listeningSeconds: 90, topTrack: nil, topArtist: nil)
        let line = StatsChatLine.render(label: "Today", summary: summary, parts: [.listeningTime])
        #expect(line == "🐺 Today: 1m")
    }

    @Test("A single play uses singular play count and 1× multiplier")
    func renderSingular() {
        let summary = WindowSummary(
            plays: 1,
            listeningSeconds: 200,
            topTrack: track("Howl", by: "Timber Wolf", count: 1),
            topArtist: nil
        )
        let line = StatsChatLine.render(label: "Today", summary: summary, parts: [.plays, .topTrack])
        #expect(line == "🐺 Today: 1 play · top track Howl by Timber Wolf (1×)")
    }

    @Test("A selected fact with no data is skipped, never emitting an empty reply")
    func renderMissingDataSkipped() {
        // Plays exist but no top artist was resolved; the artist segment drops out.
        let summary = WindowSummary(plays: 4, listeningSeconds: 300, topTrack: nil, topArtist: nil)
        let line = StatsChatLine.render(label: "Today", summary: summary, parts: [.topArtist, .plays])
        #expect(line == "🐺 Today: 4 plays")
    }

    @Test("All selected facts missing falls back to the play count")
    func renderAllMissingFallsBackToPlays() {
        let summary = WindowSummary(plays: 9, listeningSeconds: 0, topTrack: nil, topArtist: nil)
        let line = StatsChatLine.render(label: "Today", summary: summary, parts: [.topTrack, .topArtist])
        #expect(line == "🐺 Today: 9 plays")
    }

    @Test("Empty parts falls back to the default facts")
    func renderEmptyPartsUsesDefaults() {
        let summary = WindowSummary(
            plays: 3,
            listeningSeconds: 120,
            topTrack: track("Howl", by: "Timber Wolf", count: 2),
            topArtist: nil
        )
        let line = StatsChatLine.render(label: "Today", summary: summary, parts: [])
        #expect(line == "🐺 Today: 3 plays · top track Howl by Timber Wolf (2×)")
    }

    @Test("Top track with no artist detail omits the by-clause")
    func renderTrackNoArtist() {
        let summary = WindowSummary(
            plays: 2,
            listeningSeconds: 100,
            topTrack: CountedItem(id: "howl|", name: "Howl", detail: nil, count: 2),
            topArtist: nil
        )
        let line = StatsChatLine.render(label: "Today", summary: summary, parts: [.topTrack])
        #expect(line == "🐺 Today: top track Howl (2×)")
    }
}
