//
//  PlayLogStoreTests.swift
//  WolfWave
//
//  Created by Nathanial Henniges on 2026-05-22.
//  Copyright © 2026 MrDemonWolf, Inc. All rights reserved.
//

import Testing
import Foundation
@testable import WolfWave

/// Tests for the append-only NDJSON play-log store.
@MainActor
@Suite("Play Log Store Tests")
struct PlayLogStoreTests {

    // MARK: - Helpers

    /// Creates a fresh, unique temporary directory for an isolated store.
    private func makeTempDirectory() -> URL {
        makeIsolatedTempDirectory(prefix: "playlog-test")
    }

    private func sampleRecord(
        track: String,
        artist: String = "The Weeknd",
        sequence: UInt64? = nil
    ) -> PlayRecord {
        PlayRecord(
            timestamp: Date(timeIntervalSince1970: 1_716_000_000),
            track: track,
            artist: artist,
            album: "After Hours",
            duration: 200,
            playedSeconds: 188,
            sequence: sequence
        )
    }

    // MARK: - Append & Load

    @Test("Appended records are loaded back in order")
    func testAppendAndLoad() async throws {
        let dir = makeTempDirectory()
        let store = PlayLogStore(directory: dir)

        store.append(sampleRecord(track: "Blinding Lights"))
        store.append(sampleRecord(track: "Save Your Tears"))
        store.flush()

        let loaded = store.loadAll()
        #expect(loaded.count == 2)
        #expect(loaded.first?.track == "Blinding Lights")
        #expect(loaded.last?.track == "Save Your Tears")

        try? FileManager.default.removeItem(at: dir)
    }

    @Test("Loading an absent log returns an empty array")
    func testLoadEmpty() async throws {
        let dir = makeTempDirectory()
        let store = PlayLogStore(directory: dir)
        #expect(store.loadAll().isEmpty)
        try? FileManager.default.removeItem(at: dir)
    }

    @Test("Record fields survive an encode/decode round trip")
    func testRoundTrip() async throws {
        let dir = makeTempDirectory()
        let store = PlayLogStore(directory: dir)

        let original = sampleRecord(track: "Out of Time", sequence: 42)
        store.append(original)
        store.flush()

        let loaded = try #require(store.loadAll().first)
        #expect(loaded.track == original.track)
        #expect(loaded.artist == original.artist)
        #expect(loaded.album == original.album)
        #expect(loaded.duration == original.duration)
        #expect(loaded.playedSeconds == original.playedSeconds)
        #expect(loaded.sequence == 42)
        #expect(Int(loaded.timestamp.timeIntervalSince1970) == Int(original.timestamp.timeIntervalSince1970))

        try? FileManager.default.removeItem(at: dir)
    }

    @Test("Legacy NDJSON without a sequence remains readable")
    func testLegacyRecordWithoutSequenceDecodes() async throws {
        let dir = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let store = PlayLogStore(directory: dir)
        let legacy = """
        {"t":1716000000,"track":"Legacy","artist":"Wolf","album":"","dur":200,"played":180}
        """
        try Data((legacy + "\n").utf8).write(to: store.fileURL)

        let loaded = try #require(store.loadAll().first)
        #expect(loaded.track == "Legacy")
        #expect(loaded.sequence == nil)
    }

    // MARK: - Malformed Lines

    @Test("Malformed lines are skipped, valid lines survive")
    func testMalformedLinesSkipped() async throws {
        let dir = makeTempDirectory()
        let store = PlayLogStore(directory: dir)
        store.append(sampleRecord(track: "Good Line"))
        store.flush()

        // Manually append a junk line, simulating a partial write before a crash.
        if let handle = FileHandle(forWritingAtPath: store.fileURL.path) {
            _ = try? handle.seekToEnd()
            handle.write(Data("{not valid json\n".utf8))
            try? handle.close()
        }

        let loaded = store.loadAll()
        #expect(loaded.count == 1)
        #expect(loaded.first?.track == "Good Line")

        try? FileManager.default.removeItem(at: dir)
    }

    // MARK: - Replace & Clear

    @Test("replaceAll rewrites the log with exactly the given records")
    func testReplaceAll() async throws {
        let dir = makeTempDirectory()
        let store = PlayLogStore(directory: dir)
        store.append(sampleRecord(track: "Old 1"))
        store.append(sampleRecord(track: "Old 2"))
        store.flush()

        #expect(store.replaceAll(with: [sampleRecord(track: "Kept")]))
        let loaded = store.loadAll()
        #expect(loaded.count == 1)
        #expect(loaded.first?.track == "Kept")

        try? FileManager.default.removeItem(at: dir)
    }

    @Test("replaceAll reports an unwritable destination")
    func testReplaceAllFailureResult() async throws {
        let dir = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let blocked = dir.appending(path: "not-a-directory")
        try Data("blocked".utf8).write(to: blocked)
        let store = PlayLogStore(directory: blocked)

        #expect(!store.replaceAll(with: [sampleRecord(track: "Cannot Write")]))
    }

    @Test("clear empties the log")
    func testClear() async throws {
        let dir = makeTempDirectory()
        let store = PlayLogStore(directory: dir)
        store.append(sampleRecord(track: "Doomed"))
        store.flush()

        store.clear()
        #expect(store.loadAll().isEmpty)

        try? FileManager.default.removeItem(at: dir)
    }

    @Test("Appends still work after a replaceAll")
    func testAppendAfterReplace() async throws {
        let dir = makeTempDirectory()
        let store = PlayLogStore(directory: dir)
        store.append(sampleRecord(track: "First"))
        store.flush()
        store.replaceAll(with: [sampleRecord(track: "Compacted")])
        store.append(sampleRecord(track: "After Compaction"))
        store.flush()

        let loaded = store.loadAll()
        #expect(loaded.count == 2)
        #expect(loaded.first?.track == "Compacted")
        #expect(loaded.last?.track == "After Compaction")

        try? FileManager.default.removeItem(at: dir)
    }
}
