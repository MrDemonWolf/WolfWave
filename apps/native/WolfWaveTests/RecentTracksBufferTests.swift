//
//  RecentTracksBufferTests.swift
//  WolfWaveTests
//
//  Created by MrDemonWolf, Inc. on 5/22/26.
//

import XCTest
@testable import WolfWave

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
        XCTAssertEqual(track.displayLabel, "Bohemian Rhapsody — Queen")
    }

    func testDisplayLabelWithoutArtist() {
        let track = RecentTrack(title: "Untitled", artist: "", playedAt: Date())
        XCTAssertEqual(track.displayLabel, "Untitled")
    }

    func testDefaultCapacityUsesAppConstant() {
        let buffer = RecentTracksBuffer()
        XCTAssertEqual(buffer.maxEntries, AppConstants.RecentlyPlayed.maxEntries)
    }
}
