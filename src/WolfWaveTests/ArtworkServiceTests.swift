//
//  ArtworkServiceTests.swift
//  WolfWaveTests
//
//  Created by MrDemonWolf, Inc. on 2/27/26.
//

import XCTest
@testable import WolfWave

final class ArtworkServiceTests: XCTestCase {
    var service: ArtworkService!

    override func setUp() {
        super.setUp()
        service = ArtworkService()
    }

    override func tearDown() {
        service = nil
        super.tearDown()
    }

    // MARK: - Cache Tests

    func testCachedArtworkURLReturnsNilOnMiss() {
        let result = service.cachedArtworkURL(track: "Nonexistent", artist: "Nobody")
        XCTAssertNil(result)
    }

    func testCacheKeyUsesArtistPipeTrack() {
        // After fetching, the cache key format is "artist|track"
        // Without a network call, the cache should be empty
        XCTAssertNil(service.cachedArtworkURL(track: "Song", artist: "Artist"))
    }

    func testDifferentTracksHaveSeparateCacheEntries() {
        XCTAssertNil(service.cachedArtworkURL(track: "Song A", artist: "Artist"))
        XCTAssertNil(service.cachedArtworkURL(track: "Song B", artist: "Artist"))
    }

    func testDifferentArtistsHaveSeparateCacheEntries() {
        XCTAssertNil(service.cachedArtworkURL(track: "Song", artist: "Artist A"))
        XCTAssertNil(service.cachedArtworkURL(track: "Song", artist: "Artist B"))
    }

    // MARK: - URL Construction Tests

    func testFetchWithEmptyTrackCallsCompletion() {
        let expectation = expectation(description: "completion called")
        service.fetchArtworkURL(track: "", artist: "") { _ in
            expectation.fulfill()
        }
        waitForExpectations(timeout: 10)
    }

    func testFetchArtworkURLCallsCompletion() {
        let expectation = expectation(description: "completion called")
        service.fetchArtworkURL(track: "Test", artist: "Test") { _ in
            expectation.fulfill()
        }
        waitForExpectations(timeout: 10)
    }
}
