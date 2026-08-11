//
//  WebSocketServerAuthTests.swift
//  WolfWave
//
//  Created by Nathanial Henniges on 2026-05-23.
//  Copyright © 2026 MrDemonWolf, Inc. All rights reserved.
//

import Security
import XCTest
@testable import WolfWave

/// Pins the pure authentication and authorization contract used by the
/// Network.framework handshake and connection-state gates.
final class WebSocketServerAuthTests: XCTestCase {
    private let overlayToken = "abcdef1234567890"
    private let controlToken = "0123456789abcdef"

    // MARK: - Role-specific subprotocols

    func testExpectedSubprotocolsCarryDistinctRolePrefixes() {
        XCTAssertEqual(
            WebSocketAuthToken.expectedSubprotocol(for: overlayToken, role: .overlay),
            "wolfwave.overlay.abcdef1234567890"
        )
        XCTAssertEqual(
            WebSocketAuthToken.expectedSubprotocol(for: controlToken, role: .control),
            "wolfwave.control.0123456789abcdef"
        )
    }

    func testLegacyInitializerResolvesReadOnlyOverlayRole() {
        XCTAssertEqual(
            WebSocketAuthToken.authenticationRole(
                overlayToken: nil,
                controlToken: nil,
                offeredSubprotocols: []
            ),
            .overlay
        )
    }

    func testMissingAndMismatchedSubprotocolsAreRejected() {
        XCTAssertNil(
            WebSocketAuthToken.authenticationRole(
                overlayToken: overlayToken,
                controlToken: controlToken,
                offeredSubprotocols: []
            )
        )
        XCTAssertNil(
            WebSocketAuthToken.authenticationRole(
                overlayToken: overlayToken,
                controlToken: controlToken,
                offeredSubprotocols: ["graphql-ws", "wolfwave.overlay.deadbeef"]
            )
        )
        XCTAssertNil(
            WebSocketAuthToken.authenticationRole(
                overlayToken: overlayToken,
                controlToken: controlToken,
                offeredSubprotocols: [overlayToken]
            ),
            "A raw token without a role prefix must not authenticate"
        )
    }

    func testOverlayCredentialResolvesOnlyOverlayRole() {
        XCTAssertEqual(
            WebSocketAuthToken.authenticationRole(
                overlayToken: overlayToken,
                controlToken: controlToken,
                offeredSubprotocols: ["wolfwave.overlay." + overlayToken]
            ),
            .overlay
        )
        XCTAssertNil(
            WebSocketAuthToken.authenticationRole(
                overlayToken: overlayToken,
                controlToken: controlToken,
                offeredSubprotocols: ["wolfwave.control." + overlayToken]
            ),
            "Changing the prefix must not promote an overlay credential"
        )
    }

    func testIdenticalCredentialsFailClosedForControlRole() {
        XCTAssertNil(
            WebSocketAuthToken.authenticationRole(
                overlayToken: overlayToken,
                controlToken: overlayToken,
                offeredSubprotocols: ["wolfwave.control." + overlayToken]
            )
        )
        XCTAssertEqual(
            WebSocketAuthToken.authenticationRole(
                overlayToken: overlayToken,
                controlToken: overlayToken,
                offeredSubprotocols: ["wolfwave.overlay." + overlayToken]
            ),
            .overlay
        )
    }

    func testControlCredentialResolvesControlRole() {
        XCTAssertEqual(
            WebSocketAuthToken.authenticationRole(
                overlayToken: overlayToken,
                controlToken: controlToken,
                offeredSubprotocols: ["wolfwave.control." + controlToken]
            ),
            .control
        )
    }

    func testControlWinsWhenBothValidRolesAreOffered() {
        XCTAssertEqual(
            WebSocketAuthToken.authenticationRole(
                overlayToken: overlayToken,
                controlToken: controlToken,
                offeredSubprotocols: [
                    "wolfwave.overlay." + overlayToken,
                    "wolfwave.control." + controlToken,
                ]
            ),
            .control
        )
    }

    func testRoleMatchingIsCaseSensitive() {
        XCTAssertNil(
            WebSocketAuthToken.authenticationRole(
                overlayToken: overlayToken,
                controlToken: controlToken,
                offeredSubprotocols: ["wolfwave.overlay.ABCDEF1234567890"]
            )
        )
    }

    func testSelectedSubprotocolIsRevalidated() {
        XCTAssertEqual(
            WebSocketAuthToken.role(
                forSelectedSubprotocol: "wolfwave.overlay." + overlayToken,
                overlayToken: overlayToken,
                controlToken: controlToken
            ),
            .overlay
        )
        XCTAssertNil(
            WebSocketAuthToken.role(
                forSelectedSubprotocol: "wolfwave.control." + overlayToken,
                overlayToken: overlayToken,
                controlToken: controlToken
            )
        )
    }

    // MARK: - Connection and command authorization

    func testOverlayConnectionsCanReceiveStateFromLoopbackOrLAN() {
        XCTAssertTrue(WebSocketServerService.allowsConnection(role: .overlay, isLoopback: true))
        XCTAssertTrue(WebSocketServerService.allowsConnection(role: .overlay, isLoopback: false))
    }

    func testControlConnectionsAreLoopbackOnly() {
        XCTAssertTrue(WebSocketServerService.allowsConnection(role: .control, isLoopback: true))
        XCTAssertFalse(WebSocketServerService.allowsConnection(role: .control, isLoopback: false))
    }

    func testCommandsRequireLoopbackControlRole() {
        XCTAssertTrue(WebSocketServerService.allowsCommands(role: .control, isLoopback: true))
        XCTAssertFalse(WebSocketServerService.allowsCommands(role: .control, isLoopback: false))
        XCTAssertFalse(WebSocketServerService.allowsCommands(role: .overlay, isLoopback: true))
        XCTAssertFalse(WebSocketServerService.allowsCommands(role: .overlay, isLoopback: false))
    }

    // MARK: - Constant-time comparison and validation

    func testConstantTimeEquals() {
        XCTAssertTrue(WebSocketAuthToken.constantTimeEquals(overlayToken, overlayToken))
        XCTAssertTrue(WebSocketAuthToken.constantTimeEquals("", ""))
        XCTAssertFalse(WebSocketAuthToken.constantTimeEquals(overlayToken, controlToken))
        XCTAssertFalse(WebSocketAuthToken.constantTimeEquals("abcdef", overlayToken))
        XCTAssertFalse(WebSocketAuthToken.constantTimeEquals(overlayToken, "abcdef"))
    }

    func testTokenValidation() {
        XCTAssertTrue(WebSocketAuthToken.isValid(overlayToken))
        XCTAssertFalse(WebSocketAuthToken.isValid("ABCDEF1234567890"))
        XCTAssertTrue(WebSocketAuthToken.isValid(String(repeating: "a", count: 64)))
        XCTAssertFalse(WebSocketAuthToken.isValid(""))
        XCTAssertFalse(WebSocketAuthToken.isValid(String(repeating: "a", count: 63)))
        XCTAssertFalse(WebSocketAuthToken.isValid(String(repeating: "a", count: 65)))
        XCTAssertFalse(WebSocketAuthToken.isValid("</script><script>alert(1)</script>"))
        XCTAssertFalse(WebSocketAuthToken.isValid("0123456789abcdef-"))
    }

    func testGenerationAndRedaction() {
        let first = WebSocketAuthToken.generate()
        let second = WebSocketAuthToken.generate()
        XCTAssertEqual(first.count, 64)
        XCTAssertTrue(WebSocketAuthToken.isValid(first))
        XCTAssertNotEqual(first, second)
        XCTAssertEqual(WebSocketAuthToken.redact(overlayToken), "abcd…")
        XCTAssertEqual(WebSocketAuthToken.redact("ab"), "…")
        XCTAssertFalse(WebSocketAuthToken.redact(first).contains(String(first.dropFirst(4))))
    }

    // MARK: - Role-isolated persistence

    private func withInMemoryKeychain(_ body: () throws -> Void) rethrows {
        KeychainBackendTestIsolation.acquire()
        let previous = KeychainService.backend
        KeychainService.backend = InMemoryKeychainBackend()
        defer {
            KeychainService.backend = previous
            KeychainBackendTestIsolation.release()
        }
        try body()
    }

    func testCurrentOrCreateMintsSeparatePersistedCredentials() {
        withInMemoryKeychain {
            let overlay = WebSocketAuthToken.currentOrCreate(for: .overlay)
            let control = WebSocketAuthToken.currentOrCreate(for: .control)

            XCTAssertNotEqual(overlay, control)
            XCTAssertEqual(KeychainService.loadToken(), overlay)
            XCTAssertEqual(KeychainService.loadControlToken(), control)
        }
    }

    func testCurrentOrCreateReplacesInvalidStoredCredential() throws {
        try withInMemoryKeychain {
            try KeychainService.saveControlToken("ABCDEF1234567890")

            let replacement = WebSocketAuthToken.currentOrCreate(for: .control)

            XCTAssertEqual(replacement.count, 64)
            XCTAssertTrue(WebSocketAuthToken.isValid(replacement))
            XCTAssertNotEqual(replacement, "ABCDEF1234567890")
            XCTAssertEqual(KeychainService.loadControlToken(), replacement)
        }
    }

    func testCurrentOrCreateReusesEachPreexistingCredential() throws {
        try withInMemoryKeychain {
            try KeychainService.saveToken(overlayToken)
            try KeychainService.saveControlToken(controlToken)

            XCTAssertEqual(WebSocketAuthToken.currentOrCreate(for: .overlay), overlayToken)
            XCTAssertEqual(WebSocketAuthToken.currentOrCreate(for: .control), controlToken)
        }
    }

    func testPersistChangesOnlyRequestedRole() throws {
        try withInMemoryKeychain {
            try KeychainService.saveToken(overlayToken)
            try KeychainService.saveControlToken(controlToken)
            let replacement = String(repeating: "f", count: 64)

            try WebSocketAuthToken.persist(replacement, for: .control)

            XCTAssertEqual(KeychainService.loadToken(), overlayToken)
            XCTAssertEqual(KeychainService.loadControlToken(), replacement)
        }
    }

    func testRotateChangesOnlyRequestedRole() throws {
        try withInMemoryKeychain {
            let overlay = WebSocketAuthToken.currentOrCreate(for: .overlay)
            let control = WebSocketAuthToken.currentOrCreate(for: .control)

            let rotated = try WebSocketAuthToken.rotate(.control)

            XCTAssertNotEqual(rotated, control)
            XCTAssertEqual(KeychainService.loadToken(), overlay)
            XCTAssertEqual(KeychainService.loadControlToken(), rotated)
            XCTAssertEqual(WebSocketAuthToken.currentOrCreate(for: .control), rotated)
        }
    }

    func testSessionFallbackStaysRoleScopedAndPersistsAfterRecovery() {
        KeychainBackendTestIsolation.acquire()
        let previous = KeychainService.backend
        KeychainService.backend = FailingKeychainBackend()
        defer {
            KeychainService.backend = previous
            KeychainBackendTestIsolation.release()
        }

        let first = WebSocketAuthToken.currentOrCreate(for: .overlay)
        let second = WebSocketAuthToken.currentOrCreate(for: .overlay)
        XCTAssertEqual(first, second)

        let recovered = InMemoryKeychainBackend()
        KeychainService.backend = recovered
        try? KeychainService.saveToken(String(repeating: "a", count: 64))

        XCTAssertEqual(WebSocketAuthToken.currentOrCreate(for: .overlay), first)
        XCTAssertEqual(KeychainService.loadToken(), first)
        XCTAssertNil(KeychainService.loadControlToken())
    }

    func testRotateDoesNotPublishUnpersistedCredential() {
        KeychainBackendTestIsolation.acquire()
        let previous = KeychainService.backend
        KeychainService.backend = FailingKeychainBackend()
        defer {
            KeychainService.backend = previous
            KeychainBackendTestIsolation.release()
        }

        XCTAssertThrowsError(try WebSocketAuthToken.rotate(.control))
        XCTAssertNil(KeychainService.loadControlToken())
    }
}

private final class FailingKeychainBackend: KeychainBackend, @unchecked Sendable {
    func save(account _: String, value _: String) throws {
        throw KeychainService.KeychainError.saveFailed(errSecInteractionNotAllowed)
    }

    func load(account _: String) -> String? { nil }
    func delete(account _: String) {}
    func deleteAll() {}
}
