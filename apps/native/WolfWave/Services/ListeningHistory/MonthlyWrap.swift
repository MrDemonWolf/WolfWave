//
//  MonthlyWrap.swift
//  WolfWave
//
//  Created by Nathanial Henniges on 2026-05-22.
//  Copyright © 2026 MrDemonWolf, Inc. All rights reserved.
//

import Foundation

// MARK: - MonthlyMilestone

/// A bragging-rights badge surfaced on the wrap card when a month stands out
/// against the user's own recorded history. Drives the "Spotify Wrapped"-style
/// milestone pill. Pure value; computed from records, no I/O.
enum MonthlyMilestone: Sendable, Equatable {
    /// This month logged more plays than any other recorded month.
    case bestMonthYet
    /// This month logged more listening time than any other recorded month.
    case mostListeningYet

    /// Short, on-card label. Kept punchy for the badge pill.
    var label: String {
        switch self {
        case .bestMonthYet:    return "Best month yet"
        case .mostListeningYet: return "Most listening yet"
        }
    }
}

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
    /// An emotional one-liner that frames the headline number. `nil` for empty
    /// months. Defaulted (and `var` so the memberwise init accepts it) so
    /// existing call sites and tests stay source-stable.
    var framingLine: String? = nil
    /// A standout milestone for this month vs. the user's own history, or `nil`.
    var milestone: MonthlyMilestone? = nil

    /// Whether the month has any recorded plays.
    var hasData: Bool { totalPlays > 0 }
}

// MARK: - MonthlyWrap

/// Builds a `MonthlyWrapData` from raw play records. Pure. No state, no I/O.
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

        let framing = framingLine(
            plays: monthRecords.count,
            seconds: totalSeconds,
            activeDays: dayBuckets.count
        )
        let milestone = milestone(
            allRecords: records,
            monthStart: monthStart,
            thisMonthPlays: monthRecords.count,
            thisMonthSeconds: totalSeconds,
            calendar: calendar
        )

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
            busiestDay: busiest,
            framingLine: framing,
            milestone: milestone
        )
    }

    // MARK: - Framing & Milestones

    /// Builds an emotional one-liner that frames the headline play count, the way
    /// Wrapped reads "788 hours finding yourself" instead of a raw minute count.
    /// Deterministic and ordered so it's unit-testable. `nil` for empty months.
    static func framingLine(plays: Int, seconds: TimeInterval, activeDays: Int) -> String? {
        guard plays > 0 else { return nil }
        let hours = seconds / 3600
        let perActiveDay = activeDays > 0 ? plays / activeDays : plays

        if hours >= 20 {
            return "Almost a full day lost in the music."
        }
        if hours >= 8 {
            return "A full work shift of nonstop play."
        }
        if perActiveDay >= 10 {
            return "About \(perActiveDay) tracks a day. You barely hit pause."
        }
        if plays >= 100 {
            return "\(plays) plays and still counting."
        }
        return "Every play logged, start to finish."
    }

    /// Decides whether this month stands out against the user's own recorded
    /// history. Returns `nil` when there's only one month of data (nothing to
    /// beat) or the month is empty. Pure: buckets all records by month start.
    static func milestone(
        allRecords: [PlayRecord],
        monthStart: Date,
        thisMonthPlays: Int,
        thisMonthSeconds: TimeInterval,
        calendar: Calendar = .current
    ) -> MonthlyMilestone? {
        guard thisMonthPlays > 0 else { return nil }

        var playsByMonth: [Date: Int] = [:]
        var secondsByMonth: [Date: TimeInterval] = [:]
        for record in allRecords {
            guard let start = calendar.dateInterval(of: .month, for: record.timestamp)?.start
            else { continue }
            playsByMonth[start, default: 0] += 1
            secondsByMonth[start, default: 0] += record.playedSeconds
        }

        // Need at least two distinct months for a "best yet" claim to mean anything.
        guard playsByMonth.count >= 2 else { return nil }

        // Compare against every *other* month: `allRecords` includes the viewed
        // month, so comparing against the overall max would make a strict
        // comparison impossible, and `>=` would count a tie as "best yet"
        // (contradicting the doc comment's "more plays than any other month").
        let maxOtherPlays = playsByMonth
            .filter { $0.key != monthStart }
            .values.max() ?? 0
        if thisMonthPlays > maxOtherPlays {
            return .bestMonthYet
        }

        let maxOtherSeconds = secondsByMonth
            .filter { $0.key != monthStart }
            .values.max() ?? 0
        if thisMonthSeconds > maxOtherSeconds {
            return .mostListeningYet
        }
        return nil
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
