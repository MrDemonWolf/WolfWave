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
    private let handlerStore = MockURLProtocol.HandlerStore()

    override func setUp() {
        super.setUp()
        handlerStore.handler = nil
        service = ArtworkService(session: MockURLProtocol.makeSession(handlerStore: handlerStore), persistenceURL: nil)
    }

    override func tearDown() {
        handlerStore.handler = nil
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
        handlerStore.handler = { request in
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
        handlerStore.handler = { request in
            (MockURLProtocol.httpResponse(for: request, status: 200), Data(#"{"results":[]}"#.utf8))
        }

        let links = await fetchLinks(track: "Missing", artist: "Nobody")

        XCTAssertNil(links.artworkURL)
        XCTAssertNil(links.trackViewURL)
        XCTAssertNil(links.songLinkURL)
    }

    func testFetchTrackLinksHandlesNetworkError() async {
        handlerStore.handler = { _ in throw URLError(.timedOut) }

        let links = await fetchLinks(track: "Song", artist: "Artist")

        XCTAssertNil(links.artworkURL)
        XCTAssertFalse(
            service.hasAttemptedTrackLinks(track: "Song", artist: "Artist"),
            "A transient transport failure must remain retryable"
        )
    }

    func testTransportFailureIsRetriedInsteadOfNegativeCached() async {
        let counter = ThreadSafeBox(0)
        handlerStore.handler = { request in
            counter.mutate { $0 += 1 }
            let attempt = counter.value
            if attempt == 1 { throw URLError(.timedOut) }
            let json = #"{"results":[{"artworkUrl100":"https://cdn.example/100x100.jpg"}]}"#
            return (MockURLProtocol.httpResponse(for: request, status: 200), Data(json.utf8))
        }

        let first = await fetchLinks(track: "Retry", artist: "Artist")
        let second = await fetchLinks(track: "Retry", artist: "Artist")

        XCTAssertNil(first.artworkURL)
        XCTAssertEqual(second.artworkURL, "https://cdn.example/512x512.jpg")
        XCTAssertEqual(counter.value, 2)
    }

    func testServerFailureIsRetriedInsteadOfNegativeCached() async {
        let counter = ThreadSafeBox(0)
        handlerStore.handler = { request in
            counter.mutate { $0 += 1 }
            let attempt = counter.value
            if attempt == 1 {
                return (MockURLProtocol.httpResponse(for: request, status: 503), Data())
            }
            return (
                MockURLProtocol.httpResponse(for: request, status: 200),
                Data(#"{"results":[]}"#.utf8)
            )
        }

        _ = await fetchLinks(track: "Retry 503", artist: "Artist")
        _ = await fetchLinks(track: "Retry 503", artist: "Artist")

        XCTAssertEqual(counter.value, 2)
        XCTAssertTrue(service.hasAttemptedTrackLinks(track: "Retry 503", artist: "Artist"))
    }

    func testFetchTrackLinksPopulatesCache() async {
        handlerStore.handler = { request in
            let json = #"{"results":[{"artworkUrl100":"https://cdn.example/100x100.jpg","trackId":7}]}"#
            return (MockURLProtocol.httpResponse(for: request, status: 200), Data(json.utf8))
        }

        _ = await fetchLinks(track: "Cached", artist: "Artist")

        let cached = service.cachedTrackLinks(track: "Cached", artist: "Artist")
        XCTAssertEqual(cached.artworkURL, "https://cdn.example/512x512.jpg")
        XCTAssertNil(
            service.cachedArtworkURL(track: "cached", artist: "artist"),
            "Cache keys must preserve track and artist case"
        )
    }

    func testStructuredCacheKeysKeepDelimiterContainingTracksDistinct() async {
        let counter = ThreadSafeBox(0)
        MockURLProtocol.requestHandler = { request in
            guard let url = request.url,
                  let term = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                    .queryItems?
                    .first(where: { $0.name == "term" })?
                    .value
            else { throw URLError(.badURL) }

            let marker: String
            switch term {
            case "C A|B":
                marker = "first"
            case "B|C A":
                marker = "second"
            default:
                throw URLError(.badServerResponse)
            }

            counter.mutate { $0 += 1 }
            let json = #"{"results":[{"artworkUrl100":"https://cdn.example/\#(marker)/100x100.jpg"}]}"#
            return (MockURLProtocol.httpResponse(for: request, status: 200), Data(json.utf8))
        }

        let first = await fetchLinks(track: "C", artist: "A|B")
        let second = await fetchLinks(track: "B|C", artist: "A")

        XCTAssertEqual(first.artworkURL, "https://cdn.example/first/512x512.jpg")
        XCTAssertEqual(second.artworkURL, "https://cdn.example/second/512x512.jpg")
        XCTAssertEqual(counter.value, 2)
        XCTAssertEqual(service.cacheStats().entryCount, 2)
    }

    func testMissIsNotRequeriedWithinTTL() async {
        let counter = ThreadSafeBox(0)
        handlerStore.handler = { request in
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

        handlerStore.handler = { request in
            let json = #"{"results":[{"artworkUrl100":"https://cdn.example/100x100.jpg","trackId":7}]}"#
            return (MockURLProtocol.httpResponse(for: request, status: 200), Data(json.utf8))
        }

        // First instance fetches + persists to disk.
        let first = ArtworkService(
            session: MockURLProtocol.makeSession(handlerStore: handlerStore),
            persistenceURL: url
        )
        _ = await withCheckedContinuation { (cont: CheckedContinuation<TrackLinks, Never>) in
            first.fetchTrackLinks(track: "Persisted", artist: "Artist") { cont.resume(returning: $0) }
        }

        // Wait for the async disk write to land.
        let wrote = await waitUntil { FileManager.default.fileExists(atPath: url.path) }
        XCTAssertTrue(wrote, "Cache file should be written within the timeout")

        // Second instance loads from the same file, no network.
        let second = ArtworkService(
            session: MockURLProtocol.makeSession(handlerStore: handlerStore),
            persistenceURL: url
        )
        let cached = second.cachedTrackLinks(track: "Persisted", artist: "Artist")
        XCTAssertEqual(cached.artworkURL, "https://cdn.example/512x512.jpg")
    }

    func testClearCacheEmptiesMemoryAndDisk() async {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("artwork-test-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }

        handlerStore.handler = { request in
            let json = #"{"results":[{"artworkUrl100":"https://cdn.example/100x100.jpg","trackId":7}]}"#
            return (MockURLProtocol.httpResponse(for: request, status: 200), Data(json.utf8))
        }

        let svc = ArtworkService(session: MockURLProtocol.makeSession(handlerStore: handlerStore), persistenceURL: url)
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

    func testClearCacheRejectsOldResponseAndStartsFreshGeneration() async {
        let gate = ArtworkRequestGate()
        defer { gate.releaseAll() }
        MockURLProtocol.requestHandler = { request in
            try gate.response(for: request)
        }

        let staleCompletion = expectation(description: "stale request completes")
        let staleLinks = ThreadSafeBox<TrackLinks?>(nil)
        service.fetchTrackLinks(track: "Same", artist: "Artist") { links in
            staleLinks.set(links)
            staleCompletion.fulfill()
        }
        guard await waitUntil({ gate.requestCount == 1 }) else {
            XCTFail("First request did not start")
            return
        }

        service.clearCache()

        gate.releaseFirst()
        await fulfillment(of: [staleCompletion], timeout: 1)

        XCTAssertEqual(staleLinks.value?.artworkURL, "https://cdn.example/stale/512x512.jpg")
        XCTAssertNil(service.cachedArtworkURL(track: "Same", artist: "Artist"))
        XCTAssertFalse(service.hasAttemptedTrackLinks(track: "Same", artist: "Artist"))

        let freshLinks = await fetchLinks(track: "Same", artist: "Artist")

        XCTAssertEqual(freshLinks.artworkURL, "https://cdn.example/fresh/512x512.jpg")
        XCTAssertEqual(
            service.cachedArtworkURL(track: "Same", artist: "Artist"),
            "https://cdn.example/fresh/512x512.jpg"
        )
        XCTAssertEqual(service.cacheStats().entryCount, 1)
        XCTAssertEqual(gate.requestCount, 2)
    }

    func testCachedResultIsServedWithoutHittingNetwork() async {
        handlerStore.handler = { request in
            let json = #"{"results":[{"artworkUrl100":"https://cdn.example/100x100.jpg","trackId":7}]}"#
            return (MockURLProtocol.httpResponse(for: request, status: 200), Data(json.utf8))
        }
        _ = await fetchLinks(track: "Track", artist: "Artist")

        // Any further network call now fails. A cache hit must avoid it.
        handlerStore.handler = { _ in throw URLError(.notConnectedToInternet) }
        let links = await fetchLinks(track: "Track", artist: "Artist")

        XCTAssertEqual(links.artworkURL, "https://cdn.example/512x512.jpg")
    }
}

/// Holds the first URLProtocol response so cache-generation ordering is fully
/// deterministic instead of depending on scheduler timing.
private final class ArtworkRequestGate: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    private let firstRelease = DispatchSemaphore(value: 0)

    var requestCount: Int {
        lock.withLock { count }
    }

    func response(for request: URLRequest) throws -> (HTTPURLResponse, Data) {
        let requestNumber = lock.withLock {
            count += 1
            return count
        }

        let marker: String
        switch requestNumber {
        case 1:
            marker = "stale"
        case 2:
            marker = "fresh"
        default:
            throw URLError(.badServerResponse)
        }

        if requestNumber == 1 {
            guard firstRelease.wait(timeout: .now() + 2) == .success else {
                throw URLError(.timedOut)
            }
        }
        let json = #"{"results":[{"artworkUrl100":"https://cdn.example/\#(marker)/100x100.jpg"}]}"#
        return (MockURLProtocol.httpResponse(for: request, status: 200), Data(json.utf8))
    }

    func releaseFirst() {
        firstRelease.signal()
    }

    func releaseAll() {
        firstRelease.signal()
    }
}
