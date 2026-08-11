//
//  WebSocketAuthToken.swift
//  WolfWave
//
//  Created by Nathanial Henniges on 2026-05-23.
//  Copyright © 2026 MrDemonWolf, Inc. All rights reserved.
//

import Foundation
import Network
import os

/// Manages the two per-install credentials used by WolfWave's WebSocket server.
///
/// Overlay clients receive playback state but cannot execute commands. Control
/// clients may execute commands, but the server accepts that role only from a
/// loopback peer. Both credentials are 64 hex chars, live in the macOS Keychain,
/// and travel in role-specific WebSocket subprotocols so a read-only OBS URL can
/// never be promoted into a command channel.
nonisolated enum WebSocketAuthToken {
    enum Role: String, CaseIterable, Sendable, Hashable {
        case overlay
        case control

        var subprotocolPrefix: String {
            switch self {
            case .overlay:
                return "wolfwave.overlay."
            case .control:
                return "wolfwave.control."
            }
        }
    }

    /// Stable in-process fallbacks for the rare case where Keychain persistence
    /// is temporarily unavailable. Keeping each role separate prevents a failed
    /// control-token write from changing the overlay credential (and vice versa).
    private static let sessionTokens = OSAllocatedUnfairLock<[Role: String]>(initialState: [:])

    /// Serializes credential lifecycle operations without holding the short-lived
    /// session-state lock across Keychain I/O.
    private static let operationGate = DispatchSemaphore(value: 1)

    /// Returns the stored credential for `role`, minting and persisting it on
    /// first call. A temporary session credential is retried before a stale
    /// Keychain value is considered.
    @discardableResult
    static func currentOrCreate(for role: Role) -> String {
        operationGate.wait()
        defer { operationGate.signal() }

        if let sessionValue = sessionTokens.withLock({ $0[role] }) {
            do {
                try save(sessionValue, for: role)
                sessionTokens.withLock { $0[role] = nil }
            } catch {
                Log.error(
                    "WebSocketAuthToken: Failed to persist session \(role.rawValue) token: \(error)",
                    category: "WebSocket"
                )
                return sessionValue
            }
            return sessionValue
        }

        if let existing = load(for: role), !existing.isEmpty {
            return existing
        }

        let fresh = generate()
        do {
            try save(fresh, for: role)
            sessionTokens.withLock { $0[role] = nil }
        } catch {
            Log.error(
                "WebSocketAuthToken: Failed to persist new \(role.rawValue) token: \(error)",
                category: "WebSocket"
            )
            sessionTokens.withLock { $0[role] = fresh }
        }
        return fresh
    }

    /// Persists an explicitly supplied credential for `role` and clears any
    /// temporary fallback for that role.
    static func persist(_ token: String, for role: Role) throws {
        operationGate.wait()
        defer { operationGate.signal() }

        try save(token, for: role)
        sessionTokens.withLock { $0[role] = nil }
    }

    /// Mints, persists, and returns a fresh credential for `role`. The in-memory
    /// value changes only after persistence succeeds.
    @discardableResult
    static func rotate(_ role: Role) throws -> String {
        operationGate.wait()
        defer { operationGate.signal() }

        let fresh = generate()
        try save(fresh, for: role)
        sessionTokens.withLock { $0[role] = nil }
        return fresh
    }

    /// Returns the exact subprotocol string a client in `role` must offer.
    static func expectedSubprotocol(for token: String, role: Role) -> String {
        role.subprotocolPrefix + token
    }

    /// Resolves the authenticated role from the offered subprotocols.
    ///
    /// When both configured credentials are `nil` (the test-only legacy
    /// initializer), the connection is treated as a read-only overlay. In
    /// production an exact role-prefixed credential is required. Control wins
    /// only when its own credential was offered; an overlay token can never be
    /// promoted by changing the prefix.
    static func authenticationRole(
        overlayToken: String?,
        controlToken: String?,
        offeredSubprotocols: [String]
    ) -> Role? {
        guard overlayToken != nil || controlToken != nil else { return .overlay }

        var matchedOverlay = false
        var matchedControl = false
        let controlCredentialIsDistinct: Bool
        if let overlayToken, let controlToken {
            controlCredentialIsDistinct = !constantTimeEquals(overlayToken, controlToken)
        } else {
            controlCredentialIsDistinct = true
        }
        for offered in offeredSubprotocols {
            if let overlayToken,
               constantTimeEquals(offered, expectedSubprotocol(for: overlayToken, role: .overlay)) {
                matchedOverlay = true
            }
            if controlCredentialIsDistinct, let controlToken,
               constantTimeEquals(offered, expectedSubprotocol(for: controlToken, role: .control)) {
                matchedControl = true
            }
        }
        if matchedControl { return .control }
        if matchedOverlay { return .overlay }
        return nil
    }

    /// Validates the protocol Network.framework selected during the handshake
    /// and maps it back to its role.
    static func role(
        forSelectedSubprotocol selectedSubprotocol: String?,
        overlayToken: String?,
        controlToken: String?
    ) -> Role? {
        guard overlayToken != nil || controlToken != nil else { return .overlay }
        guard let selectedSubprotocol else { return nil }
        return authenticationRole(
            overlayToken: overlayToken,
            controlToken: controlToken,
            offeredSubprotocols: [selectedSubprotocol]
        )
    }

    /// Returns whether a Network.framework endpoint is a literal loopback IP.
    /// Unresolved hostnames are rejected; callers must not trust a name that can
    /// be changed by DNS.
    static func isLoopbackEndpoint(_ endpoint: NWEndpoint) -> Bool {
        switch endpoint {
        case .hostPort(let host, _):
            switch host {
            case .ipv4(let address):
                return address.isLoopback
            case .ipv6(let address):
                return address.isLoopback
            case .name:
                return false
            @unknown default:
                return false
            }
        default:
            return false
        }
    }

    /// Compares two strings for equality without leaking matching prefix length.
    static func constantTimeEquals(_ lhs: String, _ rhs: String) -> Bool {
        let a = Array(lhs.utf8)
        let b = Array(rhs.utf8)
        let count = max(a.count, b.count)
        var diff: UInt8 = a.count == b.count ? 0 : 1
        var index = 0
        while index < count {
            let lhsByte: UInt8 = index < a.count ? a[index] : 0
            let rhsByte: UInt8 = index < b.count ? b[index] : 0
            diff |= lhsByte ^ rhsByte
            index += 1
        }
        return diff == 0
    }

    /// Returns `true` for a bounded, non-empty hexadecimal credential.
    static func isValid(_ candidate: String) -> Bool {
        guard (16...128).contains(candidate.count) else { return false }
        return candidate.unicodeScalars.allSatisfy { scalar in
            (scalar >= "0" && scalar <= "9")
                || (scalar >= "a" && scalar <= "f")
                || (scalar >= "A" && scalar <= "F")
        }
    }

    /// Redacts a credential for safe logging.
    static func redact(_ token: String) -> String {
        guard token.count > 4 else { return "…" }
        return token.prefix(4) + "…"
    }

    /// Mints a fresh 64-hex-char (32 random byte) credential.
    static func generate() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        if status != errSecSuccess {
            var rng = SystemRandomNumberGenerator()
            for index in bytes.indices {
                bytes[index] = UInt8.random(in: 0...255, using: &rng)
            }
        }
        return bytes.map { String(format: "%02x", $0) }.joined()
    }

    private static func load(for role: Role) -> String? {
        switch role {
        case .overlay:
            return KeychainService.loadToken()
        case .control:
            return KeychainService.loadControlToken()
        }
    }

    private static func save(_ token: String, for role: Role) throws {
        switch role {
        case .overlay:
            try KeychainService.saveToken(token)
        case .control:
            try KeychainService.saveControlToken(token)
        }
    }
}
