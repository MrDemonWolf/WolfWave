//
//  ListeningHistoryServiceTests.swift
//  WolfWave
//
//  Created by Nathanial Henniges on 2026-05-22.
//  Copyright © 2026 MrDemonWolf, Inc. All rights reserved.
//

import Testing
import Foundation
@testable import WolfWave

/// Blocks the detached disk loader after it has captured its inputs, allowing a
/// test to perform a clear before the stale result can return to the main actor.
private final class HistoryLoadBarrier: @unchecked Sendable {
    private let reached = DispatchSemaphore(value: 0)
    private let releaseSignal = DispatchSemaphore(value: 0)
    private let releaseLock = NSLock()
    private var wasReleased = false

    func blockAfterRead() {
        reached.signal()
        _ = releaseSignal.wait(timeout: .now() + .seconds(5))
    }

    func waitUntilBlocked(
        timeout: DispatchTimeInterval = .seconds(2)
    ) async -> Bool {
        await Task.detached {
            self.reached.wait(timeout: .now() + timeout) == .success
        }.value
    }

    func release() {
        let shouldSignal = releaseLock.withLock {
            guard !wasReleased else { return false }
            wasReleased = true
            return true
        }
        if shouldSignal {
            releaseSignal.signal()
        }
    }
}

/// Fails the first sidecar deletion, then performs the real deletion. This
/// proves finite-retention compaction retries instead of dropping source lines.
private final class FailOnceTallyClear: @unchecked Sendable {
    private let lock = NSLock()
    private let fileURL: URL
    private(set) var attempts = 0

    init(fileURL: URL) {
        self.fileURL = fileURL
    }

    func clear() -> Bool {
        lock.withLock {
            attempts += 1
            guard attempts > 1 else { return false }
            guard FileManager.default.fileExists(atPath: fileURL.path) else {
                return true
            }
            do {
                try FileManager.default.removeItem(at: fileURL)
                return true
            } catch {
                return false
            }
        }
    }
}

/// Tests for the listening-history orchestrator: scrobble threshold, gating,
/// recording, clearing, and the disk-load path.
@Suite("Listening History Service Tests", .serialized)
@MainActor
struct ListeningHistoryServiceTests {

    // MARK: - Helpers

    private func makeTempDirectory() -> URL {
        makeIsolatedTempDirectory(prefix: "history-svc-test")
    }

    private func makeService(
        enabled: Bool,
        directory: URL,
        loadReadBarrier: (@Sendable () -> Void)? = nil
    ) -> ListeningHistoryService {
        ListeningHistoryService(
            store: PlayLogStore(directory: directory),
            tallyStore: LifetimeTallyStore(directory: directory),
            enabled: enabled,
            loadReadBarrier: loadReadBarrier
        )
    }

    private func seedClearFixture(
        directory: URL
    ) -> (log: PlayLogStore, tally: LifetimeTallyStore) {
        let log = PlayLogStore(directory: directory)
        _ = log.replaceAll(with: [
            PlayRecord(
                track: "On Disk", artist: "Wolf", album: "",
                duration: 200, playedSeconds: 200, sequence: 1)
        ])
        var lifetime = LifetimeTally.empty
        lifetime.fold(PlayRecord(
            timestamp: Date().addingTimeInterval(-3_600),
            track: "Folded", artist: "Wolf", album: "",
            duration: 200, playedSeconds: 200, sequence: 0))
        let tally = LifetimeTallyStore(directory: directory)
        _ = tally.save(lifetime)
        return (log, tally)
    }

    // MARK: - Earliest Recorded Month
    @Test("earliestRecordedMonth is nil when no plays have been recorded")
    func testEarliestRecordedMonthNilWhenEmpty() {
        let dir = makeTempDirectory()
        let service = makeService(enabled: true, directory: dir)
        #expect(service.earliestRecordedMonth == nil)
        try? FileManager.default.removeItem(at: dir)
    }

    @Test("earliestRecordedMonth returns first-of-month for the oldest record")
    func testEarliestRecordedMonthReturnsFirstOfOldestMonth() {
        let dir = makeTempDirectory()
        let service = makeService(enabled: true, directory: dir)

        // Record a play "now" (current month).
        service.recordTrackChange(
            track: "Recent", artist: "A", album: "",
            duration: 200, playedSeconds: 188
        )

        guard let earliest = service.earliestRecordedMonth else {
            Issue.record("Expected earliestRecordedMonth after a play")
            try? FileManager.default.removeItem(at: dir)
            return
        }

        let cal = Calendar.current
        let expected = cal.dateInterval(of: .month, for: Date())?.start
        #expect(earliest == expected)
        // Always the first day of the month.
        #expect(cal.component(.day, from: earliest) == 1)
        try? FileManager.default.removeItem(at: dir)
    }

    @Test("earliestRecordedMonth uses the minimum timestamp, not insertion order")
    func testEarliestRecordedMonthIgnoresInsertionOrder() {
        let dir = makeTempDirectory()
        let service = makeService(enabled: true, directory: dir)

        // Insert recent first, older second. Earliest should still be the older one.
        service.recordTrackChange(
            track: "Recent", artist: "A", album: "",
            duration: 200, playedSeconds: 188
        )
        service.recordTrackChange(
            track: "AlsoRecent", artist: "B", album: "",
            duration: 200, playedSeconds: 188
        )

        // Both fall in the current month. Earliest should be start-of-current-month.
        let cal = Calendar.current
        let expected = cal.dateInterval(of: .month, for: Date())?.start
        #expect(service.earliestRecordedMonth == expected)
        try? FileManager.default.removeItem(at: dir)
    }

    // MARK: - Scrobble Threshold

    @Test("A track played past 50% qualifies")
    func testQualifiesAtHalf() {
        #expect(ListeningHistoryService.qualifiesAsPlay(duration: 200, playedSeconds: 100))
        #expect(ListeningHistoryService.qualifiesAsPlay(duration: 200, playedSeconds: 199))
    }

    @Test("A track played under 50% does not qualify")
    func testRejectedUnderHalf() {
        #expect(!ListeningHistoryService.qualifiesAsPlay(duration: 200, playedSeconds: 99))
        #expect(!ListeningHistoryService.qualifiesAsPlay(duration: 200, playedSeconds: 5))
    }

    @Test("Four minutes always qualifies regardless of track length")
    func testAbsoluteThreshold() {
        // A 20-minute track played for 4 minutes is < 50% but still counts.
        #expect(ListeningHistoryService.qualifiesAsPlay(duration: 1200, playedSeconds: 240))
        // Unknown duration: only the absolute threshold can qualify it.
        #expect(ListeningHistoryService.qualifiesAsPlay(duration: 0, playedSeconds: 240))
        #expect(!ListeningHistoryService.qualifiesAsPlay(duration: 0, playedSeconds: 100))
    }

    @Test("Zero play time never qualifies")
    func testZeroPlayRejected() {
        #expect(!ListeningHistoryService.qualifiesAsPlay(duration: 200, playedSeconds: 0))
    }

    // MARK: - Recording & Gating

    @Test("A qualifying play is recorded when enabled")
    func testRecordsQualifyingPlay() {
        let dir = makeTempDirectory()
        let service = makeService(enabled: true, directory: dir)

        service.recordTrackChange(
            track: "Blinding Lights", artist: "The Weeknd", album: "After Hours",
            duration: 200, playedSeconds: 188
        )

        #expect(service.records.count == 1)
        #expect(service.snapshot.totalPlays == 1)
        try? FileManager.default.removeItem(at: dir)
    }

    @Test("A short play is dropped")
    func testDropsShortPlay() {
        let dir = makeTempDirectory()
        let service = makeService(enabled: true, directory: dir)

        service.recordTrackChange(
            track: "Skipped", artist: "Someone", album: "",
            duration: 200, playedSeconds: 8
        )

        #expect(service.records.isEmpty)
        try? FileManager.default.removeItem(at: dir)
    }

    @Test("Nothing is recorded while the feature is disabled")
    func testGatingWhenDisabled() {
        let dir = makeTempDirectory()
        let service = makeService(enabled: false, directory: dir)

        service.recordTrackChange(
            track: "Ignored", artist: "Nobody", album: "",
            duration: 200, playedSeconds: 200
        )

        #expect(service.records.isEmpty)
        // Nothing should have been written to disk either.
        #expect(PlayLogStore(directory: dir).loadAll().isEmpty)
        try? FileManager.default.removeItem(at: dir)
    }

    @Test("An empty track title is ignored")
    func testEmptyTrackIgnored() {
        let dir = makeTempDirectory()
        let service = makeService(enabled: true, directory: dir)

        service.recordTrackChange(
            track: "   ", artist: "The Weeknd", album: "",
            duration: 200, playedSeconds: 200
        )

        #expect(service.records.isEmpty)
        try? FileManager.default.removeItem(at: dir)
    }

    @Test("Live record boundary sanitizes non-finite and huge durations")
    func testLiveDurationBoundarySanitizesBeforeQualificationAndLogging() {
        let dir = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let service = makeService(enabled: true, directory: dir)
        let invalid: [Double] = [.nan, .infinity, -.infinity]

        for (index, played) in invalid.enumerated() {
            service.recordTrackChange(
                track: "Invalid Played \(index)", artist: "Wolf", album: "",
                duration: 200, playedSeconds: played)
        }
        #expect(service.records.isEmpty)

        for (index, duration) in invalid.enumerated() {
            service.recordTrackChange(
                track: "Unknown Duration \(index)", artist: "Wolf", album: "",
                duration: duration, playedSeconds: 240)
        }
        #expect(service.records.count == invalid.count)
        #expect(service.records.allSatisfy { $0.duration == 0 })
        #expect(service.records.allSatisfy { $0.playedSeconds == 240 })

        service.recordTrackChange(
            track: "Huge", artist: "Wolf", album: "",
            duration: 1.0e300, playedSeconds: 1.0e300)

        let huge = service.records.last
        #expect(huge?.duration == DurationSanitizer.ceiling)
        #expect(huge?.playedSeconds == DurationSanitizer.ceiling)
        #expect(service.records.allSatisfy {
            $0.duration.isFinite && $0.playedSeconds.isFinite
        })
    }

    // MARK: - Clear

    @Test("clearHistory empties records and snapshot")
    func testClearHistory() {
        let dir = makeTempDirectory()
        let service = makeService(enabled: true, directory: dir)
        service.recordTrackChange(
            track: "Doomed", artist: "Bring Me the Horizon", album: "amo",
            duration: 230, playedSeconds: 230
        )
        #expect(service.records.count == 1)

        service.clearHistory()
        #expect(service.records.isEmpty)
        #expect(service.snapshot.totalPlays == 0)
        try? FileManager.default.removeItem(at: dir)
    }

    @Test("Clear marker creation failure leaves disk and UI untouched")
    func testClearMarkerCreationFailureMutatesNothing() async {
        let dir = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let fixture = seedClearFixture(directory: dir)
        let marker = HistoryClearMarkerStore(
            directory: dir,
            beginOverride: { false })
        let service = ListeningHistoryService(
            store: fixture.log,
            tallyStore: fixture.tally,
            clearMarkerStore: marker,
            enabled: true)
        await service.loadFromDisk()
        let recordsBefore = service.records

        let cleared = service.clearHistory()

        #expect(!cleared)
        #expect(service.records == recordsBefore)
        #expect(fixture.log.loadAll().map(\.track) == ["On Disk"])
        #expect(!fixture.tally.load().isEmpty)
        #expect(!marker.isPending)
    }

    @Test("Failed log clear leaves a marker that relaunch recovery completes")
    func testLogClearFailureRecoversOnRelaunch() async {
        let dir = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let fixture = seedClearFixture(directory: dir)
        let failingLog = PlayLogStore(
            directory: dir,
            replaceAllOverride: { records in !records.isEmpty })
        let marker = HistoryClearMarkerStore(directory: dir)
        let service = ListeningHistoryService(
            store: failingLog,
            tallyStore: fixture.tally,
            clearMarkerStore: marker,
            enabled: true)
        await service.loadFromDisk()

        let cleared = service.clearHistory()

        #expect(!cleared)
        #expect(service.records.isEmpty)
        #expect(fixture.log.loadAll().map(\.track) == ["On Disk"])
        #expect(fixture.tally.load().isEmpty)
        #expect(marker.isPending)

        let recovered = makeService(enabled: true, directory: dir)
        await recovered.loadFromDisk()

        #expect(recovered.records.isEmpty)
        #expect(fixture.log.loadAll().isEmpty)
        #expect(fixture.tally.load().isEmpty)
        #expect(!HistoryClearMarkerStore(directory: dir).isPending)
    }

    @Test("Failed tally clear leaves a marker that relaunch recovery completes")
    func testTallyClearFailureRecoversOnRelaunch() async {
        let dir = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let fixture = seedClearFixture(directory: dir)
        let marker = HistoryClearMarkerStore(directory: dir)
        let service = ListeningHistoryService(
            store: fixture.log,
            tallyStore: LifetimeTallyStore(
                directory: dir,
                clearOverride: { false }),
            clearMarkerStore: marker,
            enabled: true)
        await service.loadFromDisk()

        let cleared = service.clearHistory()

        #expect(!cleared)
        #expect(service.records.isEmpty)
        #expect(fixture.log.loadAll().isEmpty)
        #expect(!fixture.tally.load().isEmpty)
        #expect(marker.isPending)

        let recovered = makeService(enabled: true, directory: dir)
        await recovered.loadFromDisk()

        #expect(recovered.records.isEmpty)
        #expect(fixture.log.loadAll().isEmpty)
        #expect(fixture.tally.load().isEmpty)
        #expect(!HistoryClearMarkerStore(directory: dir).isPending)
    }

    @Test("A play is rejected while a partial clear remains pending")
    func testRecordAfterPartialClearIsNotAppendedBehindMarker() async {
        let dir = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let fixture = seedClearFixture(directory: dir)
        let failingLog = PlayLogStore(
            directory: dir,
            replaceAllOverride: { records in !records.isEmpty })
        let marker = HistoryClearMarkerStore(directory: dir)
        let service = ListeningHistoryService(
            store: failingLog,
            tallyStore: fixture.tally,
            clearMarkerStore: marker,
            enabled: true)
        await service.loadFromDisk()
        #expect(!service.clearHistory())

        service.recordTrackChange(
            track: "After Clear", artist: "Wolf", album: "",
            duration: 200, playedSeconds: 200)

        #expect(service.records.isEmpty)
        #expect(fixture.log.loadAll().map(\.track) == ["On Disk"])
        #expect(marker.isPending)
    }

    @Test("Marker removal failure blocks appends and relaunch retries deletion")
    func testMarkerRemovalFailureRecoversOnRelaunch() async {
        let dir = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let fixture = seedClearFixture(directory: dir)
        let marker = HistoryClearMarkerStore(
            directory: dir,
            completeOverride: { false })
        let service = ListeningHistoryService(
            store: fixture.log,
            tallyStore: fixture.tally,
            clearMarkerStore: marker,
            enabled: true)
        await service.loadFromDisk()

        #expect(!service.clearHistory())
        #expect(fixture.log.loadAll().isEmpty)
        #expect(fixture.tally.load().isEmpty)
        #expect(marker.isPending)

        service.recordTrackChange(
            track: "After Marker Failure", artist: "Wolf", album: "",
            duration: 200, playedSeconds: 200)
        #expect(service.records.isEmpty)
        #expect(fixture.log.loadAll().isEmpty)

        let recovered = makeService(enabled: true, directory: dir)
        await recovered.loadFromDisk()

        #expect(recovered.records.isEmpty)
        #expect(!HistoryClearMarkerStore(directory: dir).isPending)
    }

    // MARK: - Disk Load

    @Test("loadFromDisk restores previously recorded plays")
    func testLoadFromDisk() async {
        let dir = makeTempDirectory()

        // First session: record two plays.
        let first = makeService(enabled: true, directory: dir)
        first.recordTrackChange(track: "One", artist: "A", album: "", duration: 200, playedSeconds: 200)
        first.recordTrackChange(track: "Two", artist: "B", album: "", duration: 200, playedSeconds: 200)
        first.shutdown()

        // Second session: a fresh service should load both from disk.
        let second = makeService(enabled: true, directory: dir)
        await second.loadFromDisk()

        #expect(second.records.count == 2)
        #expect(second.isLoaded)
        #expect(second.snapshot.totalPlays == 2)
        try? FileManager.default.removeItem(at: dir)
    }

    @Test("clear during load discards stale disk data and pre-clear buffer")
    func testClearDuringLoadWinsAndFlushesOnlyPostClearRecords() async {
        let dir = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }

        let store = PlayLogStore(directory: dir)
        store.replaceAll(with: [
            PlayRecord(
                timestamp: Date().addingTimeInterval(-60),
                track: "On Disk", artist: "Old", album: "",
                duration: 200, playedSeconds: 200)
        ])

        let barrier = HistoryLoadBarrier()
        defer { barrier.release() }
        let service = makeService(
            enabled: true,
            directory: dir,
            loadReadBarrier: { barrier.blockAfterRead() }
        )
        let load = Task { await service.loadFromDisk() }
        let reachedBarrier = await barrier.waitUntilBlocked()
        #expect(reachedBarrier)
        guard reachedBarrier else {
            load.cancel()
            return
        }

        service.recordTrackChange(
            track: "Buffered Before Clear", artist: "Old", album: "",
            duration: 200, playedSeconds: 200)
        service.clearHistory()
        service.recordTrackChange(
            track: "Buffered After Clear", artist: "New", album: "",
            duration: 200, playedSeconds: 200)

        barrier.release()
        await load.value

        #expect(service.records.map(\.track) == ["Buffered After Clear"])
        #expect(service.snapshot.totalPlays == 1)
        #expect(LifetimeTallyStore(directory: dir).load().isEmpty)
        #expect(store.loadAll().map(\.track) == ["Buffered After Clear"])
    }

    @Test("finite retention uses retained records only and clears undated lifetime tally")
    func testFiniteRetentionExcludesLifetimeTally() async {
        let dir = makeTempDirectory()
        defer {
            UserDefaults.standard.removeObject(
                forKey: AppConstants.UserDefaults.historyRetentionDays)
            try? FileManager.default.removeItem(at: dir)
        }
        UserDefaults.standard.set(
            30, forKey: AppConstants.UserDefaults.historyRetentionDays)

        let old = PlayRecord(
            timestamp: Date().addingTimeInterval(-60 * 86_400),
            track: "Expired", artist: "Old Artist", album: "",
            duration: 200, playedSeconds: 200)
        let recent = PlayRecord(
            timestamp: Date().addingTimeInterval(-60),
            track: "Retained", artist: "New Artist", album: "",
            duration: 200, playedSeconds: 200)
        let store = PlayLogStore(directory: dir)
        store.replaceAll(with: [old, recent])

        var staleLifetime = LifetimeTally.empty
        staleLifetime.fold(PlayRecord(
            timestamp: Date().addingTimeInterval(-90 * 86_400),
            track: "Previously Trimmed", artist: "Old Artist", album: "",
            duration: 200, playedSeconds: 200))
        let tallyStore = LifetimeTallyStore(directory: dir)
        tallyStore.save(staleLifetime)

        let service = makeService(enabled: true, directory: dir)
        await service.loadFromDisk()

        #expect(service.records.map(\.track) == ["Retained"])
        #expect(service.snapshot.totalPlays == 1)
        #expect(service.snapshot.topTracks.first?.name == "Retained")
        #expect(tallyStore.load().isEmpty)
        #expect(store.loadAll().map(\.track) == ["Retained"])
    }

    @Test("finite retention retries tally deletion before rewriting source log")
    func testFiniteRetentionClearFailureDefersRewriteUntilShutdownRetry() async {
        let dir = makeTempDirectory()
        defer {
            UserDefaults.standard.removeObject(
                forKey: AppConstants.UserDefaults.historyRetentionDays)
            try? FileManager.default.removeItem(at: dir)
        }
        UserDefaults.standard.set(
            30, forKey: AppConstants.UserDefaults.historyRetentionDays)
        let old = PlayRecord(
            timestamp: Date().addingTimeInterval(-60 * 86_400),
            track: "Expired", artist: "Old", album: "",
            duration: 200, playedSeconds: 200, sequence: 1)
        let recent = PlayRecord(
            timestamp: Date().addingTimeInterval(-60),
            track: "Retained", artist: "New", album: "",
            duration: 200, playedSeconds: 200, sequence: 2)
        let store = PlayLogStore(directory: dir)
        #expect(store.replaceAll(with: [old, recent]))
        var stale = LifetimeTally.empty
        stale.fold(old)
        let durableTallyStore = LifetimeTallyStore(directory: dir)
        #expect(durableTallyStore.save(stale))
        let failOnce = FailOnceTallyClear(fileURL: durableTallyStore.fileURL)
        let service = ListeningHistoryService(
            store: store,
            tallyStore: LifetimeTallyStore(
                directory: dir,
                clearOverride: { failOnce.clear() }),
            enabled: true)

        await service.loadFromDisk()

        #expect(service.records.map(\.track) == ["Retained"])
        #expect(store.loadAll().map(\.track) == ["Expired", "Retained"])
        #expect(!durableTallyStore.load().isEmpty)

        service.shutdown()

        #expect(failOnce.attempts == 2)
        #expect(durableTallyStore.load().isEmpty)
        #expect(store.loadAll().map(\.track) == ["Retained"])
    }

    // MARK: - Rolling Window Cap

    @Test("loadFromDisk trims to maxRetainedRecords and folds the rest into the lifetime tally")
    func testLoadFromDiskTrimsToCap() async {
        let dir = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }

        let cap = AppConstants.History.maxRetainedRecords
        let overflow = 5
        let total = cap + overflow

        // Seed the play log directly with `total` records, oldest first.
        let store = PlayLogStore(directory: dir)
        let base = Date().addingTimeInterval(-Double(total) * 60) // 1/min back
        var seeded: [PlayRecord] = []
        seeded.reserveCapacity(total)
        for i in 0..<total {
            seeded.append(PlayRecord(
                timestamp: base.addingTimeInterval(Double(i) * 60),
                track: "T\(i)", artist: "A\(i % 50)", album: "Al",
                duration: 200, playedSeconds: 200
            ))
        }
        store.replaceAll(with: seeded)

        let service = makeService(enabled: true, directory: dir)
        await service.loadFromDisk()

        #expect(service.records.count == cap)
        #expect(service.snapshot.totalPlays == total)
        // The newest record must still be present after trimming.
        #expect(service.records.last?.track == "T\(total - 1)")

        // The lifetime tally file must exist and reflect the trimmed overflow.
        let tallyOnDisk = LifetimeTallyStore(directory: dir).load()
        #expect(tallyOnDisk.trimmedPlayCount == overflow)
    }

    @Test("sequence high-water survives identical timestamps and a backward clock")
    func testSequenceHighWaterHandlesDuplicateAndBackwardTimestamps() async {
        let dir = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let cap = AppConstants.History.maxRetainedRecords
        let timestamp = Date(timeIntervalSince1970: 1_800_000_000)
        let seeded = (0..<(cap + 3)).map { index in
            PlayRecord(
                timestamp: index == 2
                    ? timestamp.addingTimeInterval(-3_600)
                    : timestamp,
                track: "T\(index)", artist: "Wolf", album: "",
                duration: 200, playedSeconds: 200,
                sequence: UInt64(index + 1))
        }
        let store = PlayLogStore(directory: dir)
        #expect(store.replaceAll(with: seeded))
        var tally = LifetimeTally.empty
        tally.fold(seeded[0])
        let tallyStore = LifetimeTallyStore(directory: dir)
        #expect(tallyStore.save(tally))

        let service = makeService(enabled: true, directory: dir)
        await service.loadFromDisk()

        let recovered = tallyStore.load()
        #expect(recovered.trimmedPlayCount == 3)
        #expect(recovered.lastFoldedSequence == 3)
        #expect(recovered.trackCounts["t0|wolf"]?.count == 1)
        #expect(recovered.trackCounts["t1|wolf"]?.count == 1)
        #expect(recovered.trackCounts["t2|wolf"]?.count == 1)
        #expect(service.snapshot.totalPlays == cap + 3)
        #expect(store.loadAll().count == cap)
    }

    @Test("legacy timestamp tally migrates to the assigned sequence boundary")
    func testLegacyTimestampTallyMigratesToSequence() async {
        let dir = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let cap = AppConstants.History.maxRetainedRecords
        let base = Date(timeIntervalSince1970: 1_700_000_000)
        let seeded = (0..<(cap + 1)).map { index in
            PlayRecord(
                timestamp: base.addingTimeInterval(Double(index)),
                track: "T\(index)", artist: "Wolf", album: "",
                duration: 200, playedSeconds: 200)
        }
        let store = PlayLogStore(directory: dir)
        #expect(store.replaceAll(with: seeded))
        var legacyTally = LifetimeTally.empty
        legacyTally.fold(seeded[0])
        #expect(legacyTally.lastFoldedSequence == nil)
        let tallyStore = LifetimeTallyStore(directory: dir)
        #expect(tallyStore.save(legacyTally))

        let service = makeService(enabled: true, directory: dir)
        await service.loadFromDisk()

        let migrated = tallyStore.load()
        #expect(migrated.trimmedPlayCount == 1)
        #expect(migrated.lastFoldedSequence == 1)
        let compacted = store.loadAll()
        #expect(compacted.count == cap)
        #expect(compacted.allSatisfy { $0.sequence != nil })
        #expect(compacted.first?.sequence == 2)
    }

    @Test("failed tally save leaves overflow NDJSON intact")
    func testTallySaveFailureDoesNotRewriteLog() async throws {
        let root = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let logDir = root.appending(path: "log")
        let blockedTallyDirectory = root.appending(path: "blocked-tally")
        try FileManager.default.createDirectory(
            at: logDir, withIntermediateDirectories: true)
        try Data("not a directory".utf8).write(to: blockedTallyDirectory)

        let cap = AppConstants.History.maxRetainedRecords
        let seeded = (0..<(cap + 1)).map { index in
            PlayRecord(
                timestamp: Date(timeIntervalSince1970: Double(1_700_000_000 + index)),
                track: "T\(index)", artist: "Wolf", album: "",
                duration: 200, playedSeconds: 200,
                sequence: UInt64(index + 1))
        }
        let store = PlayLogStore(directory: logDir)
        #expect(store.replaceAll(with: seeded))
        let service = ListeningHistoryService(
            store: store,
            tallyStore: LifetimeTallyStore(directory: blockedTallyDirectory),
            enabled: true)

        await service.loadFromDisk()

        #expect(service.records.count == cap)
        #expect(store.loadAll().count == cap + 1)
    }

    @Test("failed log rewrite keeps source NDJSON after tally becomes durable")
    func testRewriteFailureLeavesRecoverableLog() async {
        let dir = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let cap = AppConstants.History.maxRetainedRecords
        let seeded = (0..<(cap + 1)).map { index in
            PlayRecord(
                timestamp: Date(timeIntervalSince1970: Double(1_700_000_000 + index)),
                track: "T\(index)", artist: "Wolf", album: "",
                duration: 200, playedSeconds: 200,
                sequence: UInt64(index + 1))
        }
        let seeder = PlayLogStore(directory: dir)
        #expect(seeder.replaceAll(with: seeded))
        let failingStore = PlayLogStore(
            directory: dir,
            replaceAllOverride: { _ in false })
        let tallyStore = LifetimeTallyStore(directory: dir)
        let service = ListeningHistoryService(
            store: failingStore, tallyStore: tallyStore, enabled: true)

        await service.loadFromDisk()

        #expect(tallyStore.load().trimmedPlayCount == 1)
        #expect(tallyStore.load().lastFoldedSequence == 1)
        #expect(seeder.loadAll().count == cap + 1)

        let recovered = makeService(enabled: true, directory: dir)
        await recovered.loadFromDisk()
        #expect(recovered.snapshot.totalPlays == cap + 1)
        #expect(PlayLogStore(directory: dir).loadAll().count == cap)
    }

    @Test("legacy log recovery does not refold after a failed rewrite")
    func testLegacyRewriteFailureDoesNotDoubleFold() async {
        let dir = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let cap = AppConstants.History.maxRetainedRecords
        let overflow = 3
        let seeded = (0..<(cap + overflow)).map { index in
            PlayRecord(
                timestamp: Date(timeIntervalSince1970: Double(1_700_000_000 + index)),
                track: "T\(index)", artist: "Wolf", album: "",
                duration: 200, playedSeconds: 200)
        }
        let durableStore = PlayLogStore(directory: dir)
        #expect(durableStore.replaceAll(with: seeded))
        #expect(durableStore.loadAll().allSatisfy { $0.sequence == nil })
        let tallyStore = LifetimeTallyStore(directory: dir)
        let firstLoad = ListeningHistoryService(
            store: PlayLogStore(
                directory: dir,
                replaceAllOverride: { _ in false }),
            tallyStore: tallyStore,
            enabled: true)

        await firstLoad.loadFromDisk()

        #expect(tallyStore.load().trimmedPlayCount == overflow)
        #expect(tallyStore.load().lastFoldedSequence == UInt64(overflow))
        #expect(durableStore.loadAll().allSatisfy { $0.sequence == nil })

        let recovered = makeService(enabled: true, directory: dir)
        await recovered.loadFromDisk()

        #expect(recovered.snapshot.totalPlays == cap + overflow)
        let recoveredTally = tallyStore.load()
        #expect(recoveredTally.trimmedPlayCount == overflow)
        #expect(recoveredTally.lastFoldedSequence == UInt64(overflow))
        #expect(recoveredTally.trackCounts["t0|wolf"]?.count == 1)
        #expect(recoveredTally.trackCounts["t1|wolf"]?.count == 1)
        #expect(recoveredTally.trackCounts["t2|wolf"]?.count == 1)
        let compacted = durableStore.loadAll()
        #expect(compacted.count == cap)
        #expect(compacted.first?.sequence == UInt64(overflow + 1))
        #expect(compacted.last?.sequence == UInt64(cap + overflow))
    }

    @Test("duplicate and non-monotonic sequences repair deterministically")
    func testMalformedSequencesRepairDeterministically() async {
        let dir = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let timestamp = Date(timeIntervalSince1970: 1_700_000_000)
        let sourceSequences: [UInt64?] = [5, nil, 5, 4, 9]
        let seeded = sourceSequences.enumerated().map { index, sequence in
            PlayRecord(
                timestamp: timestamp.addingTimeInterval(Double(index)),
                track: "T\(index)", artist: "Wolf", album: "",
                duration: 200, playedSeconds: 200, sequence: sequence)
        }
        let durableStore = PlayLogStore(directory: dir)
        #expect(durableStore.replaceAll(with: seeded))
        let firstLoad = ListeningHistoryService(
            store: PlayLogStore(
                directory: dir,
                replaceAllOverride: { _ in false }),
            tallyStore: LifetimeTallyStore(directory: dir),
            enabled: true)

        await firstLoad.loadFromDisk()
        #expect(durableStore.loadAll().map(\.sequence) == sourceSequences)

        let recovered = makeService(enabled: true, directory: dir)
        await recovered.loadFromDisk()

        let expected: [UInt64?] = [5, 6, 7, 8, 9]
        #expect(recovered.records.map(\.sequence) == expected)
        #expect(durableStore.loadAll().map(\.sequence) == expected)
    }

    @Test("shutdown during scheduled load flushes deferred plays above disk watermark")
    func testShutdownDuringLoadFlushesDeferredRecords() async {
        let dir = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = PlayLogStore(directory: dir)
        #expect(store.replaceAll(with: [
            PlayRecord(
                timestamp: Date(timeIntervalSince1970: 1_700_000_000),
                track: "Existing", artist: "Wolf", album: "",
                duration: 200, playedSeconds: 200, sequence: 50)
        ]))
        let barrier = HistoryLoadBarrier()
        defer { barrier.release() }
        let service = makeService(
            enabled: true,
            directory: dir,
            loadReadBarrier: { barrier.blockAfterRead() })

        service.start()
        service.recordTrackChange(
            track: "During Load", artist: "Wolf", album: "",
            duration: 200, playedSeconds: 200)
        #expect(service.records.isEmpty)
        let reachedBarrier = await barrier.waitUntilBlocked()
        #expect(reachedBarrier)
        guard reachedBarrier else { return }

        service.shutdown()
        let beforeLoaderReturns = store.loadAll()
        #expect(beforeLoaderReturns.map(\.track) == ["Existing", "During Load"])
        #expect(beforeLoaderReturns.map(\.sequence) == [50, 51])

        barrier.release()
        let staleLoadDrained = await waitUntil(timeout: .seconds(1)) {
            service.isLoaded
        }
        #expect(staleLoadDrained)
        #expect(store.loadAll().map(\.track) == ["Existing", "During Load"])
    }

    @Test("overflow append defers tally persistence and shutdown reload keeps the evicted play")
    func testOverflowAppendDefersTallyPersistenceUntilShutdown() async {
        let dir = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }

        let cap = AppConstants.History.maxRetainedRecords

        // Seed the disk log with `cap` records via replaceAll (fast), then
        // load. Service is at the cap with no trimming required.
        let store = PlayLogStore(directory: dir)
        let base = Date().addingTimeInterval(-Double(cap) * 60)
        var seeded: [PlayRecord] = []
        seeded.reserveCapacity(cap)
        for i in 0..<cap {
            seeded.append(PlayRecord(
                timestamp: base.addingTimeInterval(Double(i) * 60),
                track: "T\(i)", artist: "Wolf", album: "Al",
                duration: 200, playedSeconds: 200
            ))
        }
        store.replaceAll(with: seeded)

        let service = makeService(enabled: true, directory: dir)
        await service.loadFromDisk()
        #expect(service.records.count == cap)

        // One more push should evict the oldest into the tally.
        service.recordTrackChange(
            track: "Overflow", artist: "Wolf", album: "",
            duration: 200, playedSeconds: 200
        )
        #expect(service.records.count == cap)
        #expect(service.records.last?.track == "Overflow")
        #expect(service.records.first?.track == "T1")
        #expect(service.snapshot.totalPlays == cap + 1)

        // The append hot path must not rewrite the full sidecar. Until a clean
        // shutdown, the evicted play remains recoverable from append-only NDJSON.
        let tallyStore = LifetimeTallyStore(directory: dir)
        #expect(tallyStore.load().isEmpty)

        service.shutdown()
        #expect(tallyStore.load().trimmedPlayCount == 1)
        #expect(tallyStore.load().trackCounts["t0|wolf"]?.count == 1)

        // A fresh process sees both the compacted live window and the tally.
        let reloaded = makeService(enabled: true, directory: dir)
        await reloaded.loadFromDisk()
        #expect(reloaded.records.count == cap)
        #expect(reloaded.snapshot.totalPlays == cap + 1)
        #expect(tallyStore.load().trackCounts["t0|wolf"]?.count == 1)
    }

    @Test("shutdown synchronously persists compaction + tally when window overflowed")
    func testShutdownPersistsCompaction() async {
        let dir = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }

        let cap = AppConstants.History.maxRetainedRecords
        let store = PlayLogStore(directory: dir)
        let base = Date().addingTimeInterval(-Double(cap) * 60)
        var seeded: [PlayRecord] = []
        seeded.reserveCapacity(cap)
        for i in 0..<cap {
            seeded.append(PlayRecord(
                timestamp: base.addingTimeInterval(Double(i) * 60),
                track: "T\(i)", artist: "Wolf", album: "Al",
                duration: 200, playedSeconds: 200
            ))
        }
        store.replaceAll(with: seeded)

        let service = makeService(enabled: true, directory: dir)
        await service.loadFromDisk()
        // Drive the service one record past the cap: fold + arm compaction.
        service.recordTrackChange(
            track: "Overflow", artist: "Wolf", album: "",
            duration: 200, playedSeconds: 200
        )

        // shutdown() must compact the NDJSON and persist the tally synchronously.
        service.shutdown()

        let onDisk = PlayLogStore(directory: dir).loadAll()
        #expect(onDisk.count == cap)
        #expect(onDisk.last?.track == "Overflow")
        #expect(onDisk.first?.track == "T1")

        let tally = LifetimeTallyStore(directory: dir).load()
        #expect(tally.trimmedPlayCount == 1)
        #expect(tally.trackCounts["t0|wolf"]?.count == 1)
    }

    // MARK: - Chat Line

    @Test("statsChatLine is friendly when nothing has played")
    func testStatsChatLineEmpty() {
        let dir = makeTempDirectory()
        let service = makeService(enabled: true, directory: dir)
        #expect(service.statsChatLine().contains("just getting started"))
        try? FileManager.default.removeItem(at: dir)
    }

    @Test("statsChatLine reports today's top track")
    func testStatsChatLineWithPlays() {
        let dir = makeTempDirectory()
        let service = makeService(enabled: true, directory: dir)
        service.recordTrackChange(
            track: "Blinding Lights", artist: "The Weeknd", album: "After Hours",
            duration: 200, playedSeconds: 200
        )
        let line = service.statsChatLine()
        #expect(line.contains("Blinding Lights"))
        #expect(line.contains("The Weeknd"))
        try? FileManager.default.removeItem(at: dir)
    }
}
