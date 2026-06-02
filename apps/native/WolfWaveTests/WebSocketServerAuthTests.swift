//
//  WebSocketServerAuthTests.swift
//  WolfWave
//
//  Created by Nathanial Henniges on 2026-05-23.
//  Copyright © 2026 MrDemonWolf, Inc. All rights reserved.
//

import XCTest
@testable import WolfWave

/// Unit tests for the WebSocket auth-token gate.
///
/// The decision logic that backs the `NWProtocolWebSocket` client-request
/// handler in `WebSocketServerService` is intentionally factored out into the
/// pure static helper `WebSocketAuthToken.shouldAccept(...)` so it can be
/// verified without standing up `NWListener` / `NWConnection`. The lifecycle
/// integration tests in `WebSocketServerIntegrationTests` cover the wiring; this
/// file pins down the actual auth contract.
final class WebSocketServerAuthTests: XCTestCase {

    // MARK: - Subprotocol shape

    func testExpectedSubprotocolHasWolfWavePrefix() {
        XCTAssertEqual(
            WebSocketAuthToken.expectedSubprotocol(for: "abcdef1234567890"),
            "wolfwave.token.abcdef1234567890"
        )
    }

    // MARK: - shouldAccept — auth disabled (legacy init)

    func testShouldAcceptIsTrueWhenTokenIsNil() {
        XCTAssertTrue(
            WebSocketAuthToken.shouldAccept(expectedToken: nil, offeredSubprotocols: []),
            "Legacy `init(port:)` (no token) must keep accepting unauthenticated clients"
        )
        XCTAssertTrue(
            WebSocketAuthToken.shouldAccept(expectedToken: nil, offeredSubprotocols: ["whatever"])
        )
    }

    // MARK: - shouldAccept — token configured

    func testRejectsWhenNoSubprotocolOffered() {
        XCTAssertFalse(
            WebSocketAuthToken.shouldAccept(
                expectedToken: "abcdef1234567890",
                offeredSubprotocols: []
            ),
            "Handshake with no Sec-WebSocket-Protocol header must be rejected"
        )
    }

    func testRejectsWhenSubprotocolDoesNotMatch() {
        XCTAssertFalse(
            WebSocketAuthToken.shouldAccept(
                expectedToken: "abcdef1234567890",
                offeredSubprotocols: ["wolfwave.token.deadbeef"]
            )
        )
        XCTAssertFalse(
            WebSocketAuthToken.shouldAccept(
                expectedToken: "abcdef1234567890",
                offeredSubprotocols: ["some.other.protocol", "graphql-ws"]
            )
        )
    }

    func testRejectsRawTokenWithoutPrefix() {
        // Client must offer the full `wolfwave.token.<hex>` form, not the bare token.
        XCTAssertFalse(
            WebSocketAuthToken.shouldAccept(
                expectedToken: "abcdef1234567890",
                offeredSubprotocols: ["abcdef1234567890"]
            )
        )
    }

    func testAcceptsWhenSubprotocolMatches() {
        XCTAssertTrue(
            WebSocketAuthToken.shouldAccept(
                expectedToken: "abcdef1234567890",
                offeredSubprotocols: ["wolfwave.token.abcdef1234567890"]
            )
        )
    }

    func testAcceptsWhenMatchingSubprotocolIsOneOfMany() {
        XCTAssertTrue(
            WebSocketAuthToken.shouldAccept(
                expectedToken: "abcdef1234567890",
                offeredSubprotocols: [
                    "graphql-ws",
                    "wolfwave.token.abcdef1234567890",
                    "json.api.v1",
                ]
            )
        )
    }

    func testCaseSensitiveTokenMatching() {
        // Hex tokens are produced lowercase. A case-mangled offer must not pass —
        // otherwise an attacker that knew the entropy could attempt mixed-case bypass.
        XCTAssertFalse(
            WebSocketAuthToken.shouldAccept(
                expectedToken: "abcdef1234567890",
                offeredSubprotocols: ["wolfwave.token.ABCDEF1234567890"]
            )
        )
    }

    // MARK: - Token shape validation (used before persisting / substituting)

    func testIsValidAcceptsLowercaseHex() {
        XCTAssertTrue(WebSocketAuthToken.isValid("abcdef1234567890"))
    }

    func testIsValidAcceptsUppercaseHex() {
        XCTAssertTrue(WebSocketAuthToken.isValid("ABCDEF1234567890"))
    }

    func testIsValidAcceptsFullLengthGeneratedToken() {
        // The generator emits 64 hex characters (32 random bytes).
        XCTAssertTrue(WebSocketAuthToken.isValid(String(repeating: "a", count: 64)))
    }

    func testIsValidRejectsTooShort() {
        XCTAssertFalse(WebSocketAuthToken.isValid("abc"))
        XCTAssertFalse(WebSocketAuthToken.isValid(String(repeating: "a", count: 15)))
    }

    func testIsValidRejectsTooLong() {
        XCTAssertFalse(WebSocketAuthToken.isValid(String(repeating: "a", count: 129)))
    }

    func testIsValidRejectsEmpty() {
        XCTAssertFalse(WebSocketAuthToken.isValid(""))
    }

    func testIsValidRejectsInjectionAttempts() {
        // The whole point: a user-edited token that could escape the JS string
        // context in `widget.html` must not pass validation.
        XCTAssertFalse(WebSocketAuthToken.isValid("</script><script>alert(1)</script>"))
        XCTAssertFalse(WebSocketAuthToken.isValid("abc'; document.cookie"))
        XCTAssertFalse(WebSocketAuthToken.isValid("0123456789abcdef\""))
        XCTAssertFalse(WebSocketAuthToken.isValid("0123456789abcdef\\"))
    }

    func testIsValidRejectsNonHexCharacters() {
        XCTAssertFalse(WebSocketAuthToken.isValid("ghijklmnopqrstuv"))
        XCTAssertFalse(WebSocketAuthToken.isValid("0123456789abcdef-"))
    }

    // MARK: - Redaction (logging safety)

    func testRedactKeepsOnlyFirstFourChars() {
        XCTAssertEqual(WebSocketAuthToken.redact("abcdef1234567890"), "abcd…")
    }

    func testRedactCollapsesShortInputs() {
        XCTAssertEqual(WebSocketAuthToken.redact("ab"), "…")
        XCTAssertEqual(WebSocketAuthToken.redact(""), "…")
    }

    func testRedactNeverLeaksFullToken() {
        let token = WebSocketAuthToken.generate()
        let redacted = WebSocketAuthToken.redact(token)
        XCTAssertFalse(redacted.contains(String(token.dropFirst(4))))
        XCTAssertLessThanOrEqual(redacted.count, 5)
    }

    // MARK: - Generation (Keychain-free)
    //
    // `generate()` is exercised directly; `currentOrCreate()` / `rotate()`
    // round-trip through KeychainService, which prompts under the ad-hoc-signed
    // test host, so they are deliberately not covered here.

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
}
