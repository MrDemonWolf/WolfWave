//
//  LifetimeTallyTests.swift
//  WolfWave
//
//  Created by Nathanial Henniges on 2026-05-25.
//  Copyright © 2026 MrDemonWolf, Inc. All rights reserved.
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
        played: TimeInterval = 200,
        sequence: UInt64? = nil
    ) -> PlayRecord {
        PlayRecord(
            timestamp: Date(),
            track: track, artist: artist, album: album,
            duration: 220, playedSeconds: played, sequence: sequence
        )
    }

    // MARK: - Fold

    @Test("Folding a record increments totals and per-key buckets")
    func testFoldSingle() {
        var tally = LifetimeTally.empty
        tally.fold(record(track: "A", artist: "Wolf", played: 180, sequence: 9))

        #expect(tally.trimmedPlayCount == 1)
        #expect(tally.trimmedListeningSeconds == 180)
        #expect(tally.artistCounts["wolf"]?.count == 1)
        #expect(tally.trackCounts["a|wolf"]?.count == 1)
        #expect(tally.albumCounts["album|wolf"]?.count == 1)
        #expect(tally.lastFoldedSequence == 9)
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

    // MARK: - Exact Keys

    @Test("Folding retains every key so later plays can change the true top item")
    func testFoldRetainsAllKeys() {
        var tally = LifetimeTally.empty
        for _ in 0..<3 { tally.fold(record(track: "T1", artist: "AlphaArtist")) }
        for _ in 0..<2 { tally.fold(record(track: "T2", artist: "BetaArtist")) }
        tally.fold(record(track: "T3", artist: "GammaArtist"))
        tally.fold(record(track: "T4", artist: "DeltaArtist"))

        #expect(tally.artistCounts.count == 4)
        #expect(tally.artistCounts["gammaartist"]?.count == 1)
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
        let dir = makeIsolatedTempDirectory(prefix: "wolfwave-tally")
        let store = LifetimeTallyStore(directory: dir)
        #expect(store.load().isEmpty)
    }

    @Test("Store save then load reproduces the tally")
    func testStoreSaveLoad() throws {
        let dir = makeIsolatedTempDirectory(prefix: "wolfwave-tally")
        defer { try? FileManager.default.removeItem(at: dir) }

        let store = LifetimeTallyStore(directory: dir)
        var tally = LifetimeTally.empty
        tally.fold(record(track: "S", artist: "Wolf", played: 99))
        #expect(store.save(tally))

        let loaded = store.load()
        #expect(loaded == tally)
    }

    @Test("Store save reports an unwritable destination")
    func testStoreSaveFailureResult() throws {
        let dir = makeIsolatedTempDirectory(prefix: "wolfwave-tally")
        defer { try? FileManager.default.removeItem(at: dir) }
        let blocked = dir.appending(path: "not-a-directory")
        try Data("blocked".utf8).write(to: blocked)
        let store = LifetimeTallyStore(directory: blocked)

        #expect(!store.save(.empty))
    }

    @Test("Store clear removes the file so the next load is empty")
    func testStoreClear() throws {
        let dir = makeIsolatedTempDirectory(prefix: "wolfwave-tally")
        defer { try? FileManager.default.removeItem(at: dir) }

        let store = LifetimeTallyStore(directory: dir)
        var tally = LifetimeTally.empty
        tally.fold(record(track: "S", artist: "Wolf"))
        store.save(tally)
        store.clear()
        #expect(store.load().isEmpty)
    }
}
