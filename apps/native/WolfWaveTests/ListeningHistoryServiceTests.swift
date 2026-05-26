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

/// Tests for the listening-history orchestrator: scrobble threshold, gating,
/// recording, clearing, and the disk-load path.
@Suite("Listening History Service Tests")
@MainActor
struct ListeningHistoryServiceTests {

    // MARK: - Helpers

    private func makeTempDirectory() -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("history-svc-test-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func makeService(enabled: Bool, directory: URL) -> ListeningHistoryService {
        ListeningHistoryService(
            store: PlayLogStore(directory: directory),
            tallyStore: LifetimeTallyStore(directory: directory),
            enabled: enabled
        )
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

    @Test("recordTrackChange past the cap folds the oldest play into the tally")
    func testRecordPastCapFolds() async {
        let dir = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }

        let cap = AppConstants.History.maxRetainedRecords

        // Seed the disk log with `cap` records via replaceAll (fast), then
        // load — service is at the cap with no trimming required.
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
        // The folded record (T0) should appear in the persisted tally.
        let tally = LifetimeTallyStore(directory: dir).load()
        #expect(tally.trimmedPlayCount == 1)
        #expect(tally.trackCounts["t0|wolf"]?.count == 1)
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
        // Drive the service one record past the cap — fold + arm compaction.
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
