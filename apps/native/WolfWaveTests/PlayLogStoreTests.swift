//
//  PlayLogStoreTests.swift
//  wolfwave
//
//  Created by MrDemonWolf, Inc. on 5/22/26.
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
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("playlog-test-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func sampleRecord(track: String, artist: String = "The Weeknd") -> PlayRecord {
        PlayRecord(
            timestamp: Date(timeIntervalSince1970: 1_716_000_000),
            track: track,
            artist: artist,
            album: "After Hours",
            duration: 200,
            playedSeconds: 188
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

        let original = sampleRecord(track: "Out of Time")
        store.append(original)
        store.flush()

        let loaded = try #require(store.loadAll().first)
        #expect(loaded.track == original.track)
        #expect(loaded.artist == original.artist)
        #expect(loaded.album == original.album)
        #expect(loaded.duration == original.duration)
        #expect(loaded.playedSeconds == original.playedSeconds)
        #expect(Int(loaded.timestamp.timeIntervalSince1970) == Int(original.timestamp.timeIntervalSince1970))

        try? FileManager.default.removeItem(at: dir)
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
            try? handle.seekToEnd()
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

        store.replaceAll(with: [sampleRecord(track: "Kept")])
        let loaded = store.loadAll()
        #expect(loaded.count == 1)
        #expect(loaded.first?.track == "Kept")

        try? FileManager.default.removeItem(at: dir)
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
