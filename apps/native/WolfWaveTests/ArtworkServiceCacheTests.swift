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
        // Pre-populate the cache with a known URL for the uppercase key
        let expectation = expectation(description: "fetch completes")
        let testTrack = "UniqueTestTrack_\(UUID().uuidString)"
        service.fetchArtworkURL(track: testTrack, artist: "Artist") { _ in
            expectation.fulfill()
        }
        waitForExpectations(timeout: 10)

        // Now check: the lowercase variant should NOT match the cached uppercase entry
        let upperResult = service.cachedArtworkURL(track: testTrack, artist: "Artist")
        let lowerResult = service.cachedArtworkURL(track: testTrack.lowercased(), artist: "artist")

        // If cache is case-sensitive, the lowercase lookup must differ from uppercase
        // (either nil because it was never fetched, or a different value)
        if upperResult != nil {
            XCTAssertNotEqual(upperResult, lowerResult,
                "Case-sensitive cache should not return the same value for differently-cased keys")
        } else {
            // Even if the network returned nil, lowercase should also be nil (no cross-contamination)
            XCTAssertNil(lowerResult,
                "Lowercase key should not return a cached value when only uppercase was fetched")
        }
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
