//
//  MonthlyWrapTests.swift
//  WolfWave
//
//  Created by Nathanial Henniges on 2026-05-22.
//  Copyright © 2026 MrDemonWolf, Inc. All rights reserved.
//

import Testing
import Foundation
import SwiftUI
@testable import WolfWave

/// Tests for the monthly "wrapped"-style summary builder.
@MainActor
@Suite("Monthly Wrap Tests")
struct MonthlyWrapTests {

    // MARK: - Helpers

    private var calendar: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        return cal
    }

    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.hour = 12
        return calendar.date(from: components)!
    }

    private func record(track: String, artist: String, at date: Date) -> PlayRecord {
        PlayRecord(timestamp: date, track: track, artist: artist, album: "Album",
                   duration: 200, playedSeconds: 180)
    }

    // MARK: - Tests

    @Test("Only plays within the target month are counted")
    func testMonthFiltering() {
        let records = [
            record(track: "May A", artist: "X", at: date(2026, 5, 3)),
            record(track: "May B", artist: "X", at: date(2026, 5, 20)),
            record(track: "April", artist: "X", at: date(2026, 4, 28)),
            record(track: "June", artist: "X", at: date(2026, 6, 1)),
        ]
        let wrap = MonthlyWrap.data(from: records, month: date(2026, 5, 15), calendar: calendar)
        #expect(wrap.totalPlays == 2)
        #expect(wrap.hasData)
        #expect(wrap.monthLabel.contains("2026"))
    }

    @Test("A month with no plays has no data")
    func testEmptyMonth() {
        let records = [record(track: "April", artist: "X", at: date(2026, 4, 10))]
        let wrap = MonthlyWrap.data(from: records, month: date(2026, 5, 15), calendar: calendar)
        #expect(!wrap.hasData)
        #expect(wrap.totalPlays == 0)
        #expect(wrap.topArtist == nil)
    }

    @Test("A month with exactly one play reports that single play as its top")
    func testSinglePlayMonth() {
        let records = [record(track: "Solo", artist: "Lonely", at: date(2026, 5, 9))]
        let wrap = MonthlyWrap.data(from: records, month: date(2026, 5, 15), calendar: calendar)
        #expect(wrap.hasData)
        #expect(wrap.totalPlays == 1)
        #expect(wrap.uniqueArtists == 1)
        #expect(wrap.uniqueTracks == 1)
        #expect(wrap.topArtist?.name == "Lonely")
        #expect(wrap.topTrack?.name == "Solo")
        #expect(wrap.topTrack?.count == 1)
        #expect(wrap.busiestDay?.count == 1)
    }

    @Test("Plays on the first and last day of the month are both counted")
    func testMonthBoundaryIncludesFirstAndLastDay() {
        let records = [
            record(track: "FirstDay", artist: "X", at: date(2026, 5, 1)),
            record(track: "LastDay", artist: "X", at: date(2026, 5, 31)),
            // Just outside the May window on either side (must be excluded).
            record(track: "AprilEnd", artist: "X", at: date(2026, 4, 30)),
            record(track: "JuneStart", artist: "X", at: date(2026, 6, 1)),
        ]
        let wrap = MonthlyWrap.data(from: records, month: date(2026, 5, 15), calendar: calendar)
        #expect(wrap.totalPlays == 2)
        #expect(wrap.uniqueTracks == 2)
    }

    @Test("Top artist and track reflect the busiest entries")
    func testTopEntries() {
        let records = [
            record(track: "Hit", artist: "Star", at: date(2026, 5, 1)),
            record(track: "Hit", artist: "Star", at: date(2026, 5, 2)),
            record(track: "Hit", artist: "Star", at: date(2026, 5, 3)),
            record(track: "Other", artist: "Nobody", at: date(2026, 5, 4)),
        ]
        let wrap = MonthlyWrap.data(from: records, month: date(2026, 5, 15), calendar: calendar)
        #expect(wrap.topArtist?.name == "Star")
        #expect(wrap.topTrack?.name == "Hit")
        #expect(wrap.topTrack?.count == 3)
        #expect(wrap.uniqueArtists == 2)
        #expect(wrap.uniqueTracks == 2)
    }

    @Test("Busiest day is the day with the most plays")
    func testBusiestDay() {
        let records = [
            record(track: "A", artist: "X", at: date(2026, 5, 10)),
            record(track: "B", artist: "X", at: date(2026, 5, 10)),
            record(track: "C", artist: "X", at: date(2026, 5, 11)),
        ]
        let wrap = MonthlyWrap.data(from: records, month: date(2026, 5, 15), calendar: calendar)
        #expect(wrap.busiestDay?.count == 2)
    }

    @Test("MonthlyWrapCard renders without crashing on the WolfWave gradient")
    func testCardRenders() {
        let data = MonthlyWrap.data(from: [], month: date(2026, 5, 15), calendar: calendar)
        let renderer = ImageRenderer(content: MonthlyWrapCard(data: data).frame(width: 380))
        #expect(renderer.nsImage != nil)
    }
}
