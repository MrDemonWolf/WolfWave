//
//  TrackInfoCommandTests.swift
//  WolfWaveTests
//
//  Created by MrDemonWolf, Inc. on 2/13/26.
//

import XCTest
@testable import WolfWave

@MainActor
final class TrackInfoCommandTests: XCTestCase {

    // MARK: - Fixtures

    private struct Fixture {
        let triggers: [String]
        let description: String
        let defaultMessage: String
        let primaryTrigger: String
        let altCaseTriggers: [String]
        let trackText: String
    }

    private static let current = Fixture(
        triggers: ["!song", "!currentsong", "!nowplaying"],
        description: "Displays the currently playing track",
        defaultMessage: "No track currently playing",
        primaryTrigger: "!song",
        altCaseTriggers: ["!SONG", "!Song", "!NowPlaying"],
        trackText: "Daft Punk - Around The World"
    )

    private static let last = Fixture(
        triggers: ["!last", "!lastsong", "!prevsong"],
        description: "Displays the last played track",
        defaultMessage: "No previous track available",
        primaryTrigger: "!last",
        altCaseTriggers: ["!LAST", "!LastSong", "!PREVSONG"],
        trackText: "Daft Punk - One More Time"
    )

    private func makeCommand(_ fixture: Fixture) -> TrackInfoCommand {
        TrackInfoCommand(
            triggers: fixture.triggers,
            description: fixture.description,
            defaultMessage: fixture.defaultMessage
        )
    }

    // MARK: - Shared assertions

    private func assertAllTriggersMatch(_ fixture: Fixture) {
        let cmd = makeCommand(fixture)
        cmd.getTrackInfo = { "Artist - Song" }
        for trigger in fixture.triggers {
            XCTAssertNotNil(cmd.execute(message: trigger), "Expected match for \(trigger)")
        }
    }

    private func assertCaseInsensitive(_ fixture: Fixture) {
        let cmd = makeCommand(fixture)
        cmd.getTrackInfo = { "Artist - Song" }
        for trigger in fixture.altCaseTriggers {
            XCTAssertNotNil(cmd.execute(message: trigger), "Expected case-insensitive match for \(trigger)")
        }
    }

    private func assertNonMatchingReturnsNil(_ fixture: Fixture) {
        let cmd = makeCommand(fixture)
        cmd.getTrackInfo = { "Artist - Song" }
        XCTAssertNil(cmd.execute(message: "hello world"))
    }

    private func assertDefaultMessageWhenNoCallback(_ fixture: Fixture) {
        let cmd = makeCommand(fixture)
        XCTAssertEqual(cmd.execute(message: fixture.primaryTrigger), fixture.defaultMessage)
    }

    private func assertCallbackValueReturned(_ fixture: Fixture) {
        let cmd = makeCommand(fixture)
        cmd.getTrackInfo = { fixture.trackText }
        XCTAssertEqual(cmd.execute(message: fixture.primaryTrigger), fixture.trackText)
    }

    private func assertDisabledReturnsNil(_ fixture: Fixture) {
        let cmd = makeCommand(fixture)
        cmd.getTrackInfo = { "Artist - Song" }
        cmd.isEnabled = { false }
        XCTAssertNil(cmd.execute(message: fixture.primaryTrigger))
    }

    private func assertEnabledReturnsResponse(_ fixture: Fixture) {
        let cmd = makeCommand(fixture)
        cmd.getTrackInfo = { "Artist - Song" }
        cmd.isEnabled = { true }
        XCTAssertNotNil(cmd.execute(message: fixture.primaryTrigger))
    }

    private func assertDefaultsToEnabled(_ fixture: Fixture) {
        let cmd = makeCommand(fixture)
        cmd.getTrackInfo = { "Artist - Song" }
        XCTAssertNotNil(cmd.execute(message: fixture.primaryTrigger))
    }

    private func assertLongResponseTruncatedTo500(_ fixture: Fixture) throws {
        let cmd = makeCommand(fixture)
        cmd.getTrackInfo = { String(repeating: "a", count: 600) }
        let result = try XCTUnwrap(cmd.execute(message: fixture.primaryTrigger))
        XCTAssertEqual(result.count, 500)
        XCTAssertTrue(result.hasSuffix("..."))
    }

    private func assertExactly500NotTruncated(_ fixture: Fixture) throws {
        let cmd = makeCommand(fixture)
        cmd.getTrackInfo = { String(repeating: "a", count: 500) }
        let result = try XCTUnwrap(cmd.execute(message: fixture.primaryTrigger))
        XCTAssertEqual(result.count, 500)
        XCTAssertFalse(result.hasSuffix("..."))
    }

    private func assertBoundary501Truncates(_ fixture: Fixture) throws {
        let cmd = makeCommand(fixture)
        cmd.getTrackInfo = { String(repeating: "b", count: 501) }
        let result = try XCTUnwrap(cmd.execute(message: fixture.primaryTrigger))
        XCTAssertEqual(result.count, 500)
        XCTAssertTrue(result.hasSuffix("..."))
    }

    private func assertTrailingTextStillMatches(_ fixture: Fixture) {
        let cmd = makeCommand(fixture)
        cmd.getTrackInfo = { "Artist - Song" }
        XCTAssertNotNil(cmd.execute(message: "\(fixture.primaryTrigger) extra stuff"))
    }

    private func assertTriggersArrayContents(_ fixture: Fixture) {
        let cmd = makeCommand(fixture)
        XCTAssertEqual(cmd.triggers, fixture.triggers)
    }

    private func assertDescriptionValue(_ fixture: Fixture) {
        let cmd = makeCommand(fixture)
        XCTAssertEqual(cmd.description, fixture.description)
    }

    // MARK: - Current Track tests (!song / !currentsong / !nowplaying)

    func testCurrent_allTriggersMatch() { assertAllTriggersMatch(Self.current) }
    func testCurrent_caseInsensitive() { assertCaseInsensitive(Self.current) }
    func testCurrent_nonMatchingReturnsNil() { assertNonMatchingReturnsNil(Self.current) }
    func testCurrent_defaultMessageWhenNoCallback() { assertDefaultMessageWhenNoCallback(Self.current) }
    func testCurrent_callbackValueReturned() { assertCallbackValueReturned(Self.current) }
    func testCurrent_disabledReturnsNil() { assertDisabledReturnsNil(Self.current) }
    func testCurrent_enabledReturnsResponse() { assertEnabledReturnsResponse(Self.current) }
    func testCurrent_defaultsToEnabled() { assertDefaultsToEnabled(Self.current) }
    func testCurrent_longResponseTruncatedTo500() throws { try assertLongResponseTruncatedTo500(Self.current) }
    func testCurrent_exactly500NotTruncated() throws { try assertExactly500NotTruncated(Self.current) }
    func testCurrent_boundary501Truncates() throws { try assertBoundary501Truncates(Self.current) }
    func testCurrent_trailingTextStillMatches() { assertTrailingTextStillMatches(Self.current) }
    func testCurrent_triggersArrayContents() { assertTriggersArrayContents(Self.current) }
    func testCurrent_descriptionValue() { assertDescriptionValue(Self.current) }

    func testCurrent_defaultCooldownValues() throws {
        let cmd = makeCommand(Self.current)
        XCTAssertEqual(cmd.globalCooldown, 15.0)
        XCTAssertEqual(cmd.userCooldown, 15.0)
    }

    // MARK: - Last Track tests (!last / !lastsong / !prevsong)

    func testLast_allTriggersMatch() { assertAllTriggersMatch(Self.last) }
    func testLast_caseInsensitive() { assertCaseInsensitive(Self.last) }
    func testLast_nonMatchingReturnsNil() { assertNonMatchingReturnsNil(Self.last) }
    func testLast_defaultMessageWhenNoCallback() { assertDefaultMessageWhenNoCallback(Self.last) }
    func testLast_callbackValueReturned() { assertCallbackValueReturned(Self.last) }
    func testLast_disabledReturnsNil() { assertDisabledReturnsNil(Self.last) }
    func testLast_enabledReturnsResponse() { assertEnabledReturnsResponse(Self.last) }
    func testLast_defaultsToEnabled() { assertDefaultsToEnabled(Self.last) }
    func testLast_longResponseTruncatedTo500() throws { try assertLongResponseTruncatedTo500(Self.last) }
    func testLast_exactly500NotTruncated() throws { try assertExactly500NotTruncated(Self.last) }
    func testLast_trailingTextStillMatches() { assertTrailingTextStillMatches(Self.last) }
    func testLast_triggersArrayContents() { assertTriggersArrayContents(Self.last) }
}
