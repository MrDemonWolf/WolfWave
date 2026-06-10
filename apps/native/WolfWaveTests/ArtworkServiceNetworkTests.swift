//
//  ArtworkServiceNetworkTests.swift
//  WolfWave
//
//  Created by Nathanial Henniges on 2026-05-22.
//  Copyright © 2026 MrDemonWolf, Inc. All rights reserved.
//

import XCTest

@testable import WolfWave

// MARK: - ArtworkServiceNetworkTests

/// Covers `ArtworkService` iTunes Search API parsing, error handling, and
/// caching, with the network layer stubbed by `MockURLProtocol`.
@MainActor
final class ArtworkServiceNetworkTests: XCTestCase {

    private var service: ArtworkService!

    override func setUp() {
        super.setUp()
        service = ArtworkService(session: MockURLProtocol.makeSession(), persistenceURL: nil)
    }

    override func tearDown() {
        MockURLProtocol.reset()
        service = nil
        super.tearDown()
    }

    /// Awaits the callback-based `fetchTrackLinks` as an async value.
    private func fetchLinks(track: String, artist: String) async -> TrackLinks {
        await withCheckedContinuation { continuation in
            service.fetchTrackLinks(track: track, artist: artist) { links in
                continuation.resume(returning: links)
            }
        }
    }

    func testFetchTrackLinksParsesFieldsAndUpgradesArtworkResolution() async {
        MockURLProtocol.requestHandler = { request in
            let result = #"{"artworkUrl100":"https://cdn.example/100x100bb.jpg","trackViewUrl":"https://music.apple.com/track","trackId":42}"#
            let json = #"{"results":[\#(result)]}"#
            return (MockURLProtocol.httpResponse(for: request, status: 200), Data(json.utf8))
        }

        let links = await fetchLinks(track: "Song", artist: "Artist")

        XCTAssertEqual(links.artworkURL, "https://cdn.example/512x512bb.jpg")
        XCTAssertEqual(links.trackViewURL, "https://music.apple.com/track")
        XCTAssertNotNil(links.songLinkURL)
    }

    func testFetchTrackLinksReturnsNilFieldsOnEmptyResults() async {
        MockURLProtocol.requestHandler = { request in
            (MockURLProtocol.httpResponse(for: request, status: 200), Data(#"{"results":[]}"#.utf8))
        }

        let links = await fetchLinks(track: "Missing", artist: "Nobody")

        XCTAssertNil(links.artworkURL)
        XCTAssertNil(links.trackViewURL)
        XCTAssertNil(links.songLinkURL)
    }

    func testFetchTrackLinksHandlesNetworkError() async {
        MockURLProtocol.requestHandler = { _ in throw URLError(.timedOut) }

        let links = await fetchLinks(track: "Song", artist: "Artist")

        XCTAssertNil(links.artworkURL)
    }

    func testFetchTrackLinksPopulatesCache() async {
        MockURLProtocol.requestHandler = { request in
            let json = #"{"results":[{"artworkUrl100":"https://cdn.example/100x100.jpg","trackId":7}]}"#
            return (MockURLProtocol.httpResponse(for: request, status: 200), Data(json.utf8))
        }

        _ = await fetchLinks(track: "Cached", artist: "Artist")

        let cached = service.cachedTrackLinks(track: "Cached", artist: "Artist")
        XCTAssertEqual(cached.artworkURL, "https://cdn.example/512x512.jpg")
    }

    func testMissIsNotRequeriedWithinTTL() async {
        let counter = ThreadSafeBox(0)
        MockURLProtocol.requestHandler = { request in
            counter.mutate { $0 += 1 }
            return (MockURLProtocol.httpResponse(for: request, status: 200), Data(#"{"results":[]}"#.utf8))
        }

        // First lookup misses and records the empty resolution.
        _ = await fetchLinks(track: "Missing", artist: "Nobody")
        // Second lookup for the same track must be served from the negative cache.
        _ = await fetchLinks(track: "Missing", artist: "Nobody")

        XCTAssertEqual(counter.value, 1, "A recent miss must not re-hit the network")
    }

    func testCachePersistsAcrossInstancesViaDisk() async {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("artwork-test-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }

        MockURLProtocol.requestHandler = { request in
            let json = #"{"results":[{"artworkUrl100":"https://cdn.example/100x100.jpg","trackId":7}]}"#
            return (MockURLProtocol.httpResponse(for: request, status: 200), Data(json.utf8))
        }

        // First instance fetches + persists to disk.
        let first = ArtworkService(session: MockURLProtocol.makeSession(), persistenceURL: url)
        _ = await withCheckedContinuation { (cont: CheckedContinuation<TrackLinks, Never>) in
            first.fetchTrackLinks(track: "Persisted", artist: "Artist") { cont.resume(returning: $0) }
        }

        // Wait for the async disk write to land.
        let wrote = await waitUntil { FileManager.default.fileExists(atPath: url.path) }
        XCTAssertTrue(wrote, "Cache file should be written within the timeout")

        // Second instance loads from the same file, no network.
        let second = ArtworkService(session: MockURLProtocol.makeSession(), persistenceURL: url)
        let cached = second.cachedTrackLinks(track: "Persisted", artist: "Artist")
        XCTAssertEqual(cached.artworkURL, "https://cdn.example/512x512.jpg")
    }

    func testClearCacheEmptiesMemoryAndDisk() async {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("artwork-test-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }

        MockURLProtocol.requestHandler = { request in
            let json = #"{"results":[{"artworkUrl100":"https://cdn.example/100x100.jpg","trackId":7}]}"#
            return (MockURLProtocol.httpResponse(for: request, status: 200), Data(json.utf8))
        }

        let svc = ArtworkService(session: MockURLProtocol.makeSession(), persistenceURL: url)
        _ = await withCheckedContinuation { (cont: CheckedContinuation<TrackLinks, Never>) in
            svc.fetchTrackLinks(track: "Doomed", artist: "Artist") { cont.resume(returning: $0) }
        }
        await waitUntil { FileManager.default.fileExists(atPath: url.path) }

        svc.clearCache()
        let deleted = await waitUntil { !FileManager.default.fileExists(atPath: url.path) }

        XCTAssertNil(svc.cachedArtworkURL(track: "Doomed", artist: "Artist"))
        XCTAssertEqual(svc.cacheStats().entryCount, 0)
        XCTAssertTrue(deleted, "Cache file should be deleted within the timeout")
    }

    func testCachedResultIsServedWithoutHittingNetwork() async {
        MockURLProtocol.requestHandler = { request in
            let json = #"{"results":[{"artworkUrl100":"https://cdn.example/100x100.jpg","trackId":7}]}"#
            return (MockURLProtocol.httpResponse(for: request, status: 200), Data(json.utf8))
        }
        _ = await fetchLinks(track: "Track", artist: "Artist")

        // Any further network call now fails. A cache hit must avoid it.
        MockURLProtocol.requestHandler = { _ in throw URLError(.notConnectedToInternet) }
        let links = await fetchLinks(track: "Track", artist: "Artist")

        XCTAssertEqual(links.artworkURL, "https://cdn.example/512x512.jpg")
    }
}
