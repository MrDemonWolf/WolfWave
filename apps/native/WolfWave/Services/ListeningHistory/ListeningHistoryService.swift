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
    private let clearMarkerStore: HistoryClearMarkerStore

    /// While true, the durable clear tombstone remains and no new record may be
    /// appended: recovery would intentionally delete anything written behind it.
    private var clearIsPending: Bool

    /// Lifetime tally of trimmed plays. Merged into every snapshot so
    /// totals/top-N stay accurate after the rolling window evicts records.
    private var lifetime: LifetimeTally = .empty

    /// Set to `true` when `records` has been mutated past the cap but the
    /// NDJSON file has not yet been compacted. Drives `shutdown()` rewrite.
    private var needsCompaction = false

    /// The in-memory lifetime high-water mark has not yet been saved. A tally
    /// save must succeed before compaction may remove its source NDJSON lines.
    private var needsTallyPersistence = false

    /// Sequence assigned to the next live record. Disk load establishes this
    /// before buffered plays are appended, avoiding collisions across launches.
    private var nextSequence: UInt64 = 1

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
    /// Invalidates disk-load results captured before a user clear. The detached
    /// reader is side-effect free; only a matching generation may publish.
    private var historyGeneration = 0

    /// Deterministic test seam invoked by the detached loader immediately after
    /// its disk read. Production leaves it nil.
    private let loadReadBarrier: (@Sendable () -> Void)?

    // MARK: - Init

    /// Creates the service.
    ///
    /// - Parameters:
    ///   - store: Backing play-log store. Defaults to the Application Support log.
    ///   - tallyStore: Lifetime tally store. Defaults to the Application Support sidecar.
    ///   - clearMarkerStore: Durable cross-store clear marker. Tests may inject
    ///     failure behavior; production derives it from the play-log directory.
    ///   - enabled: Initial enabled state (typically the persisted UserDefaults value).
    ///   - loadReadBarrier: Test-only hook after the detached disk read.
    init(
        store: PlayLogStore = PlayLogStore(),
        tallyStore: LifetimeTallyStore = LifetimeTallyStore(),
        clearMarkerStore: HistoryClearMarkerStore? = nil,
        enabled: Bool,
        loadReadBarrier: (@Sendable () -> Void)? = nil
    ) {
        let markerStore = clearMarkerStore ?? HistoryClearMarkerStore(
            directory: store.fileURL.deletingLastPathComponent())
        self.store = store
        self.tallyStore = tallyStore
        self.clearMarkerStore = markerStore
        self.clearIsPending = markerStore.isPending
        self.isEnabled = enabled
        self.loadReadBarrier = loadReadBarrier
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
        Log.info("ListeningHistoryService: Listening History enabled", category: .history)
    }

    /// Spawns `loadFromDisk()` unless a load is already in flight, so overlapping
    /// callers (a rapid disable→enable toggle, or `start()` racing `enable()`)
    /// share one load. Two concurrent loads could interleave the shared play-log
    /// and tally stores and re-fold overflow or drop a deferred play.
    private func scheduleLoad() {
        guard loadTask == nil else { return }
        // Claim load ownership before spawning the task. A track callback can
        // run immediately after start()/enable() returns and must be buffered.
        isLoading = true
        let generation = historyGeneration
        loadTask = Task { [weak self] in
            await self?.loadFromDisk(generation: generation)
            self?.loadTask = nil
        }
    }

    /// Stops recording. Existing history on disk is left intact.
    func disable() {
        guard isEnabled else { return }
        isEnabled = false
        Log.info("ListeningHistoryService: Listening History disabled", category: .history)
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
        guard completePendingClear() else {
            store.flush()
            return
        }
        if isLoading {
            // The loader owns qualified plays only in `deferredDuringLoad`.
            // Invalidate its eventual result, reconstruct the disk watermark,
            // append those plays synchronously via flush, and leave the full
            // NDJSON untouched for next-launch normalization/compaction.
            historyGeneration &+= 1
            loadTask?.cancel()
            loadTask = nil
            isLoading = false
            establishNextSequenceFromDisk()
            let buffered = deferredDuringLoad
            deferredDuringLoad.removeAll()
            for record in buffered {
                appendRecord(record)
            }
            store.flush()
            return
        }

        let preserveLifetime = usesLifetimeTally
        var tallyIsDurable = true
        if preserveLifetime {
            if needsCompaction || needsTallyPersistence {
                tallyIsDurable = tallyStore.save(lifetime)
            }
        } else {
            lifetime = .empty
            tallyIsDurable = tallyStore.clear()
        }
        if tallyIsDurable {
            needsTallyPersistence = false
        } else {
            needsTallyPersistence = true
        }
        if needsCompaction, tallyIsDurable {
            needsCompaction = !store.replaceAll(with: records)
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
        let safeDuration = DurationSanitizer.clampFiniteSeconds(duration)
        let safePlayedSeconds = DurationSanitizer.clampFiniteSeconds(playedSeconds)
        guard Self.qualifiesAsPlay(
            duration: safeDuration,
            playedSeconds: safePlayedSeconds
        ) else { return }
        guard completePendingClear() else {
            Log.warn(
                "ListeningHistoryService: Play not recorded while history clear is pending",
                category: .history)
            return
        }

        let record = PlayRecord(
            track: trimmedTrack,
            artist: artist,
            album: album,
            duration: safeDuration,
            playedSeconds: safePlayedSeconds
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
    private func appendRecord(_ pendingRecord: PlayRecord) {
        let record = recordWithSequence(pendingRecord)
        store.append(record)
        records.append(record)
        let preserveLifetime = usesLifetimeTally
        if !preserveLifetime, !lifetime.isEmpty {
            lifetime = .empty
            needsTallyPersistence = !tallyStore.clear()
        }

        let cap = AppConstants.History.maxRetainedRecords
        if records.count > cap {
            let overflow = records.count - cap
            let evicted = Array(records.prefix(overflow))
            records.removeFirst(overflow)
            if preserveLifetime {
                lifetime.fold(evicted)
                needsTallyPersistence = true
                // Keep the full sidecar rewrite off the recording hot path.
                // Until shutdown compacts the log, NDJSON still contains these
                // plays so an unclean-exit reload can recover the tally.
            }
            needsCompaction = true
        }

        rebuildSnapshot()
        Log.debug(
            "ListeningHistoryService: Recorded play: \(record.track) (\(Int(record.playedSeconds))s)",
            category: .history
        )
    }

    /// Deletes all recorded history, on disk and in memory.
    ///
    /// - Returns: `true` only when the clear marker, play log, and lifetime
    ///   tally have all reached their durable final state.
    @discardableResult
    func clearHistory() -> Bool {
        // The marker must exist before either data store is mutated. If it
        // cannot be persisted, leave both disk and UI state untouched.
        guard clearMarkerStore.begin() else {
            Log.error(
                "ListeningHistoryService: Could not persist history clear intent",
                category: .history)
            return false
        }

        clearIsPending = true
        historyGeneration &+= 1
        // Buffered plays accumulated before the clear belong to old history.
        deferredDuringLoad.removeAll()
        records = []
        lifetime = .empty
        needsCompaction = false
        needsTallyPersistence = false
        nextSequence = 1
        isLoaded = true
        rebuildSnapshot()

        let completed = completePendingClear()
        if completed {
            Log.info(
                "ListeningHistoryService: History cleared by user",
                category: .history)
        } else {
            Log.error(
                "ListeningHistoryService: History clear pending durable retry",
                category: .history)
        }
        return completed
    }

    /// Replays a persisted clear intent. No caller may append while this returns
    /// false, because a later recovery intentionally empties both data stores.
    @discardableResult
    private func completePendingClear() -> Bool {
        guard clearIsPending else { return true }
        clearIsPending = true
        let logCleared = store.clear()
        let tallyCleared = tallyStore.clear()
        guard logCleared, tallyCleared else { return false }
        guard clearMarkerStore.complete() else { return false }
        clearIsPending = false
        return true
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

        let summary = StatsAggregator.windowSummary(
            from: records, since: since,
            lifetime: usesLifetimeTally ? lifetime : .empty)
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
        if let loadTask {
            await loadTask.value
            return
        }
        isLoading = true
        await loadFromDisk(generation: historyGeneration)
    }

    /// Performs one load owned by `generation`. `scheduleLoad()` passes the
    /// generation captured before its task is spawned so a same-turn clear can
    /// invalidate work that has not begun executing yet.
    private func loadFromDisk(generation: Int) async {
        let store = self.store
        let tallyStore = self.tallyStore
        let clearMarkerStore = self.clearMarkerStore
        let loadReadBarrier = self.loadReadBarrier
        let retentionDays = DefaultsStore.store.integer(
            forKey: AppConstants.UserDefaults.historyRetentionDays
        )
        let cap = AppConstants.History.maxRetainedRecords

        struct LoadResult: Sendable {
            let records: [PlayRecord]
            let tally: LifetimeTally
            let retentionExpiredCount: Int
            let foldedCount: Int
            let shouldRewrite: Bool
            let shouldClearTally: Bool
            let shouldSaveTally: Bool
            let nextSequence: UInt64
            let clearRecoveryPending: Bool
        }

        let result = await Task.detached(priority: .utility) { () -> LoadResult in
            let preserveLifetime = retentionDays <= 0
            if clearMarkerStore.isPending {
                let logCleared = store.clear()
                let tallyCleared = tallyStore.clear()
                let completed = logCleared && tallyCleared
                    && clearMarkerStore.complete()
                guard completed else {
                    return LoadResult(
                        records: [], tally: .empty,
                        retentionExpiredCount: 0, foldedCount: 0,
                        shouldRewrite: false, shouldClearTally: false,
                        shouldSaveTally: false, nextSequence: 1,
                        clearRecoveryPending: true)
                }
            }
            var all = store.loadAll()
            var tally = preserveLifetime ? tallyStore.load() : .empty
            loadReadBarrier?()
            var shouldRewrite = false
            var shouldSaveTally = false
            var retentionExpiredCount = 0

            // Normalize legacy/malformed sequence values deterministically from
            // file order alone. This must not depend on the persisted tally:
            // when a tally save succeeds but the matching log rewrite fails,
            // the same source lines must receive the same sequences next launch
            // so the tally high-water mark prevents a second fold.
            var previousSequence: UInt64 = 0
            for index in all.indices {
                if let sequence = all[index].sequence,
                   sequence > previousSequence {
                    previousSequence = sequence
                } else if previousSequence < UInt64.max {
                    previousSequence += 1
                    all[index] = all[index].assigningSequence(previousSequence)
                    shouldRewrite = true
                }
            }
            let highestSequence = Swift.max(
                previousSequence, tally.lastFoldedSequence ?? 0)

            // 1. Day-based retention (existing behavior. These records are
            //    *expired* by the user's setting, so they're dropped, NOT
            //    folded into the lifetime tally).
            if retentionDays > 0 {
                let cutoff = Date().addingTimeInterval(-Double(retentionDays) * 86_400)
                let kept = all.filter { $0.timestamp >= cutoff }
                if kept.count != all.count {
                    retentionExpiredCount = all.count - kept.count
                    all = kept
                    shouldRewrite = true
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
            var foldedCount = 0
            let overflow = Swift.max(0, all.count - cap)
            let evicted = Array(all.prefix(overflow))

            // Legacy tallies used timestamps as their crash-recovery marker.
            // Translate that one time into the sequence boundary represented by
            // the currently-evicted prefix. Future equal-timestamp records are
            // then distinguished exactly by sequence.
            if preserveLifetime,
               tally.lastFoldedSequence == nil,
               (!tally.isEmpty || tally.lastFoldedTimestamp != nil) {
                let baseline: UInt64
                if let firstSequence = all.first?.sequence {
                    baseline = firstSequence > 0 ? firstSequence - 1 : 0
                } else {
                    baseline = highestSequence
                }
                var migratedMark = baseline
                if let timestampMark = tally.lastFoldedTimestamp {
                    for record in evicted {
                        guard record.timestamp <= timestampMark else { break }
                        migratedMark = record.sequence ?? migratedMark
                    }
                }
                tally.lastFoldedSequence = migratedMark
                shouldSaveTally = true
            }

            if all.count > cap {
                all.removeFirst(overflow)
                if preserveLifetime {
                    let mark = tally.lastFoldedSequence ?? 0
                    let toFold = evicted.filter { ($0.sequence ?? 0) > mark }
                    tally.fold(toFold)
                    foldedCount = toFold.count
                    shouldSaveTally = shouldSaveTally || !toFold.isEmpty
                }
                shouldRewrite = true
            }

            let nextSequence = highestSequence < UInt64.max
                ? highestSequence + 1
                : UInt64.max

            return LoadResult(
                records: all, tally: tally,
                retentionExpiredCount: retentionExpiredCount,
                foldedCount: foldedCount,
                shouldRewrite: shouldRewrite,
                shouldClearTally: !preserveLifetime,
                shouldSaveTally: preserveLifetime && shouldSaveTally,
                nextSequence: nextSequence,
                clearRecoveryPending: false)
        }.value

        guard generation == historyGeneration else {
            // A user clear won while the detached read was suspended. Never
            // publish or persist the stale result; only flush post-clear plays.
            isLoaded = true
            finishLoading()
            Log.info(
                "ListeningHistoryService: Discarded stale disk load after history clear",
                category: .history)
            return
        }

        if result.clearRecoveryPending {
            records = []
            lifetime = .empty
            nextSequence = 1
            isLoaded = true
            needsCompaction = false
            needsTallyPersistence = false
            if completePendingClear() {
                finishLoading()
            } else {
                // Records captured while deletion is unresolved cannot be
                // appended behind the tombstone; recovery would erase them.
                deferredDuringLoad.removeAll()
                isLoading = false
                rebuildSnapshot()
            }
            Log.error(
                "ListeningHistoryService: History clear still pending after launch recovery",
                category: .history)
            return
        }
        clearIsPending = false

        var tallyIsDurable = true
        if result.shouldClearTally {
            tallyIsDurable = tallyStore.clear()
        } else if result.shouldSaveTally {
            tallyIsDurable = tallyStore.save(result.tally)
        }
        var rewriteSucceeded = !result.shouldRewrite
        if result.shouldRewrite, tallyIsDurable {
            rewriteSucceeded = store.replaceAll(with: result.records)
        }
        records = result.records
        lifetime = result.tally
        nextSequence = result.nextSequence
        isLoaded = true
        needsTallyPersistence = (result.shouldClearTally || result.shouldSaveTally)
            && !tallyIsDurable
        needsCompaction = result.shouldRewrite && !rewriteSucceeded
        finishLoading()

        if result.foldedCount > 0 {
            Log.info(
                "ListeningHistoryService: Folded \(result.foldedCount) old plays into lifetime tally (cap \(cap))",
                category: .history
            )
        }
        if result.retentionExpiredCount > 0 {
            Log.info(
                "ListeningHistoryService: Expired \(result.retentionExpiredCount) plays under finite retention",
                category: .history
            )
        }
        Log.info(
            "ListeningHistoryService: Loaded \(result.records.count) plays from disk",
            category: .history
        )
    }

    /// Ends load mode and flushes records captured while the disk read was in
    /// flight, preserving their arrival order.
    private func finishLoading() {
        // No await separates clearing the flag, taking the buffer, and appending
        // it, so a live record cannot interleave with this ordered flush.
        isLoading = false
        let buffered = deferredDuringLoad
        deferredDuringLoad.removeAll()
        for record in buffered {
            appendRecord(record)
        }
        rebuildSnapshot()
    }

    /// Assigns a sequence at the last responsible moment, after initial disk
    /// state is known. Existing sequenced records are preserved.
    private func recordWithSequence(_ record: PlayRecord) -> PlayRecord {
        if let sequence = record.sequence {
            if sequence >= nextSequence, sequence < UInt64.max {
                nextSequence = sequence + 1
            }
            return record
        }
        let sequenced = record.assigningSequence(nextSequence)
        if nextSequence < UInt64.max {
            nextSequence += 1
        }
        return sequenced
    }

    /// Reconstructs the next sequence without rewriting legacy disk records.
    /// The virtual repair follows the same file-order-only rule as disk load so
    /// deferred shutdown appends remain above the sequence migration will assign.
    private func establishNextSequenceFromDisk() {
        var previousSequence: UInt64 = 0
        for record in store.loadAll() {
            if let sequence = record.sequence, sequence > previousSequence {
                previousSequence = sequence
            } else if previousSequence < UInt64.max {
                previousSequence += 1
            }
        }
        let highWater = Swift.max(
            previousSequence,
            tallyStore.load().lastFoldedSequence ?? 0)
        nextSequence = highWater < UInt64.max ? highWater + 1 : UInt64.max
    }

    /// Recomputes the snapshot, excluding the undated lifetime sidecar whenever
    /// finite retention is active.
    private func rebuildSnapshot() {
        snapshot = StatsAggregator.snapshot(
            from: records,
            lifetime: usesLifetimeTally ? lifetime : .empty)
    }

    /// Finite retention intentionally reports only retained records. The
    /// lifetime sidecar has no per-play dates, so merging it would resurrect
    /// plays outside the user's chosen retention window.
    private var usesLifetimeTally: Bool {
        DefaultsStore.store.integer(
            forKey: AppConstants.UserDefaults.historyRetentionDays) <= 0
    }
}
