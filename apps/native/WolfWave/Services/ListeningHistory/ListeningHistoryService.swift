//
//  ListeningHistoryService.swift
//  WolfWave
//
//  Created by Nathanial Henniges on 2026-05-22.
//  Copyright © 2026 MrDemonWolf, Inc. All rights reserved.
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

    /// Derived statistics, recomputed whenever `records` changes.
    private(set) var snapshot: StatsSnapshot = .empty

    /// Whether the initial disk load has completed.
    private(set) var isLoaded = false

    // MARK: - Private

    private let store: PlayLogStore
    private let tallyStore: LifetimeTallyStore

    /// Lifetime tally of trimmed plays. Merged into every snapshot so
    /// totals/top-N stay accurate after the rolling window evicts records.
    private var lifetime: LifetimeTally = .empty

    /// Set to `true` when `records` has been mutated past the cap but the
    /// NDJSON file has not yet been compacted. Drives `shutdown()` rewrite.
    private var needsCompaction = false

    /// `true` while `loadFromDisk()` is awaiting its background read. Plays that
    /// arrive in this window are buffered (see `deferredDuringLoad`) instead of
    /// written, because the load overwrites `records` and a concurrent
    /// `replaceAll` could clobber the disk append.
    private var isLoading = false

    /// Plays recorded while a disk load was in flight. Flushed in order once
    /// `loadFromDisk()` finishes so a track played mid-load isn't dropped.
    private var deferredDuringLoad: [PlayRecord] = []

    /// The in-flight load, if any. Set synchronously in `scheduleLoad()` before
    /// the task is spawned so a rapid disable→enable toggle coalesces onto the
    /// single running load instead of starting a second one that would interleave
    /// the shared stores and re-fold overflow.
    private var loadTask: Task<Void, Never>?

    // MARK: - Init

    /// Creates the service.
    ///
    /// - Parameters:
    ///   - store: Backing play-log store. Defaults to the Application Support log.
    ///   - tallyStore: Lifetime tally store. Defaults to the Application Support sidecar.
    ///   - enabled: Initial enabled state (typically the persisted UserDefaults value).
    init(
        store: PlayLogStore = PlayLogStore(),
        tallyStore: LifetimeTallyStore = LifetimeTallyStore(),
        enabled: Bool
    ) {
        self.store = store
        self.tallyStore = tallyStore
        self.isEnabled = enabled
    }

    // MARK: - Lifecycle

    /// Loads existing history from disk (off the main thread) if the feature is
    /// enabled. Safe to call once at launch.
    func start() {
        guard isEnabled else { return }
        scheduleLoad()
    }

    /// Enables recording and loads any existing history.
    func enable() {
        guard !isEnabled else { return }
        isEnabled = true
        scheduleLoad()
        Log.info("ListeningHistoryService: Listening History enabled", category: AppConstants.History.logCategory)
    }

    /// Spawns `loadFromDisk()` unless a load is already in flight, so overlapping
    /// callers (a rapid disable→enable toggle, or `start()` racing `enable()`)
    /// share one load. Two concurrent loads could interleave the shared play-log
    /// and tally stores and re-fold overflow or drop a deferred play.
    private func scheduleLoad() {
        guard loadTask == nil else { return }
        loadTask = Task { [weak self] in
            await self?.loadFromDisk()
            self?.loadTask = nil
        }
    }

    /// Stops recording. Existing history on disk is left intact.
    func disable() {
        guard isEnabled else { return }
        isEnabled = false
        Log.info("ListeningHistoryService: Listening History disabled", category: AppConstants.History.logCategory)
    }

    /// Flushes buffered writes. Call before the app terminates.
    ///
    /// If the in-memory window has overflowed during this session, the play
    /// log is compacted to the live records here so the next launch starts
    /// from a normalized file. The lifetime tally is also persisted.
    ///
    /// Both writes run **synchronously** so they're guaranteed to complete
    /// before `applicationWillTerminate` returns and the process exits, a
    /// detached `Task` would be racing termination.
    func shutdown() {
        if needsCompaction {
            store.replaceAll(with: records)
            tallyStore.save(lifetime)
            needsCompaction = false
        }
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

        // A disk load is awaiting its background read. Buffer the play; it would
        // otherwise be overwritten when loadFromDisk assigns `records`, and a
        // concurrent replaceAll could drop the disk append too. Flushed in order
        // by loadFromDisk once the load completes.
        guard !isLoading else {
            deferredDuringLoad.append(record)
            return
        }

        appendRecord(record)
    }

    /// Appends one already-validated play to disk + the in-memory window and
    /// enforces the rolling-window cap. The hot path stays append-only; NDJSON
    /// compaction is deferred to `shutdown()`.
    private func appendRecord(_ record: PlayRecord) {
        store.append(record)
        records.append(record)

        let cap = AppConstants.History.maxRetainedRecords
        if records.count > cap {
            let overflow = records.count - cap
            let evicted = Array(records.prefix(overflow))
            records.removeFirst(overflow)
            lifetime.fold(evicted)
            tallyStore.save(lifetime)
            needsCompaction = true
        }

        rebuildSnapshot()
        Log.debug(
            "ListeningHistoryService: Recorded play: \(record.track) (\(Int(record.playedSeconds))s)",
            category: AppConstants.History.logCategory
        )
    }

    /// Deletes all recorded history, on disk and in memory.
    func clearHistory() {
        store.clear()
        tallyStore.clear()
        records = []
        lifetime = .empty
        needsCompaction = false
        rebuildSnapshot()
        Log.info("ListeningHistoryService: History cleared by user", category: AppConstants.History.logCategory)
    }

    // MARK: - Derived Data

    /// Builds the wrap for the calendar month containing `month`.
    func monthlyWrap(for month: Date = Date()) -> MonthlyWrapData {
        MonthlyWrap.data(from: records, month: month)
    }

    /// First day of the earliest month containing a recorded play.
    /// `nil` when no plays have been recorded yet.
    var earliestRecordedMonth: Date? {
        guard let earliest = records.map(\.timestamp).min() else { return nil }
        return Calendar.current.dateInterval(of: .month, for: earliest)?.start
    }

    /// A chat-ready one-liner for the `!stats` command.
    ///
    /// Reports the selected `parts` over the selected `window`, falling back to a
    /// friendly message when nothing played in that window. The streamer
    /// configures `window` and `parts` in **Settings → History & Stats**.
    ///
    /// - Parameters:
    ///   - window: The time slice to report over. Defaults to ``StatsWindow/today``.
    ///   - parts: The facts to include, in any order (rendered in canonical order).
    ///     Defaults to ``StatsPart/defaults``.
    ///   - sessionStart: When the current stream went live. Used by
    ///     ``StatsWindow/session``; when `nil` that window falls back to today.
    ///   - now: Reference "now" for window bounds. Injectable for tests.
    ///   - calendar: Calendar for day bucketing. Injectable for tests.
    /// - Returns: The chat line, prefixed with the 🐺 mark.
    func statsChatLine(
        window: StatsWindow = .default,
        parts: [StatsPart] = StatsPart.defaults,
        sessionStart: Date? = nil,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> String {
        // "This stream" needs a live anchor; without one, behave like "today".
        let effectiveWindow: StatsWindow = (window == .session && sessionStart == nil) ? .today : window
        let label = effectiveWindow.chatLabel

        let since: Date?
        switch effectiveWindow {
        case .today:
            since = calendar.startOfDay(for: now)
        case .session:
            since = sessionStart
        case .week:
            let startOfToday = calendar.startOfDay(for: now)
            since = calendar.date(byAdding: .day, value: -6, to: startOfToday) ?? startOfToday
        case .allTime:
            since = nil
        }

        let summary = StatsAggregator.windowSummary(from: records, since: since, lifetime: lifetime)
        return StatsChatLine.render(label: label, summary: summary, parts: parts)
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

    /// Loads history from disk on a background task, applies retention and the
    /// rolling-window cap (folding evicted records into the lifetime tally),
    /// then publishes the result on the main actor.
    ///
    /// Internal rather than private so tests can await it directly.
    func loadFromDisk() async {
        // Set synchronously before the first await so any play recorded during
        // the background read is buffered, not lost to the `records` assignment.
        isLoading = true
        let store = self.store
        let tallyStore = self.tallyStore
        let retentionDays = Foundation.UserDefaults.standard.integer(
            forKey: AppConstants.UserDefaults.historyRetentionDays
        )
        let cap = AppConstants.History.maxRetainedRecords

        struct LoadResult {
            let records: [PlayRecord]
            let tally: LifetimeTally
            let trimmedCount: Int
        }

        let result = await Task.detached(priority: .utility) { () -> LoadResult in
            var tally = tallyStore.load()
            var all = store.loadAll()
            var rewrote = false

            // 1. Day-based retention (existing behavior. These records are
            //    *expired* by the user's setting, so they're dropped, NOT
            //    folded into the lifetime tally).
            if retentionDays > 0 {
                let cutoff = Date().addingTimeInterval(-Double(retentionDays) * 86_400)
                let kept = all.filter { $0.timestamp >= cutoff }
                if kept.count != all.count {
                    all = kept
                    rewrote = true
                }
            }

            // 2. Rolling-window cap. Fold the oldest overflow into the tally.
            //    Only fold records newer than the tally's high-water mark: after
            //    a clean shutdown the NDJSON was compacted so the overflow is all
            //    genuinely new, but after an unclean exit (crash / Force Quit /
            //    kill) the NDJSON can still hold records already folded into the
            //    persisted tally. Re-folding those would double-count lifetime
            //    stats, so skip anything at or before the mark while still
            //    trimming it out of the in-memory window (and off disk below).
            var trimmedCount = 0
            if all.count > cap {
                let overflow = all.count - cap
                let evicted = Array(all.prefix(overflow))
                all.removeFirst(overflow)
                let mark = tally.lastFoldedTimestamp ?? .distantPast
                let toFold = evicted.filter { $0.timestamp > mark }
                if !toFold.isEmpty {
                    tally.fold(toFold)
                    tallyStore.save(tally)
                }
                trimmedCount = toFold.count
                rewrote = true
            }

            if rewrote {
                store.replaceAll(with: all)
            }
            return LoadResult(records: all, tally: tally, trimmedCount: trimmedCount)
        }.value

        records = result.records
        lifetime = result.tally
        isLoaded = true
        needsCompaction = false

        // Flush plays recorded while the load was in flight, in arrival order.
        // No await separates this from the assignment above, so recordTrackChange
        // cannot interleave between them.
        isLoading = false
        let buffered = deferredDuringLoad
        deferredDuringLoad = []
        for record in buffered { appendRecord(record) }

        rebuildSnapshot()
        if result.trimmedCount > 0 {
            Log.info(
                "ListeningHistoryService: Trimmed \(result.trimmedCount) old plays into lifetime tally (cap \(cap))",
                category: AppConstants.History.logCategory
            )
        }
        Log.info(
            "ListeningHistoryService: Loaded \(result.records.count) plays from disk",
            category: AppConstants.History.logCategory
        )
    }

    /// Recomputes `snapshot` from the current `records` plus the persisted
    /// `lifetime` tally so totals/top-N remain correct after trimming.
    private func rebuildSnapshot() {
        snapshot = StatsAggregator.snapshot(from: records, lifetime: lifetime)
    }
}
