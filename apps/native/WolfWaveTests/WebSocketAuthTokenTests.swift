//
//  WebSocketAuthTokenTests.swift
//  WolfWaveTests
//
//  Copyright © 2026 MrDemonWolf, Inc. All rights reserved.
//

import XCTest

@testable import WolfWave

/// Unit tests for the `WebSocketAuthToken` type — token minting, validation,
/// subprotocol formatting, accept gating, and redaction.
///
/// These deliberately do **not** exercise `currentOrCreate()` / `rotate()`:
/// those round-trip through `KeychainService`, which prompts for Keychain
/// access under the ad-hoc-signed test host and is the kind of dependency
/// CLAUDE.md says unit tests should avoid. Token *generation* is still covered
/// directly via the module-scoped `generate()`, and the handshake/accept path
/// is covered by `WebSocketServerAuthTests`.
final class WebSocketAuthTokenTests: XCTestCase {

    // MARK: - Generation (Keychain-free)

    func testGenerateProduces64HexChars() {
        let token = WebSocketAuthToken.generate()
        XCTAssertEqual(token.count, 64, "32 random bytes → 64 hex chars")
        XCTAssertTrue(WebSocketAuthToken.isValid(token))
    }

    func testGenerateProducesDistinctTokens() {
        var seen = Set<String>()
        for _ in 0..<50 { seen.insert(WebSocketAuthToken.generate()) }
        XCTAssertEqual(seen.count, 50, "generated tokens must not repeat")
    }

    // MARK: - Subprotocol

    func testExpectedSubprotocolPrefixesToken() {
        XCTAssertEqual(
            WebSocketAuthToken.expectedSubprotocol(for: "abc123"),
            "wolfwave.token.abc123"
        )
    }

    // MARK: - Accept gating

    func testShouldAcceptWhenOfferedSubprotocolMatches() {
        let token = "deadbeefcafef00d"
        XCTAssertTrue(
            WebSocketAuthToken.shouldAccept(
                expectedToken: token,
                offeredSubprotocols: ["chat", WebSocketAuthToken.expectedSubprotocol(for: token)]
            )
        )
    }

    func testShouldRejectWhenSubprotocolMissingOrWrong() {
        XCTAssertFalse(
            WebSocketAuthToken.shouldAccept(expectedToken: "abcdef0123456789", offeredSubprotocols: []))
        XCTAssertFalse(
            WebSocketAuthToken.shouldAccept(
                expectedToken: "abcdef0123456789",
                offeredSubprotocols: ["wolfwave.token.wrong"]))
    }

    func testShouldAcceptAnythingWhenExpectedTokenIsNil() {
        XCTAssertTrue(
            WebSocketAuthToken.shouldAccept(expectedToken: nil, offeredSubprotocols: []))
    }

    // MARK: - Validation

    func testIsValidAcceptsHexInLengthRange() {
        XCTAssertTrue(WebSocketAuthToken.isValid(String(repeating: "a", count: 16)))
        XCTAssertTrue(WebSocketAuthToken.isValid(String(repeating: "F", count: 64)))
        XCTAssertTrue(WebSocketAuthToken.isValid(String(repeating: "0", count: 128)))
    }

    func testIsValidRejectsOutOfRangeLengths() {
        XCTAssertFalse(WebSocketAuthToken.isValid(String(repeating: "a", count: 15)))
        XCTAssertFalse(WebSocketAuthToken.isValid(String(repeating: "a", count: 129)))
        XCTAssertFalse(WebSocketAuthToken.isValid(""))
    }

    func testIsValidRejectsNonHexCharacters() {
        // Long enough but contains characters that could break out of a JS
        // string when substituted into widget.html.
        XCTAssertFalse(WebSocketAuthToken.isValid("zzzzzzzzzzzzzzzz"))
        XCTAssertFalse(WebSocketAuthToken.isValid("</script>aaaaaaaa"))
        XCTAssertFalse(WebSocketAuthToken.isValid("abcdef0123456789 "))
    }

    // MARK: - Redaction

    func testRedactKeepsFirstFourCharsOnly() {
        XCTAssertEqual(WebSocketAuthToken.redact("a1b2c3d4e5f6"), "a1b2…")
    }

    func testRedactCollapsesShortTokens() {
        XCTAssertEqual(WebSocketAuthToken.redact("ab"), "…")
        XCTAssertEqual(WebSocketAuthToken.redact("abcd"), "…")
    }

    func testRedactNeverLeaksFullToken() {
        let token = WebSocketAuthToken.generate()
        let redacted = WebSocketAuthToken.redact(token)
        XCTAssertFalse(redacted.contains(String(token.dropFirst(4))))
        XCTAssertLessThanOrEqual(redacted.count, 5)
    }
}
