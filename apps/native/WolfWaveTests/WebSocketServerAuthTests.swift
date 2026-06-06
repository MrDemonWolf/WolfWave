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

    // MARK: - shouldAccept, auth disabled (legacy init)

    func testShouldAcceptIsTrueWhenTokenIsNil() {
        XCTAssertTrue(
            WebSocketAuthToken.shouldAccept(expectedToken: nil, offeredSubprotocols: []),
            "Legacy `init(port:)` (no token) must keep accepting unauthenticated clients"
        )
        XCTAssertTrue(
            WebSocketAuthToken.shouldAccept(expectedToken: nil, offeredSubprotocols: ["whatever"])
        )
    }

    // MARK: - shouldAccept, token configured

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
        // Hex tokens are produced lowercase. A case-mangled offer must not pass,
        // otherwise an attacker that knew the entropy could attempt mixed-case bypass.
        XCTAssertFalse(
            WebSocketAuthToken.shouldAccept(
                expectedToken: "abcdef1234567890",
                offeredSubprotocols: ["wolfwave.token.ABCDEF1234567890"]
            )
        )
    }

    // MARK: - Constant-time comparison

    func testConstantTimeEqualsMatch() {
        XCTAssertTrue(
            WebSocketAuthToken.constantTimeEquals("abcdef1234567890", "abcdef1234567890")
        )
        XCTAssertTrue(WebSocketAuthToken.constantTimeEquals("", ""))
    }

    func testConstantTimeEqualsNonMatchSameLength() {
        XCTAssertFalse(
            WebSocketAuthToken.constantTimeEquals("abcdef1234567890", "abcdef1234567891")
        )
        // Differ only in the first byte (the early-exit risk for naive compares).
        XCTAssertFalse(
            WebSocketAuthToken.constantTimeEquals("Xbcdef1234567890", "abcdef1234567890")
        )
    }

    func testConstantTimeEqualsLengthMismatch() {
        XCTAssertFalse(WebSocketAuthToken.constantTimeEquals("abcdef", "abcdef1234567890"))
        XCTAssertFalse(WebSocketAuthToken.constantTimeEquals("abcdef1234567890", "abcdef"))
        // A prefix must not pass.
        XCTAssertFalse(WebSocketAuthToken.constantTimeEquals("abc", "abcdef"))
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
    // `generate()` is exercised directly. `currentOrCreate()` / `rotate()` are
    // covered below through an in-memory backend so the tests NEVER touch the
    // real Keychain (which prompts under the ad-hoc-signed test host).

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

    // MARK: - currentOrCreate / rotate (in-memory backend, Keychain-free)
    //
    // `WebSocketAuthToken` persists through `KeychainService`, which carries its
    // own injectable `KeychainBackend` seam. Each of these tests swaps in a fresh
    // `InMemoryKeychainBackend` and restores the previous one so they NEVER touch
    // the real Keychain (which prompts under ad-hoc test signing).

    /// Runs `body` with an empty in-memory Keychain backend installed, restoring
    /// the previously active backend afterward.
    private func withInMemoryKeychain(_ body: () throws -> Void) rethrows {
        let previous = KeychainService.backend
        KeychainService.backend = InMemoryKeychainBackend()
        defer { KeychainService.backend = previous }
        try body()
    }

    func testCurrentOrCreateMintsAndPersistsWhenEmpty() {
        withInMemoryKeychain {
            XCTAssertNil(KeychainService.loadToken())

            let minted = WebSocketAuthToken.currentOrCreate()

            XCTAssertTrue(WebSocketAuthToken.isValid(minted), "minted token must be valid hex")
            XCTAssertEqual(KeychainService.loadToken(), minted, "minted token must be persisted")
        }
    }

    func testCurrentOrCreateIsStableAcrossCalls() {
        withInMemoryKeychain {
            let first = WebSocketAuthToken.currentOrCreate()
            let second = WebSocketAuthToken.currentOrCreate()

            XCTAssertEqual(first, second, "currentOrCreate must return the persisted token on later calls")
        }
    }

    func testCurrentOrCreateReusesPreexistingToken() throws {
        try withInMemoryKeychain {
            let existing = WebSocketAuthToken.generate()
            try KeychainService.saveToken(existing)

            let returned = WebSocketAuthToken.currentOrCreate()

            XCTAssertEqual(returned, existing, "an already-stored token must be returned verbatim")
        }
    }

    func testRotateReplacesAndPersistsToken() {
        withInMemoryKeychain {
            let original = WebSocketAuthToken.currentOrCreate()

            let rotated = WebSocketAuthToken.rotate()

            XCTAssertNotEqual(rotated, original, "rotate must mint a new token")
            XCTAssertTrue(WebSocketAuthToken.isValid(rotated))
            XCTAssertEqual(KeychainService.loadToken(), rotated, "rotate must persist the new token")
            XCTAssertEqual(
                WebSocketAuthToken.currentOrCreate(),
                rotated,
                "a subsequent currentOrCreate must return the rotated token"
            )
        }
    }
}
