//
//  StatsAggregator.swift
//  WolfWave
//
//  Created by Nathanial Henniges on 2026-05-22.
//  Copyright © 2026 MrDemonWolf, Inc. All rights reserved.
//

import Foundation

// MARK: - CountedItem

/// A named thing (artist, track, album) with how many times it was played.
struct CountedItem: Identifiable, Hashable, Sendable {
    /// Stable grouping key (case-insensitive).
    let id: String
    /// Display name (e.g. track or artist title).
    let name: String
    /// Optional secondary line (e.g. the artist for a track row).
    let detail: String?
    /// Number of recorded plays.
    let count: Int
}

// MARK: - DailyCount

/// Play count and listening time bucketed to a single calendar day.
struct DailyCount: Identifiable, Hashable, Sendable {
    /// Start-of-day date — also the identity.
    let id: Date
    /// Number of plays that day.
    let count: Int
    /// Listening time that day, in seconds.
    let seconds: TimeInterval

    /// Start-of-day date for the bucket.
    var day: Date { id }
}

// MARK: - StatsSnapshot

/// An immutable, fully-derived view of the listening history. Recomputed from
/// the in-memory play log whenever it changes — it costs no disk I/O.
struct StatsSnapshot: Sendable {
    let totalPlays: Int
    let totalListeningSeconds: TimeInterval
    let playsToday: Int
    let listeningSecondsToday: TimeInterval
    let playsThisWeek: Int
    let listeningSecondsThisWeek: TimeInterval
    let topArtists: [CountedItem]
    let topTracks: [CountedItem]
    let topAlbums: [CountedItem]
    /// Exactly 7 buckets, oldest day first, ending today.
    let last7Days: [DailyCount]
    /// 24 buckets, index = hour of day (0–23).
    let playsByHour: [Int]
    /// Most recent plays, newest first.
    let recent: [PlayRecord]
    /// The most-played track recorded today, if any.
    let topTrackToday: CountedItem?

    /// An empty snapshot — used before any history is loaded.
    static let empty = StatsSnapshot(
        totalPlays: 0,
        totalListeningSeconds: 0,
        playsToday: 0,
        listeningSecondsToday: 0,
        playsThisWeek: 0,
        listeningSecondsThisWeek: 0,
        topArtists: [],
        topTracks: [],
        topAlbums: [],
        last7Days: [],
        playsByHour: Array(repeating: 0, count: 24),
        recent: [],
        topTrackToday: nil
    )

    /// Whether there is anything to show.
    var hasData: Bool { totalPlays > 0 }
}

// MARK: - StatsAggregator

/// Pure functions that derive a `StatsSnapshot` from raw play records.
///
/// No state, no I/O — trivially testable and cheap to call (a few passes over
/// the records array).
enum StatsAggregator {

    /// How many entries each "top" list contains.
    static let topListLimit = 10

    /// Builds a snapshot from `records`, optionally folding in a persisted
    /// `LifetimeTally` for stats that must outlive the rolling record window.
    ///
    /// - Parameters:
    ///   - records: All recorded plays currently in memory, in any order.
    ///   - lifetime: Tally of plays previously trimmed out of `records`.
    ///     Defaults to `.empty` — pass a non-empty tally to merge totals + top-N.
    ///   - now: The reference "now" for today/this-week windows. Injectable for tests.
    ///   - calendar: Calendar used for day bucketing. Injectable for tests.
    /// - Returns: A fully-derived snapshot.
    static func snapshot(
        from records: [PlayRecord],
        lifetime: LifetimeTally = .empty,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> StatsSnapshot {
        guard !records.isEmpty || !lifetime.isEmpty else { return .empty }

        let startOfToday = calendar.startOfDay(for: now)
        let weekStart = calendar.date(byAdding: .day, value: -6, to: startOfToday) ?? startOfToday

        var totalSeconds: TimeInterval = 0
        var todayPlays = 0
        var todaySeconds: TimeInterval = 0
        var weekPlays = 0
        var weekSeconds: TimeInterval = 0
        var byHour = Array(repeating: 0, count: 24)
        var todayRecords: [PlayRecord] = []

        for record in records {
            totalSeconds += record.playedSeconds
            let hour = calendar.component(.hour, from: record.timestamp)
            if hour >= 0, hour < 24 { byHour[hour] += 1 }

            if record.timestamp >= startOfToday {
                todayPlays += 1
                todaySeconds += record.playedSeconds
                todayRecords.append(record)
            }
            if record.timestamp >= weekStart {
                weekPlays += 1
                weekSeconds += record.playedSeconds
            }
        }

        let recent = records
            .sorted { $0.timestamp > $1.timestamp }
            .prefix(AppConstants.History.recentDisplayCount)

        return StatsSnapshot(
            totalPlays: records.count + lifetime.trimmedPlayCount,
            totalListeningSeconds: totalSeconds + lifetime.trimmedListeningSeconds,
            playsToday: todayPlays,
            listeningSecondsToday: todaySeconds,
            playsThisWeek: weekPlays,
            listeningSecondsThisWeek: weekSeconds,
            topArtists: topItems(
                records, key: \.artistKey, name: \.artist, detail: nil,
                merging: lifetime.artistCounts
            ),
            topTracks: topItems(
                records, key: \.trackKey, name: \.track, detail: \.artist,
                merging: lifetime.trackCounts
            ),
            topAlbums: topItems(
                records.filter { !$0.album.isEmpty },
                key: \.albumKey, name: \.album, detail: \.artist,
                merging: lifetime.albumCounts
            ),
            last7Days: dailyBuckets(records, startOfToday: startOfToday, calendar: calendar),
            playsByHour: byHour,
            recent: Array(recent),
            topTrackToday: topItems(
                todayRecords, key: \.trackKey, name: \.track, detail: \.artist,
                merging: [:]
            ).first
        )
    }

    // MARK: - Private Helpers

    /// Groups `records` by `key`, returning the most-played entries first.
    ///
    /// - Parameters:
    ///   - records: Records to group.
    ///   - key: Key path producing the grouping key.
    ///   - name: Key path producing the display name.
    ///   - detail: Optional key path producing the secondary line.
    /// - Returns: Up to `topListLimit` items, highest count first.
    private static func topItems(
        _ records: [PlayRecord],
        key: KeyPath<PlayRecord, String>,
        name: KeyPath<PlayRecord, String>,
        detail: KeyPath<PlayRecord, String>?,
        merging tally: [String: LifetimeTally.TallyEntry]
    ) -> [CountedItem] {
        struct Bucket {
            var name: String
            var detail: String?
            var count: Int
            var latest: Date
        }
        var buckets: [String: Bucket] = [:]

        // Seed with the persisted lifetime counts. Records (live, newer) win
        // the display-string tie-break because they're processed second.
        for (groupKey, entry) in tally {
            buckets[groupKey] = Bucket(
                name: entry.name,
                detail: entry.detail,
                count: entry.count,
                latest: .distantPast
            )
        }

        for record in records {
            let groupKey = record[keyPath: key]
            let displayName = record[keyPath: name]
            let displayDetail = detail.map { record[keyPath: $0] }
            if var existing = buckets[groupKey] {
                existing.count += 1
                // Prefer the display strings from the most recent play.
                if record.timestamp >= existing.latest {
                    existing.name = displayName
                    existing.detail = displayDetail
                    existing.latest = record.timestamp
                }
                buckets[groupKey] = existing
            } else {
                buckets[groupKey] = Bucket(
                    name: displayName,
                    detail: displayDetail,
                    count: 1,
                    latest: record.timestamp
                )
            }
        }

        let items: [CountedItem] = buckets.map { key, value in
            CountedItem(id: key, name: value.name, detail: value.detail, count: value.count)
        }
        let ranked = items.sorted { lhs, rhs in
            if lhs.count != rhs.count { return lhs.count > rhs.count }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
        return Array(ranked.prefix(topListLimit))
    }

    /// Builds exactly 7 day buckets ending today (oldest first).
    private static func dailyBuckets(
        _ records: [PlayRecord],
        startOfToday: Date,
        calendar: Calendar
    ) -> [DailyCount] {
        var counts: [Date: (count: Int, seconds: TimeInterval)] = [:]
        for record in records {
            let day = calendar.startOfDay(for: record.timestamp)
            var bucket = counts[day] ?? (0, 0)
            bucket.count += 1
            bucket.seconds += record.playedSeconds
            counts[day] = bucket
        }

        return (0..<7).reversed().compactMap { offset -> DailyCount? in
            guard let day = calendar.date(byAdding: .day, value: -offset, to: startOfToday) else { return nil }
            let bucket = counts[day] ?? (0, 0)
            return DailyCount(id: day, count: bucket.count, seconds: bucket.seconds)
        }
    }
}
