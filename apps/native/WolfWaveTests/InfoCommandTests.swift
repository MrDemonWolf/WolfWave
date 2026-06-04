//
//  InfoCommandTests.swift
//  WolfWave
//
//  Created by Nathanial Henniges on 2026-06-03.
//  Copyright © 2026 MrDemonWolf, Inc. All rights reserved.
//

import XCTest
@testable import WolfWave

/// Coverage for the generic `InfoCommand` static-reply bot command, exercised
/// through the `!wolfwave` shape: opt-in (default off) gating, alias matching,
/// case-insensitivity, lazy message resolution, and 500-char truncation.
///
/// Uses scoped, test-only UserDefaults keys in `.standard` (the store
/// `Preferences` and `allTriggers` read from) and clears them in tear-down. No
/// Keychain access.
@MainActor
final class InfoCommandTests: XCTestCase {

    private let enabledKey = "test.infoCommand.enabled"
    private let aliasesKey = "test.infoCommand.aliases"

    override func setUp() {
        super.setUp()
        UserDefaults.standard.removeObject(forKey: enabledKey)
        UserDefaults.standard.removeObject(forKey: aliasesKey)
    }

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: enabledKey)
        UserDefaults.standard.removeObject(forKey: aliasesKey)
        super.tearDown()
    }

    // MARK: - Helpers

    private func makeCommand(
        message: @escaping () -> String = { "Hello from WolfWave" }
    ) -> InfoCommand {
        InfoCommand(
            triggers: ["!wolfwave"],
            description: "Info",
            enabledDefaultsKey: enabledKey,
            aliasesKey: aliasesKey,
            messageProvider: message
        )
    }

    private func enable() { UserDefaults.standard.set(true, forKey: enabledKey) }

    // MARK: - Enable gating

    func testDisabledByDefault_returnsNil() {
        XCTAssertNil(makeCommand().execute(message: "!wolfwave"))
    }

    func testExplicitlyDisabled_returnsNil() {
        UserDefaults.standard.set(false, forKey: enabledKey)
        XCTAssertNil(makeCommand().execute(message: "!wolfwave"))
    }

    func testEnabled_returnsMessage() {
        enable()
        XCTAssertEqual(makeCommand().execute(message: "!wolfwave"), "Hello from WolfWave")
    }

    // MARK: - Trigger matching

    func testNonMatchingReturnsNil() {
        enable()
        XCTAssertNil(makeCommand().execute(message: "!song"))
    }

    func testCaseInsensitive() {
        enable()
        let cmd = makeCommand()
        XCTAssertNotNil(cmd.execute(message: "!WOLFWAVE"))
        XCTAssertNotNil(cmd.execute(message: "!WolfWave"))
    }

    func testTrailingTextStillMatches() {
        enable()
        XCTAssertNotNil(makeCommand().execute(message: "!wolfwave please"))
    }

    func testLeadingWhitespaceTokenStillMatches() {
        enable()
        XCTAssertNotNil(makeCommand().execute(message: "   !wolfwave"))
    }

    // MARK: - Custom aliases

    func testCustomAliasMatches() {
        enable()
        UserDefaults.standard.set("ww, app", forKey: aliasesKey)
        let cmd = makeCommand()
        XCTAssertNotNil(cmd.execute(message: "!ww"))
        XCTAssertNotNil(cmd.execute(message: "!app"))
    }

    func testAliasStoredWithoutBangIsNormalized() {
        enable()
        UserDefaults.standard.set("ww", forKey: aliasesKey)
        XCTAssertNotNil(makeCommand().execute(message: "!ww"))
    }

    // MARK: - Lazy resolution + truncation

    func testMessageResolvedAtCallTime() {
        enable()
        var dynamic = "first"
        let cmd = makeCommand(message: { dynamic })
        XCTAssertEqual(cmd.execute(message: "!wolfwave"), "first")
        dynamic = "second"
        XCTAssertEqual(cmd.execute(message: "!wolfwave"), "second")
    }

    func testLongMessageTruncatedTo500() throws {
        enable()
        let cmd = makeCommand(message: { String(repeating: "a", count: 600) })
        let result = try XCTUnwrap(cmd.execute(message: "!wolfwave"))
        XCTAssertEqual(result.count, 500)
        XCTAssertTrue(result.hasSuffix("..."))
    }

    // MARK: - Metadata

    func testTriggersDescriptionAndAliasesKeyExposed() {
        let cmd = makeCommand()
        XCTAssertEqual(cmd.triggers, ["!wolfwave"])
        XCTAssertEqual(cmd.description, "Info")
        XCTAssertEqual(cmd.aliasesKey, aliasesKey)
    }
}
