//
//  ListeningHistoryService.swift
//  wolfwave
//
//  Created by MrDemonWolf, Inc. on 5/22/26.
//

import Foundation
import Observation

/// Orchestrates the opt-in Listening History & Stats feature.
///
/// Owns the append-only `PlayLogStore`, keeps an in-memory copy of every
/// recorded play, applies the scrobble threshold, and exposes a derived
/// `StatsSnapshot` for the UI and the `!stats` Twitch command.
///
/// Recording only happens while `isEnabled` is `true`. Stats are derived in
/// memory, so they cost zero disk writes.
@MainActor
@Observable
final class ListeningHistoryService {

    // MARK: - Observable State

    /// Whether plays are currently being recorded to disk.
    private(set) var isEnabled: Bool

    /// Every recorded play, oldest first. Loaded from disk on `start()` and
    /// appended to live as tracks change.
    private(set) var records: [PlayRecord] = []

    /// Derived statistics — recomputed whenever `records` changes.
    private(set) var snapshot: StatsSnapshot = .empty

    /// Whether the initial disk load has completed.
    private(set) var isLoaded = false

    // MARK: - Private

    private let store: PlayLogStore

    // MARK: - Init

    /// Creates the service.
    ///
    /// - Parameters:
    ///   - store: Backing play-log store. Defaults to the Application Support log.
    ///   - enabled: Initial enabled state (typically the persisted UserDefaults value).
    init(store: PlayLogStore = PlayLogStore(), enabled: Bool) {
        self.store = store
        self.isEnabled = enabled
    }

    // MARK: - Lifecycle

    /// Loads existing history from disk (off the main thread) if the feature is
    /// enabled. Safe to call once at launch.
    func start() {
        guard isEnabled else { return }
        Task { await loadFromDisk() }
    }

    /// Enables recording and loads any existing history.
    func enable() {
        guard !isEnabled else { return }
        isEnabled = true
        Task { await loadFromDisk() }
        Log.info("ListeningHistoryService: Listening History enabled", category: AppConstants.History.logCategory)
    }

    /// Stops recording. Existing history on disk is left intact.
    func disable() {
        guard isEnabled else { return }
        isEnabled = false
        Log.info("ListeningHistoryService: Listening History disabled", category: AppConstants.History.logCategory)
    }

    /// Flushes buffered writes — call before the app terminates.
    func shutdown() {
        store.flush()
    }

    // MARK: - Recording

    /// Records a finished play if the feature is enabled and the track crossed
    /// the scrobble threshold.
    ///
    /// - Parameters:
    ///   - track: Track title.
    ///   - artist: Artist name.
    ///   - album: Album title.
    ///   - duration: Track length in seconds.
    ///   - playedSeconds: How long the track actually played in seconds.
    func recordTrackChange(
        track: String,
        artist: String,
        album: String,
        duration: TimeInterval,
        playedSeconds: TimeInterval
    ) {
        guard isEnabled else { return }
        let trimmedTrack = track.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTrack.isEmpty else { return }
        guard Self.qualifiesAsPlay(duration: duration, playedSeconds: playedSeconds) else { return }

        let record = PlayRecord(
            track: trimmedTrack,
            artist: artist,
            album: album,
            duration: duration,
            playedSeconds: playedSeconds
        )
        store.append(record)
        records.append(record)
        rebuildSnapshot()
        Log.debug(
            "ListeningHistoryService: Recorded play — \(trimmedTrack) (\(Int(playedSeconds))s)",
            category: AppConstants.History.logCategory
        )
    }

    /// Deletes all recorded history, on disk and in memory.
    func clearHistory() {
        store.clear()
        records = []
        rebuildSnapshot()
        Log.info("ListeningHistoryService: History cleared by user", category: AppConstants.History.logCategory)
    }

    // MARK: - Derived Data

    /// Builds the wrap for the calendar month containing `month`.
    func monthlyWrap(for month: Date = Date()) -> MonthlyWrapData {
        MonthlyWrap.data(from: records, month: month)
    }

    /// A chat-ready one-liner for the `!stats` command.
    ///
    /// Reports today's play count and top track, falling back to a friendly
    /// message when nothing has played yet today.
    func statsChatLine() -> String {
        let snap = snapshot
        guard snap.playsToday > 0 else {
            return "🐺 No plays logged yet today — the music's just getting started!"
        }
        let plays = snap.playsToday == 1 ? "1 play" : "\(snap.playsToday) plays"
        if let top = snap.topTrackToday {
            let times = top.count == 1 ? "1×" : "\(top.count)×"
            let by = top.detail.map { " by \($0)" } ?? ""
            return "🐺 Today: \(plays) · top track \(top.name)\(by) (\(times))"
        }
        return "🐺 Today: \(plays) of music so far"
    }

    // MARK: - Scrobble Rule

    /// Whether a play is long enough to record.
    ///
    /// A play qualifies once it reaches at least half the track's length, or
    /// `scrobbleAbsoluteSeconds` (4 minutes) regardless of length.
    ///
    /// - Parameters:
    ///   - duration: Track length in seconds (0 when unknown).
    ///   - playedSeconds: How long the track played in seconds.
    /// - Returns: `true` if the play should be recorded.
    static func qualifiesAsPlay(duration: TimeInterval, playedSeconds: TimeInterval) -> Bool {
        guard playedSeconds > 0 else { return false }
        if playedSeconds >= AppConstants.History.scrobbleAbsoluteSeconds { return true }
        guard duration > 0 else { return false }
        return playedSeconds >= duration * AppConstants.History.scrobbleFraction
    }

    // MARK: - Private Helpers

    /// Loads history from disk on a background task, applies retention, then
    /// publishes the result on the main actor.
    ///
    /// Internal rather than private so tests can await it directly.
    func loadFromDisk() async {
        let store = self.store
        let retentionDays = Foundation.UserDefaults.standard.integer(
            forKey: AppConstants.UserDefaults.historyRetentionDays
        )
        let loaded = await Task.detached(priority: .utility) { () -> [PlayRecord] in
            let all = store.loadAll()
            guard retentionDays > 0 else { return all }
            let cutoff = Date().addingTimeInterval(-Double(retentionDays) * 86_400)
            let kept = all.filter { $0.timestamp >= cutoff }
            if kept.count != all.count {
                store.replaceAll(with: kept)
            }
            return kept
        }.value

        records = loaded
        isLoaded = true
        rebuildSnapshot()
        Log.info(
            "ListeningHistoryService: Loaded \(loaded.count) plays from disk",
            category: AppConstants.History.logCategory
        )
    }

    /// Recomputes `snapshot` from the current `records`.
    private func rebuildSnapshot() {
        snapshot = StatsAggregator.snapshot(from: records)
    }
}
