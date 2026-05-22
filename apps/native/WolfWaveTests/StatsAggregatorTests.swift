//
//  StatsAggregatorTests.swift
//  wolfwave
//
//  Created by MrDemonWolf, Inc. on 5/22/26.
//

import Testing
import Foundation
@testable import WolfWave

/// Tests for the pure stats aggregation functions.
@Suite("Stats Aggregator Tests")
struct StatsAggregatorTests {

    // MARK: - Helpers

    /// A fixed UTC Gregorian calendar so day/hour bucketing is deterministic.
    private var calendar: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        return cal
    }

    /// Builds a date at the given UTC components.
    private func date(_ year: Int, _ month: Int, _ day: Int, hour: Int = 12) -> Date {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.hour = hour
        return calendar.date(from: components)!
    }

    private func record(
        track: String, artist: String, album: String = "Album",
        at date: Date, played: TimeInterval = 180
    ) -> PlayRecord {
        PlayRecord(timestamp: date, track: track, artist: artist, album: album,
                   duration: 200, playedSeconds: played)
    }

    // MARK: - Empty

    @Test("An empty record set yields the empty snapshot")
    func testEmpty() {
        let snapshot = StatsAggregator.snapshot(from: [])
        #expect(!snapshot.hasData)
        #expect(snapshot.totalPlays == 0)
        #expect(snapshot.playsByHour.count == 24)
    }

    // MARK: - Totals

    @Test("Total plays and listening time sum correctly")
    func testTotals() {
        let now = date(2026, 5, 20)
        let records = [
            record(track: "A", artist: "X", at: now, played: 100),
            record(track: "B", artist: "X", at: now, played: 200),
            record(track: "C", artist: "Y", at: now, played: 50),
        ]
        let snapshot = StatsAggregator.snapshot(from: records, now: now, calendar: calendar)
        #expect(snapshot.totalPlays == 3)
        #expect(snapshot.totalListeningSeconds == 350)
    }

    // MARK: - Top Lists

    @Test("Top artists are ranked by play count")
    func testTopArtists() {
        let now = date(2026, 5, 20)
        let records = [
            record(track: "A1", artist: "Alpha", at: now),
            record(track: "A2", artist: "Alpha", at: now),
            record(track: "A3", artist: "Alpha", at: now),
            record(track: "B1", artist: "Beta", at: now),
        ]
        let snapshot = StatsAggregator.snapshot(from: records, now: now, calendar: calendar)
        #expect(snapshot.topArtists.first?.name == "Alpha")
        #expect(snapshot.topArtists.first?.count == 3)
        #expect(snapshot.topArtists.count == 2)
    }

    @Test("Top tracks group case-insensitively and keep an artist detail")
    func testTopTracks() {
        let now = date(2026, 5, 20)
        let records = [
            record(track: "Echo", artist: "Alpha", at: now),
            record(track: "echo", artist: "Alpha", at: now),
        ]
        let snapshot = StatsAggregator.snapshot(from: records, now: now, calendar: calendar)
        #expect(snapshot.topTracks.count == 1)
        #expect(snapshot.topTracks.first?.count == 2)
        #expect(snapshot.topTracks.first?.detail == "Alpha")
    }

    @Test("Albums with empty titles are excluded from top albums")
    func testTopAlbumsSkipsEmpty() {
        let now = date(2026, 5, 20)
        let records = [
            record(track: "A", artist: "X", album: "", at: now),
            record(track: "B", artist: "X", album: "Real Album", at: now),
        ]
        let snapshot = StatsAggregator.snapshot(from: records, now: now, calendar: calendar)
        #expect(snapshot.topAlbums.count == 1)
        #expect(snapshot.topAlbums.first?.name == "Real Album")
    }

    // MARK: - Day & Hour Buckets

    @Test("last7Days always has exactly 7 buckets")
    func testSevenDayBuckets() {
        let now = date(2026, 5, 20)
        let snapshot = StatsAggregator.snapshot(
            from: [record(track: "A", artist: "X", at: now)],
            now: now, calendar: calendar
        )
        #expect(snapshot.last7Days.count == 7)
        // Today's bucket is the last one and contains the play.
        #expect(snapshot.last7Days.last?.count == 1)
    }

    @Test("Plays are bucketed by hour of day")
    func testPlaysByHour() {
        let now = date(2026, 5, 20, hour: 23)
        let records = [
            record(track: "A", artist: "X", at: date(2026, 5, 20, hour: 9)),
            record(track: "B", artist: "X", at: date(2026, 5, 20, hour: 9)),
            record(track: "C", artist: "X", at: date(2026, 5, 20, hour: 14)),
        ]
        let snapshot = StatsAggregator.snapshot(from: records, now: now, calendar: calendar)
        #expect(snapshot.playsByHour[9] == 2)
        #expect(snapshot.playsByHour[14] == 1)
        #expect(snapshot.playsByHour[0] == 0)
    }

    // MARK: - Today

    @Test("playsToday only counts records from the current day")
    func testPlaysToday() {
        let now = date(2026, 5, 20)
        let records = [
            record(track: "Today1", artist: "X", at: date(2026, 5, 20, hour: 8)),
            record(track: "Today2", artist: "X", at: date(2026, 5, 20, hour: 18)),
            record(track: "Yesterday", artist: "X", at: date(2026, 5, 19)),
        ]
        let snapshot = StatsAggregator.snapshot(from: records, now: now, calendar: calendar)
        #expect(snapshot.playsToday == 2)
        #expect(snapshot.topTrackToday != nil)
    }

    @Test("recent plays are newest first")
    func testRecentOrdering() {
        let now = date(2026, 5, 20)
        let records = [
            record(track: "Oldest", artist: "X", at: date(2026, 5, 18)),
            record(track: "Newest", artist: "X", at: date(2026, 5, 20)),
            record(track: "Middle", artist: "X", at: date(2026, 5, 19)),
        ]
        let snapshot = StatsAggregator.snapshot(from: records, now: now, calendar: calendar)
        #expect(snapshot.recent.first?.track == "Newest")
        #expect(snapshot.recent.last?.track == "Oldest")
    }
}
