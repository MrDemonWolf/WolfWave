//
//  WebSocketAuthToken.swift
//  WolfWave
//
//  Created by Nathanial Henniges on 2026-05-23.
//  Copyright © 2026 MrDemonWolf, Inc. All rights reserved.
//

import Foundation

/// Manages the per-install authentication token used to gate WebSocket
/// overlay connections.
///
/// The token is minted on first launch (64 hex chars / 32 random bytes),
/// stored in the macOS Keychain via `KeychainService.saveToken(_:)`, and
/// presented by clients on the WebSocket handshake as the
/// `wolfwave.token.<hex>` subprotocol. Only the first 4 characters are ever
/// logged so the full credential never ends up in a diagnostics export.
nonisolated enum WebSocketAuthToken {

    /// Subprotocol prefix advertised by the widget on `new WebSocket(url, [...])`
    /// and checked server-side.
    static let subprotocolPrefix = "wolfwave.token."

    /// Returns the stored token, minting and persisting one on first call.
    @discardableResult
    static func currentOrCreate() -> String {
        if let existing = KeychainService.loadToken(), !existing.isEmpty {
            return existing
        }
        let fresh = generate()
        do {
            try KeychainService.saveToken(fresh)
        } catch {
            Log.error("WebSocketAuthToken: Failed to persist new token: \(error)", category: "WebSocket")
        }
        return fresh
    }

    /// Mints a fresh token, replaces the stored one, and returns it.
    /// Active connections continue using the previous token until they
    /// disconnect. Caller is responsible for restarting the server when
    /// it wants to invalidate every client.
    @discardableResult
    static func rotate() -> String {
        let fresh = generate()
        do {
            try KeychainService.saveToken(fresh)
        } catch {
            Log.error("WebSocketAuthToken: Failed to rotate token: \(error)", category: "WebSocket")
        }
        return fresh
    }

    /// Returns the subprotocol string a client must offer to be accepted.
    static func expectedSubprotocol(for token: String) -> String {
        subprotocolPrefix + token
    }

    /// Decides whether a handshake should be accepted given the server's
    /// configured token and the subprotocols the client offered.
    ///
    /// - When `expectedToken` is `nil` (test-only legacy init), any handshake
    ///   passes. Preserves backward-compat for the lifecycle tests that
    ///   construct the service via `init(port:)`.
    /// - Otherwise the client must have offered `wolfwave.token.<expected>`
    ///   in its `Sec-WebSocket-Protocol` list.
    static func shouldAccept(expectedToken: String?, offeredSubprotocols: [String]) -> Bool {
        guard let expected = expectedToken else { return true }
        return offeredSubprotocols.contains(expectedSubprotocol(for: expected))
    }

    /// Returns `true` when `candidate` is a non-empty hex string (`[0-9a-fA-F]+`)
    /// between 16 and 128 characters. Custom tokens entered by the user are
    /// gated through this check before they are persisted or substituted into
    /// the served `widget.html`, so a token can never contain `</script>` or
    /// other characters that would break out of the JS string context.
    static func isValid(_ candidate: String) -> Bool {
        guard (16...128).contains(candidate.count) else { return false }
        return candidate.unicodeScalars.allSatisfy { scalar in
            (scalar >= "0" && scalar <= "9")
                || (scalar >= "a" && scalar <= "f")
                || (scalar >= "A" && scalar <= "F")
        }
    }

    /// Redacts a token for safe logging. Keeps the first 4 chars and an ellipsis.
    static func redact(_ token: String) -> String {
        guard token.count > 4 else { return "…" }
        return token.prefix(4) + "…"
    }

    // MARK: - Generation

    /// Mints a fresh 64-hex-char (32 random byte) token. Exposed at module scope
    /// so unit tests can verify token shape and uniqueness without round-tripping
    /// through the Keychain (which prompts for access under ad-hoc test signing).
    static func generate() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        if status != errSecSuccess {
            var rng = SystemRandomNumberGenerator()
            for i in 0..<bytes.count {
                bytes[i] = UInt8.random(in: 0...255, using: &rng)
            }
        }
        return bytes.map { String(format: "%02x", $0) }.joined()
    }
}
