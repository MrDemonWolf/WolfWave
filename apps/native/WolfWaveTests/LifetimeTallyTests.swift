//
//  LifetimeTallyTests.swift
//  WolfWaveTests
//
//  Created by MrDemonWolf, Inc. on 5/25/26.
//

import Testing
import Foundation
@testable import WolfWave

/// Tests for the lifetime tally model and its on-disk store.
@MainActor
@Suite("Lifetime Tally Tests")
struct LifetimeTallyTests {

    // MARK: - Helpers

    private func record(
        track: String, artist: String, album: String = "Album",
        played: TimeInterval = 200
    ) -> PlayRecord {
        PlayRecord(
            timestamp: Date(),
            track: track, artist: artist, album: album,
            duration: 220, playedSeconds: played
        )
    }

    // MARK: - Fold

    @Test("Folding a record increments totals and per-key buckets")
    func testFoldSingle() {
        var tally = LifetimeTally.empty
        tally.fold(record(track: "A", artist: "Wolf", played: 180))

        #expect(tally.trimmedPlayCount == 1)
        #expect(tally.trimmedListeningSeconds == 180)
        #expect(tally.artistCounts["wolf"]?.count == 1)
        #expect(tally.trackCounts["a|wolf"]?.count == 1)
        #expect(tally.albumCounts["album|wolf"]?.count == 1)
    }

    @Test("Folding the same track multiple times accumulates count + seconds")
    func testFoldAccumulates() {
        var tally = LifetimeTally.empty
        tally.fold(record(track: "A", artist: "Wolf", played: 100))
        tally.fold(record(track: "A", artist: "Wolf", played: 200))
        tally.fold(record(track: "A", artist: "Wolf", played: 50))

        #expect(tally.trimmedPlayCount == 3)
        #expect(tally.trimmedListeningSeconds == 350)
        let entry = tally.trackCounts["a|wolf"]
        #expect(entry?.count == 3)
        #expect(entry?.seconds == 350)
    }

    @Test("Records with empty album skip the album bucket")
    func testEmptyAlbumNotCounted() {
        var tally = LifetimeTally.empty
        tally.fold(record(track: "A", artist: "Wolf", album: "", played: 60))
        #expect(tally.artistCounts.count == 1)
        #expect(tally.trackCounts.count == 1)
        #expect(tally.albumCounts.isEmpty)
    }

    // MARK: - Eviction

    @Test("Per-dimension cap evicts the lowest-count entry")
    func testEvictionAtCap() {
        var tally = LifetimeTally.empty
        // Cap = 3. Seed with three artists at counts 3, 2, 1.
        for _ in 0..<3 { tally.fold(record(track: "T1", artist: "AlphaArtist"), keyCap: 3) }
        for _ in 0..<2 { tally.fold(record(track: "T2", artist: "BetaArtist"), keyCap: 3) }
        tally.fold(record(track: "T3", artist: "GammaArtist"), keyCap: 3)
        #expect(tally.artistCounts.count == 3)

        // A fourth, brand-new artist arrives — Gamma (lowest) should be evicted.
        tally.fold(record(track: "T4", artist: "DeltaArtist"), keyCap: 3)
        #expect(tally.artistCounts.count == 3)
        #expect(tally.artistCounts["gammaartist"] == nil)
        #expect(tally.artistCounts["deltaartist"]?.count == 1)
        #expect(tally.artistCounts["alphaartist"]?.count == 3)
    }

    // MARK: - Codable

    @Test("Tally round-trips through JSON encoder/decoder")
    func testCodableRoundTrip() throws {
        var tally = LifetimeTally.empty
        tally.fold(record(track: "Song", artist: "Wolf", played: 120))
        tally.fold(record(track: "Other", artist: "Wolf", album: "", played: 60))

        let data = try JSONEncoder().encode(tally)
        let restored = try JSONDecoder().decode(LifetimeTally.self, from: data)
        #expect(restored == tally)
    }

    // MARK: - Store

    @Test("Store load returns .empty when file is absent")
    func testStoreLoadMissing() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("wolfwave-tally-\(UUID().uuidString)", isDirectory: true)
        let store = LifetimeTallyStore(directory: dir)
        #expect(store.load().isEmpty)
    }

    @Test("Store save then load reproduces the tally")
    func testStoreSaveLoad() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("wolfwave-tally-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let store = LifetimeTallyStore(directory: dir)
        var tally = LifetimeTally.empty
        tally.fold(record(track: "S", artist: "Wolf", played: 99))
        store.save(tally)

        let loaded = store.load()
        #expect(loaded == tally)
    }

    @Test("Store clear removes the file so the next load is empty")
    func testStoreClear() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("wolfwave-tally-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let store = LifetimeTallyStore(directory: dir)
        var tally = LifetimeTally.empty
        tally.fold(record(track: "S", artist: "Wolf"))
        store.save(tally)
        store.clear()
        #expect(store.load().isEmpty)
    }
}
