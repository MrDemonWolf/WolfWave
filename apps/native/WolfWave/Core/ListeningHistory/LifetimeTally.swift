//
//  LifetimeTally.swift
//  WolfWave
//
//  Created by Nathanial Henniges on 2026-05-25.
//  Copyright © 2026 MrDemonWolf, Inc. All rights reserved.
//

import Foundation

// MARK: - LifetimeTally

/// Persisted rollup of plays that have been *trimmed* out of the rolling
/// `PlayRecord` window so that lifetime stats (`totalPlays`, top artists, etc.)
/// remain correct after old records are dropped.
///
/// The tally only accounts for the records no longer in memory. The live
/// `records` array contributes separately when `StatsAggregator` merges them.
///
/// Per-dimension dictionaries are capped at
/// `AppConstants.History.lifetimeTopKeyCap` entries; eviction drops the
/// lowest-count entry to bound the on-disk size.
nonisolated struct LifetimeTally: Codable, Equatable, Sendable {

    // MARK: - TallyEntry

    /// A single per-key bucket within the tally.
    nonisolated struct TallyEntry: Codable, Equatable, Sendable {
        /// Display name (preserves casing from the most recent fold).
        var name: String
        /// Optional secondary line, used as the artist for tracks and albums.
        var detail: String?
        /// Number of folded plays attributed to this key.
        var count: Int
        /// Total played seconds attributed to this key.
        var seconds: TimeInterval
    }

    // MARK: - Properties

    /// Total plays folded into the tally (no longer in `records[]`).
    var trimmedPlayCount: Int = 0

    /// Total listening seconds folded into the tally.
    var trimmedListeningSeconds: TimeInterval = 0

    /// Timestamp of the newest record folded into this tally (its high-water
    /// mark). `nil` until the first fold. Used on load to skip re-folding records
    /// that are already reflected here but may still linger in the append-only
    /// NDJSON after an unclean exit (which would otherwise double-count lifetime
    /// stats). Optional so tally files written before this field decode cleanly
    /// (absent key → `nil`).
    var lastFoldedTimestamp: Date?

    /// Per-artist counts (key: `PlayRecord.artistKey`).
    var artistCounts: [String: TallyEntry] = [:]

    /// Per-track counts (key: `PlayRecord.trackKey`).
    var trackCounts: [String: TallyEntry] = [:]

    /// Per-album counts (key: `PlayRecord.albumKey`).
    var albumCounts: [String: TallyEntry] = [:]

    // MARK: - Convenience

    /// The empty tally, used before any record has been folded.
    static let empty = LifetimeTally()

    /// Whether the tally contains anything.
    var isEmpty: Bool {
        trimmedPlayCount == 0
            && artistCounts.isEmpty
            && trackCounts.isEmpty
            && albumCounts.isEmpty
    }

    // MARK: - Folding

    /// Folds a single record into the tally, incrementing totals and updating
    /// per-key buckets. Evicts the lowest-count entry from each dimension when
    /// its dictionary exceeds `keyCap`.
    ///
    /// - Parameters:
    ///   - record: Record being trimmed from the live window.
    ///   - keyCap: Per-dimension cap. Defaults to
    ///     `AppConstants.History.lifetimeTopKeyCap`.
    mutating func fold(_ record: PlayRecord, keyCap: Int = AppConstants.History.lifetimeTopKeyCap) {
        trimmedPlayCount += 1
        trimmedListeningSeconds += record.playedSeconds
        lastFoldedTimestamp = Swift.max(lastFoldedTimestamp ?? record.timestamp, record.timestamp)

        Self.bump(
            &artistCounts, key: record.artistKey, name: record.artist,
            detail: nil, played: record.playedSeconds, keyCap: keyCap
        )
        Self.bump(
            &trackCounts, key: record.trackKey, name: record.track,
            detail: record.artist, played: record.playedSeconds, keyCap: keyCap
        )
        if !record.album.isEmpty {
            Self.bump(
                &albumCounts, key: record.albumKey, name: record.album,
                detail: record.artist, played: record.playedSeconds, keyCap: keyCap
            )
        }
    }

    /// Folds a batch of records, applying eviction once at the end.
    mutating func fold(_ records: [PlayRecord], keyCap: Int = AppConstants.History.lifetimeTopKeyCap) {
        for record in records {
            fold(record, keyCap: keyCap)
        }
    }

    // MARK: - Private

    /// Increments `dict[key]` (creating the bucket if missing) and evicts the
    /// lowest-count entry when `dict.count > keyCap`.
    private static func bump(
        _ dict: inout [String: TallyEntry],
        key: String,
        name: String,
        detail: String?,
        played: TimeInterval,
        keyCap: Int
    ) {
        if var existing = dict[key] {
            existing.count += 1
            existing.seconds += played
            existing.name = name
            existing.detail = detail
            dict[key] = existing
        } else {
            dict[key] = TallyEntry(name: name, detail: detail, count: 1, seconds: played)
            if dict.count > keyCap {
                evictLowest(&dict)
            }
        }
    }

    /// Drops the lowest-count entry. Ties broken by name (alphabetic last).
    private static func evictLowest(_ dict: inout [String: TallyEntry]) {
        guard let victim = dict.min(by: { lhs, rhs in
            if lhs.value.count != rhs.value.count { return lhs.value.count < rhs.value.count }
            return lhs.value.name.localizedCaseInsensitiveCompare(rhs.value.name) == .orderedDescending
        }) else { return }
        dict.removeValue(forKey: victim.key)
    }
}

// MARK: - LifetimeTallyStore

/// Persists a `LifetimeTally` as a single JSON file alongside the play log.
///
/// Writes are atomic and happen on a dedicated serial queue, so the store is
/// safe to call from any thread.
nonisolated final class LifetimeTallyStore: @unchecked Sendable {

    // MARK: - Properties

    /// URL of the tally JSON file.
    let fileURL: URL

    /// Serial queue protecting all file I/O.
    private let ioQueue = DispatchQueue(
        label: "com.mrdemonwolf.wolfwave.lifetimetally", qos: .utility
    )

    private let encoder = JSONCoders.defaultEncoder
    private let decoder = JSONCoders.default

    // MARK: - Init

    init(directory: URL? = nil) {
        let dir = directory ?? HistoryStoreSupport.defaultDirectory()
        fileURL = dir.appending(path: AppConstants.History.lifetimeTallyFileName)
    }

    // MARK: - Public API

    /// Loads the tally from disk, returning `.empty` when the file is absent or
    /// malformed.
    func load() -> LifetimeTally {
        ioQueue.sync {
            guard let data = try? Data(contentsOf: fileURL), !data.isEmpty,
                  let tally = try? decoder.decode(LifetimeTally.self, from: data) else {
                return .empty
            }
            return tally
        }
    }

    /// Atomically writes `tally` to disk.
    func save(_ tally: LifetimeTally) {
        ioQueue.sync {
            ensureDirectoryExists()
            guard let data = try? encoder.encode(tally) else {
                Log.warn(
                    "LifetimeTallyStore: Failed to encode tally",
                    category: AppConstants.History.logCategory
                )
                return
            }
            do {
                try data.write(to: fileURL, options: .atomic)
            } catch {
                Log.error(
                    "LifetimeTallyStore: Save failed: \(error.localizedDescription)",
                    category: AppConstants.History.logCategory
                )
            }
        }
    }

    /// Removes the tally file (used by `clearHistory`).
    func clear() {
        ioQueue.sync {
            try? FileManager.default.removeItem(at: fileURL)
        }
    }

    private func ensureDirectoryExists() {
        HistoryStoreSupport.ensureDirectory(for: fileURL)
    }
}
