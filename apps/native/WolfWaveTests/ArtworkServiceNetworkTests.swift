//
//  ArtworkServiceNetworkTests.swift
//  WolfWaveTests
//
//  Created by MrDemonWolf, Inc. on 5/22/26.
//

import XCTest

@testable import WolfWave

// MARK: - ArtworkServiceNetworkTests

/// Covers `ArtworkService` iTunes Search API parsing, error handling, and
/// caching, with the network layer stubbed by `MockURLProtocol`.
final class ArtworkServiceNetworkTests: XCTestCase {

    private var service: ArtworkService!

    override func setUp() {
        super.setUp()
        service = ArtworkService(session: MockURLProtocol.makeSession())
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

    func testCachedResultIsServedWithoutHittingNetwork() async {
        MockURLProtocol.requestHandler = { request in
            let json = #"{"results":[{"artworkUrl100":"https://cdn.example/100x100.jpg","trackId":7}]}"#
            return (MockURLProtocol.httpResponse(for: request, status: 200), Data(json.utf8))
        }
        _ = await fetchLinks(track: "Track", artist: "Artist")

        // Any further network call now fails — a cache hit must avoid it.
        MockURLProtocol.requestHandler = { _ in throw URLError(.notConnectedToInternet) }
        let links = await fetchLinks(track: "Track", artist: "Artist")

        XCTAssertEqual(links.artworkURL, "https://cdn.example/512x512.jpg")
    }
}
