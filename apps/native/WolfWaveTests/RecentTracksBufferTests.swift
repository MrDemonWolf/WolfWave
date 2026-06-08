//
//  RecentTracksBufferTests.swift
//  WolfWave
//
//  Created by Nathanial Henniges on 2026-05-22.
//  Copyright © 2026 MrDemonWolf, Inc. All rights reserved.
//

import XCTest
@testable import WolfWave

@MainActor
final class RecentTracksBufferTests: XCTestCase {

    private func makeTrack(_ title: String, _ artist: String = "Artist") -> RecentTrack {
        RecentTrack(title: title, artist: artist, playedAt: Date())
    }

    func testStartsEmpty() {
        let buffer = RecentTracksBuffer(maxEntries: 5)
        XCTAssertTrue(buffer.isEmpty)
        XCTAssertEqual(buffer.count, 0)
        XCTAssertEqual(buffer.entries, [])
    }

    func testPushAddsToFront() {
        var buffer = RecentTracksBuffer(maxEntries: 5)
        buffer.push(makeTrack("A"))
        buffer.push(makeTrack("B"))
        buffer.push(makeTrack("C"))
        XCTAssertEqual(buffer.entries.map(\.title), ["C", "B", "A"])
    }

    func testHeadDuplicateIsIgnored() {
        var buffer = RecentTracksBuffer(maxEntries: 5)
        buffer.push(makeTrack("A"))
        buffer.push(makeTrack("A"))
        buffer.push(makeTrack("A"))
        XCTAssertEqual(buffer.count, 1)
    }

    func testNonHeadDuplicateMovesToFront() {
        var buffer = RecentTracksBuffer(maxEntries: 5)
        buffer.push(makeTrack("A"))
        buffer.push(makeTrack("B"))
        buffer.push(makeTrack("C"))
        buffer.push(makeTrack("A"))
        XCTAssertEqual(buffer.entries.map(\.title), ["A", "C", "B"])
    }

    func testMaxEntriesTrimsTail() {
        var buffer = RecentTracksBuffer(maxEntries: 3)
        buffer.push(makeTrack("A"))
        buffer.push(makeTrack("B"))
        buffer.push(makeTrack("C"))
        buffer.push(makeTrack("D"))
        buffer.push(makeTrack("E"))
        XCTAssertEqual(buffer.entries.map(\.title), ["E", "D", "C"])
    }

    func testEqualityIgnoresPlayedAt() {
        let a = RecentTrack(title: "Song", artist: "Artist", playedAt: Date(timeIntervalSince1970: 0))
        let b = RecentTrack(title: "Song", artist: "Artist", playedAt: Date(timeIntervalSince1970: 999))
        XCTAssertEqual(a, b)
    }

    func testDisplayLabelWithArtist() {
        let track = RecentTrack(title: "Bohemian Rhapsody", artist: "Queen", playedAt: Date())
        XCTAssertEqual(track.displayLabel, "Bohemian Rhapsody · Queen")
    }

    func testDisplayLabelWithoutArtist() {
        let track = RecentTrack(title: "Untitled", artist: "", playedAt: Date())
        XCTAssertEqual(track.displayLabel, "Untitled")
    }

    func testDefaultCapacityUsesAppConstant() {
        let buffer = RecentTracksBuffer()
        XCTAssertEqual(buffer.maxEntries, AppConstants.RecentlyPlayed.maxEntries)
    }

    // MARK: - Capacity clamp (regression lock)
    //
    // Before the clamp, `init` had `precondition(maxEntries > 0)`: a hard trap
    // that crashed a shipped build on a non-positive capacity. These cases prove
    // the clamp floors at 1 instead of trapping. (If the trap ever comes back,
    // constructing with 0 here aborts the whole test host.)

    func testZeroMaxEntriesClampsToOne() {
        let buffer = RecentTracksBuffer(maxEntries: 0)
        XCTAssertEqual(buffer.maxEntries, 1)
    }

    func testNegativeMaxEntriesClampsToOne() {
        let buffer = RecentTracksBuffer(maxEntries: -5)
        XCTAssertEqual(buffer.maxEntries, 1)
    }

    func testClampedBufferKeepsNewestAndStillDedupsHead() {
        var buffer = RecentTracksBuffer(maxEntries: 0) // clamps to 1
        buffer.push(makeTrack("A"))
        buffer.push(makeTrack("B"))
        XCTAssertEqual(buffer.entries.map(\.title), ["B"]) // tail-trim keeps newest
        buffer.push(makeTrack("B"))                        // head dup ignored, no growth
        XCTAssertEqual(buffer.count, 1)
    }
}
