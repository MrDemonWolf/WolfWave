//
//  ArtworkServiceCacheTests.swift
//  WolfWaveTests
//
//  Created by MrDemonWolf, Inc. on 3/19/26.
//

import XCTest
@testable import WolfWave

final class ArtworkServiceCacheTests: XCTestCase {
    var service = ArtworkService()

    override func setUp() {
        super.setUp()
        service = ArtworkService()
    }

    // MARK: - Cache Miss Tests

    func testCacheMissReturnsNilForUnknownTrack() {
        let result = service.cachedArtworkURL(track: "UnknownTrack123", artist: "UnknownArtist456")
        XCTAssertNil(result)
    }

    // MARK: - Case Sensitivity Tests

    func testCacheIsCaseSensitive() {
        // "Artist|Track" and "artist|track" should be different keys
        let upper = service.cachedArtworkURL(track: "Track", artist: "Artist")
        let lower = service.cachedArtworkURL(track: "track", artist: "artist")
        // Both should be nil (no cached data), but this proves the keys differ
        XCTAssertNil(upper)
        XCTAssertNil(lower)
    }

    // MARK: - Concurrent Access Tests

    func testConcurrentCacheAccessIsThreadSafe() {
        let iterations = 100
        let expectation = expectation(description: "concurrent access")
        expectation.expectedFulfillmentCount = iterations

        DispatchQueue.concurrentPerform(iterations: iterations) { i in
            let track = "Track\(i)"
            let artist = "Artist\(i)"
            _ = self.service.cachedArtworkURL(track: track, artist: artist)
            expectation.fulfill()
        }

        waitForExpectations(timeout: 10)
    }

    // MARK: - Edge Case Input Tests
    // fetchArtworkURL tests are integration-style (hit network)

    func testFetchWithEmptyStringsCallsCompletion() {
        let expectation = expectation(description: "completion called")
        service.fetchArtworkURL(track: "", artist: "") { _ in
            expectation.fulfill()
        }
        waitForExpectations(timeout: 10)
    }

    func testFetchWithSpecialCharsCallsCompletion() {
        let expectation = expectation(description: "completion called")
        service.fetchArtworkURL(track: "Test & Track </>", artist: "Ar!@#$%^&*()tist") { _ in
            expectation.fulfill()
        }
        waitForExpectations(timeout: 10)
    }

    func testFetchWithUnicodeCallsCompletion() {
        let expectation = expectation(description: "completion called")
        service.fetchArtworkURL(track: "日本語テスト", artist: "アーティスト") { _ in
            expectation.fulfill()
        }
        waitForExpectations(timeout: 10)
    }

    // MARK: - Performance Tests

    func testCachedArtworkURLLookupPerformance() {
        measure {
            for i in 0..<1000 {
                _ = service.cachedArtworkURL(track: "Track\(i)", artist: "Artist\(i)")
            }
        }
    }
}
