//
//  MonthlyWrap.swift
//  WolfWave
//
//  Created by Nathanial Henniges on 2026-05-22.
//  Copyright © 2026 MrDemonWolf, Inc. All rights reserved.
//

import Foundation

// MARK: - MonthlyWrapData

/// A personal "wrapped"-style summary of one calendar month of listening.
struct MonthlyWrapData: Sendable {
    /// Human-readable month label, e.g. "May 2026".
    let monthLabel: String
    /// First day of the month this wrap covers.
    let monthStart: Date
    /// Total plays recorded in the month.
    let totalPlays: Int
    /// Total listening time in the month, in seconds.
    let totalListeningSeconds: TimeInterval
    /// Distinct artists heard.
    let uniqueArtists: Int
    /// Distinct tracks heard.
    let uniqueTracks: Int
    /// Most-played artist of the month.
    let topArtist: CountedItem?
    /// Most-played track of the month.
    let topTrack: CountedItem?
    /// Most-played album of the month.
    let topAlbum: CountedItem?
    /// The single busiest listening day.
    let busiestDay: DailyCount?

    /// Whether the month has any recorded plays.
    var hasData: Bool { totalPlays > 0 }
}

// MARK: - MonthlyWrap

/// Builds a `MonthlyWrapData` from raw play records. Pure — no state, no I/O.
enum MonthlyWrap {

    /// Builds the wrap for the calendar month containing `month`.
    ///
    /// - Parameters:
    ///   - records: All recorded plays, in any order.
    ///   - month: Any date inside the target month. Defaults to now.
    ///   - calendar: Calendar used for month/day bucketing. Injectable for tests.
    /// - Returns: The month's summary (empty when no plays fall in the month).
    static func data(
        from records: [PlayRecord],
        month: Date = Date(),
        calendar: Calendar = .current
    ) -> MonthlyWrapData {
        let interval = calendar.dateInterval(of: .month, for: month)
        let monthStart = interval?.start ?? calendar.startOfDay(for: month)
        let label = monthLabel(for: monthStart)

        let monthRecords: [PlayRecord]
        if let interval {
            monthRecords = records.filter { interval.contains($0.timestamp) }
        } else {
            monthRecords = []
        }

        guard !monthRecords.isEmpty else {
            return MonthlyWrapData(
                monthLabel: label,
                monthStart: monthStart,
                totalPlays: 0,
                totalListeningSeconds: 0,
                uniqueArtists: 0,
                uniqueTracks: 0,
                topArtist: nil,
                topTrack: nil,
                topAlbum: nil,
                busiestDay: nil
            )
        }

        let snapshot = StatsAggregator.snapshot(
            from: monthRecords,
            now: interval?.end ?? month,
            calendar: calendar
        )
        let totalSeconds = monthRecords.reduce(0) { $0 + $1.playedSeconds }
        let uniqueArtists = Set(monthRecords.map { $0.artistKey }).count
        let uniqueTracks = Set(monthRecords.map { $0.trackKey }).count

        var dayBuckets: [Date: (count: Int, seconds: TimeInterval)] = [:]
        for record in monthRecords {
            let day = calendar.startOfDay(for: record.timestamp)
            var bucket = dayBuckets[day] ?? (0, 0)
            bucket.count += 1
            bucket.seconds += record.playedSeconds
            dayBuckets[day] = bucket
        }
        let busiest = dayBuckets
            .map { DailyCount(id: $0.key, count: $0.value.count, seconds: $0.value.seconds) }
            .max { $0.count < $1.count }

        return MonthlyWrapData(
            monthLabel: label,
            monthStart: monthStart,
            totalPlays: monthRecords.count,
            totalListeningSeconds: totalSeconds,
            uniqueArtists: uniqueArtists,
            uniqueTracks: uniqueTracks,
            topArtist: snapshot.topArtists.first,
            topTrack: snapshot.topTracks.first,
            topAlbum: snapshot.topAlbums.first,
            busiestDay: busiest
        )
    }

    private static let monthLabelFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "LLLL yyyy"
        return formatter
    }()

    /// Formats a "Month Year" label for the given date.
    private static func monthLabel(for date: Date) -> String {
        monthLabelFormatter.string(from: date)
    }
}
