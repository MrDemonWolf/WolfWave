//
//  KeychainService.swift
//  WolfWave
//
//  Created by Nathanial Henniges on 2026-01-08.
//  Copyright © 2026 MrDemonWolf, Inc. All rights reserved.
//

import Foundation

/// Secure credential storage using the macOS Keychain.
///
/// Provides a type-safe interface for storing and retrieving sensitive credentials.
/// All items use `kSecAttrAccessibleAfterFirstUnlock` accessibility for persistence after unlock.
///
/// Stored Credentials:
/// - **Overlay Auth Token**: Read-only WebSocket credential used by OBS widgets
/// - **Control Auth Token**: Same-Mac WebSocket credential used by Stream Deck
/// - **Twitch OAuth Token**: User's OAuth token for Twitch API and chat
/// - **Twitch Username**: Bot account username for display and identification
/// - **Twitch User ID**: Bot account user ID for EventSub subscriptions
/// - **Twitch Channel ID**: Target channel for bot commands
///
/// Error Handling:
/// - All save operations throw `KeychainError` on failure
/// - Load operations return nil if not found; checked grant reads preserve failures
/// - Delete operations throw on failure and succeed silently if absent
///
/// Thread Safety:
/// - Keychain operations are thread-safe (backed by Security framework)
/// - Safe to call from any thread
///
/// Usage Example:
/// ```swift
/// try KeychainService.saveTwitchCredentialGrant(
///     .init(accessToken: "oauth_token_here", channelID: "channel")
/// )
/// if let token = KeychainService.loadTwitchToken() {
///     // Use token for Twitch API calls
/// }
/// ```
nonisolated enum KeychainService {
    /// One crash-atomic Twitch account record. Keeping access, refresh, resolved
    /// identity, and the configured channel in one Keychain item prevents
    /// force-quit windows from cross-pairing different account configurations.
    nonisolated struct TwitchCredentialGrant: Codable, Equatable, Sendable {
        var accessToken: String?
        var refreshToken: String?
        var username: String?
        var userID: String?
        var channelID: String?

        static let empty = TwitchCredentialGrant()

        var isEmpty: Bool {
            accessToken == nil
                && refreshToken == nil
                && username == nil
                && userID == nil
                && channelID == nil
        }

        init(
            accessToken: String? = nil,
            refreshToken: String? = nil,
            username: String? = nil,
            userID: String? = nil,
            channelID: String? = nil
        ) {
            self.accessToken = accessToken
            self.refreshToken = refreshToken
            self.username = username
            self.userID = userID
            self.channelID = channelID
        }
    }

    // MARK: - Constants

    /// Service identifier for Keychain items.
    ///
    /// Scoped to the running bundle identifier so DEBUG (`…wolfwave.dev`) and
    /// release (`com.mrdemonwolf.wolfwave`) builds keep separate items. Without
    /// this, every rebuild whose code signature differs from the binary that
    /// originally wrote the item triggers a "WolfWave wants to use your
    /// confidential information stored in … keychain" ACL prompt.
    ///
    /// Release bundle ID is preserved verbatim to keep existing users' tokens
    /// readable after upgrade.
    private static let service: String = {
        let releaseBundleID = "com.mrdemonwolf.wolfwave"
        guard let bundleID = Bundle.main.bundleIdentifier, !bundleID.isEmpty else {
            return releaseBundleID
        }
        return bundleID
    }()

    /// Account identifier for the read-only overlay token. The legacy account
    /// name is intentionally preserved so existing OBS URLs survive upgrade.
    private static let websocketAuthToken = "websocketAuthToken"

    /// Account identifier for the privileged, loopback-only control token.
    private static let websocketControlToken = "websocketControlToken"

    /// Account identifier for Twitch OAuth token.
    private static let twitchBotAccountOauthToken = "twitchBotAccountOauthToken"

    /// Account identifier for the Twitch OAuth refresh token.
    private static let twitchBotAccountRefreshToken = AppConstants.Keychain.twitchBotAccountRefreshToken

    /// Account identifier for Twitch bot username.
    private static let twitchBotAccountUsername = "twitchBotAccountUsername"

    /// Account identifier for Twitch bot user ID.
    private static let twitchBotAccountUserID = "twitchBotAccountUserID"

    /// Versioned crash-atomic replacement for the legacy Twitch items. Version 2
    /// adds the configured channel so manual token/channel saves are one write.
    /// Internal so migration/failure tests can identify the one atomic write.
    static let twitchCredentialGrantAccount = "twitchBotCredentialGrant.v2"

    /// Version 1 held access, refresh, username, and user ID while channel was a
    /// separate item. It remains readable only as a copy-before-delete source.
    static let legacyTwitchCredentialGrantAccount = "twitchBotCredentialGrant.v1"

    /// Serializes read-modify-write access and one-time legacy migration.
    private static let twitchCredentialLock = NSLock()

    /// Precedence-preserving result of reading the pre-v2 Twitch accounts.
    private enum LegacyTwitchCredentialSource {
        case absent
        case valid(TwitchCredentialGrant)
        case malformed
    }

    /// Account identifier for Twitch channel ID.
    private static let twitchChannelIDAccount = "twitchChannelIDAccount"

    // MARK: - Error Types

    /// Errors that can occur during Keychain operations.
    enum KeychainError: LocalizedError {
        /// Failed to save data to Keychain with given Security framework status code.
        case saveFailed(OSStatus)

        /// Failed to load data from Keychain with the Security framework status.
        case loadFailed(OSStatus)

        /// Failed to delete data from Keychain with the Security framework status.
        case deleteFailed(OSStatus)

        /// Invalid or corrupted data read from Keychain.
        case invalidData

        var errorDescription: String? {
            switch self {
            case .saveFailed(let status):
                return "Failed to save token to Keychain (status: \(status))"
            case .loadFailed(let status):
                return "Failed to load token from Keychain (status: \(status))"
            case .deleteFailed(let status):
                return "Failed to delete token from Keychain (status: \(status))"
            case .invalidData:
                return "Invalid token data"
            }
        }
    }

    // MARK: - Public Methods - WebSocket Tokens

    /// Saves the read-only overlay authentication token to Keychain.
    ///
    /// Uses update-or-add pattern for efficiency (single Keychain roundtrip when updating).
    ///
    /// - Parameter token: The authentication token to save.
    /// - Throws: `KeychainError.saveFailed(status)` if Keychain operation fails.
    static func saveToken(_ token: String) throws {
        try upsertItem(account: websocketAuthToken, value: token)
    }

    /// Loads the read-only overlay authentication token from Keychain.
    ///
    /// - Returns: The stored token string, or nil if not found or on error.
    static func loadToken() -> String? {
        loadItem(account: websocketAuthToken)
    }

    /// Status-bearing read for credential lifecycle code that must distinguish
    /// confirmed absence from a temporarily unavailable Keychain.
    static func loadTokenChecked() throws -> String? {
        try backend.load(account: websocketAuthToken)
    }

    /// Deletes the read-only overlay authentication token from Keychain.
    ///
    /// Succeeds silently if token doesn't exist.
    static func deleteToken() throws {
        try deleteItem(account: websocketAuthToken)
    }

    /// Saves the privileged, loopback-only control token to Keychain.
    static func saveControlToken(_ token: String) throws {
        try upsertItem(account: websocketControlToken, value: token)
    }

    /// Loads the privileged, loopback-only control token from Keychain.
    static func loadControlToken() -> String? {
        loadItem(account: websocketControlToken)
    }

    /// Status-bearing counterpart to ``loadControlToken()``.
    static func loadControlTokenChecked() throws -> String? {
        try backend.load(account: websocketControlToken)
    }

    /// Deletes the privileged, loopback-only control token from Keychain.
    static func deleteControlToken() throws {
        try deleteItem(account: websocketControlToken)
    }

    // MARK: - Public Methods - Twitch Credential Reads

    static func loadTwitchToken() -> String? {
        loadTwitchCredentialGrant().accessToken
    }

    static func loadTwitchRefreshToken() -> String? {
        loadTwitchCredentialGrant().refreshToken
    }

    static func loadTwitchUsername() -> String? {
        loadTwitchCredentialGrant().username
    }

    static func loadTwitchBotUserID() -> String? {
        loadTwitchCredentialGrant().userID
    }

    // MARK: - Atomic Twitch Grant

    /// Loads one internally consistent Twitch account snapshot. Read failures
    /// fail closed and never fall through to legacy migration.
    static func loadTwitchCredentialGrant() -> TwitchCredentialGrant {
        do {
            return try loadTwitchCredentialGrantChecked()
        } catch {
            Log.error(
                "KeychainService: Failed to load Twitch credential grant - \(error.localizedDescription)",
                category: "Keychain")
            return .empty
        }
    }

    /// Checked variant used by account transactions that must distinguish a
    /// missing grant from an unavailable Keychain.
    static func loadTwitchCredentialGrantChecked() throws -> TwitchCredentialGrant {
        try twitchCredentialLock.withLock {
            try loadTwitchCredentialGrantLocked()
        }
    }

    /// Replaces the complete Twitch account in one atomic backend write.
    static func saveTwitchCredentialGrant(_ grant: TwitchCredentialGrant) throws {
        try validateTwitchCredentialGrant(grant)
        try twitchCredentialLock.withLock {
            try saveTwitchCredentialGrantLocked(grant)
            if !grant.isEmpty {
                deleteLegacyTwitchCredentialsBestEffortLocked()
            }
        }
    }

    /// Clears legacy Twitch fields first and the canonical grant last. The
    /// canonical grant therefore remains authoritative after any failed delete.
    static func deleteTwitchCredentialGrant() throws {
        try twitchCredentialLock.withLock {
            try deleteTwitchCredentialGrantLocked()
        }
    }

    /// Atomically reads, conditionally mutates, validates, and saves the complete
    /// Twitch record while holding one Keychain lock. Credential-store CAS paths
    /// use this so a concurrent channel edit can never be overwritten by a stale
    /// snapshot captured before the edit.
    @discardableResult
    static func mutateTwitchCredentialGrant(
        _ mutation: (inout TwitchCredentialGrant) throws -> Bool
    ) throws -> Bool {
        try twitchCredentialLock.withLock {
            var grant = try loadTwitchCredentialGrantLocked()
            guard try mutation(&grant) else { return false }
            try validateTwitchCredentialGrant(grant)
            try saveTwitchCredentialGrantLocked(grant)
            if !grant.isEmpty {
                deleteLegacyTwitchCredentialsBestEffortLocked()
            }
            return true
        }
    }

    private static func loadTwitchCredentialGrantLocked() throws -> TwitchCredentialGrant {
        // A backend error is not "not found": return it without inspecting or
        // mutating legacy fields, which might belong to an older account.
        if let encoded = try backend.load(account: twitchCredentialGrantAccount) {
            return decodeCurrentTwitchCredentialGrantOrFailClosed(encoded)
        }

        switch try loadLegacyTwitchCredentialSourceLocked() {
        case .absent:
            return .empty
        case .malformed:
            markMalformedTwitchCredentialsForReauthentication()
            return .empty
        case .valid(let legacy):
            migrateTwitchCredentialGrantBestEffortLocked(legacy)
            return legacy
        }
    }

    /// Reads legacy sources without mutating them. Version 1 remains
    /// authoritative over per-field values even when malformed, preventing a
    /// stale partial account from becoming visible on a later read.
    private static func loadLegacyTwitchCredentialSourceLocked() throws
        -> LegacyTwitchCredentialSource {
        if let encoded = try backend.load(
            account: legacyTwitchCredentialGrantAccount
        ) {
            guard let data = encoded.data(using: .utf8),
                  var migrated = try? JSONDecoder().decode(
                    TwitchCredentialGrant.self,
                    from: data
                  ),
                  (try? validateTwitchCredentialGrant(migrated)) != nil else {
                return .malformed
            }
            if migrated.channelID == nil {
                migrated.channelID = try backend.load(account: twitchChannelIDAccount)
            }
            guard (try? validateTwitchCredentialGrant(migrated)) != nil else {
                return .malformed
            }
            return .valid(migrated)
        }

        let legacy = TwitchCredentialGrant(
            accessToken: try backend.load(account: twitchBotAccountOauthToken),
            refreshToken: try backend.load(account: twitchBotAccountRefreshToken),
            username: try backend.load(account: twitchBotAccountUsername),
            userID: try backend.load(account: twitchBotAccountUserID),
            channelID: try backend.load(account: twitchChannelIDAccount)
        )
        guard !legacy.isEmpty else { return .absent }
        guard (try? validateTwitchCredentialGrant(legacy)) != nil else {
            return .malformed
        }
        return .valid(legacy)
    }

    private static func decodeCurrentTwitchCredentialGrantOrFailClosed(
        _ encoded: String
    ) -> TwitchCredentialGrant {
        guard let data = encoded.data(using: .utf8),
              let decoded = try? JSONDecoder().decode(
                TwitchCredentialGrant.self,
                from: data
              ),
              (try? validateTwitchCredentialGrant(decoded)) != nil else {
            markMalformedTwitchCredentialsForReauthentication()
            return .empty
        }
        // A v2 record is authoritative even when its channel is nil. Never
        // re-adopt a stale separate channel left by best-effort cleanup.
        return decoded
    }

    private static func migrateTwitchCredentialGrantBestEffortLocked(
        _ grant: TwitchCredentialGrant
    ) {
        do {
            try saveTwitchCredentialGrantLocked(grant)
            deleteLegacyTwitchCredentialsBestEffortLocked()
        } catch {
            // Migration is copy-then-delete. Returning the unchanged in-memory
            // snapshot preserves existing users and retries on the next read.
            Log.error(
                "KeychainService: Twitch credential migration deferred - \(error.localizedDescription)",
                category: "Keychain"
            )
        }
    }

    private static func markMalformedTwitchCredentialsForReauthentication() {
        // Retain the malformed authoritative source unchanged. Partially deleting
        // v1/per-field sources could expose a valid-looking stale fragment on the
        // next launch. A later valid v2 commit or factory reset safely cleans it.
        requireTwitchReauthentication()
    }

    private static func saveTwitchCredentialGrantLocked(
        _ grant: TwitchCredentialGrant
    ) throws {
        guard !grant.isEmpty else {
            try deleteTwitchCredentialGrantLocked()
            return
        }
        try saveTwitchCredentialGrantRecordLocked(grant)
    }

    /// Writes an authoritative v2 record, including the encoded-empty tombstone
    /// used as a clear barrier when legacy input is malformed.
    private static func saveTwitchCredentialGrantRecordLocked(
        _ grant: TwitchCredentialGrant
    ) throws {
        try validateTwitchCredentialGrant(grant)
        let data = try JSONEncoder().encode(grant)
        guard let encoded = String(data: data, encoding: .utf8) else {
            throw KeychainError.invalidData
        }
        try backend.save(account: twitchCredentialGrantAccount, value: encoded)
    }

    private static func validateTwitchCredentialGrant(
        _ grant: TwitchCredentialGrant
    ) throws {
        let values = [
            grant.accessToken,
            grant.refreshToken,
            grant.username,
            grant.userID,
            grant.channelID,
        ]
        guard values.compactMap({ $0 }).allSatisfy({ !$0.isEmpty }) else {
            throw KeychainError.invalidData
        }
    }

    private static var legacyTwitchCredentialAccounts: [String] {
        [
            legacyTwitchCredentialGrantAccount,
            twitchBotAccountOauthToken,
            twitchBotAccountRefreshToken,
            twitchBotAccountUsername,
            twitchBotAccountUserID,
            twitchChannelIDAccount,
        ]
    }

    private static func deleteTwitchCredentialGrantLocked() throws {
        if try backend.load(account: twitchCredentialGrantAccount) == nil {
            switch try loadLegacyTwitchCredentialSourceLocked() {
            case .absent:
                break
            case .valid(let grant):
                // Publish the complete legacy snapshot before the first delete.
                try saveTwitchCredentialGrantRecordLocked(grant)
            case .malformed:
                // An encoded-empty v2 item is an authoritative tombstone. It
                // blocks partially deleted malformed sources from exposing a
                // stale fallback if any subsequent delete fails.
                markMalformedTwitchCredentialsForReauthentication()
                try saveTwitchCredentialGrantRecordLocked(.empty)
            }
        }
        for account in legacyTwitchCredentialAccounts {
            try backend.delete(account: account)
        }
        try backend.delete(account: twitchCredentialGrantAccount)
    }

    /// Cleanup after a successful canonical save is best effort because the
    /// canonical record wins every future read even if a stale legacy field
    /// cannot be removed immediately.
    private static func deleteLegacyTwitchCredentialsBestEffortLocked() {
        for account in legacyTwitchCredentialAccounts {
            do {
                try backend.delete(account: account)
            } catch {
                Log.error(
                    "KeychainService: Could not remove legacy Twitch item '\(account)' - \(error.localizedDescription)",
                    category: "Keychain")
            }
        }
    }

    private static func requireTwitchReauthentication() {
        Preferences.setTwitchReauthNeeded(true)
        Task { @MainActor in
            NotificationCenter.default.post(
                name: Notification.Name.twitchReauthNeededChanged,
                object: nil
            )
        }
    }

    static func loadTwitchChannelID() -> String? {
        loadTwitchCredentialGrant().channelID
    }

    // MARK: - Public Methods - Factory Reset

    /// Deletes every WolfWave credential from the Keychain in one sweep.
    ///
    /// Wipes the entire generic-password class for the app's service, so it
    /// covers both WebSocket tokens, all Twitch tokens, and any credential
    /// added later without needing a per-account call. Used by the factory
    /// reset. Succeeds silently if nothing is stored and throws on failure.
    static func deleteAll() throws {
        try twitchCredentialLock.withLock {
            try backend.deleteAll()
        }
    }

    // MARK: - Backend Injection

    /// Raw storage backing every credential operation.
    ///
    /// Test hosts default to process-local storage so no test can touch the
    /// user's real Keychain before a suite installs its own backend. Normal app
    /// launches use the Security framework. Mutated only from serialized tests.
    nonisolated(unsafe) static var backend: KeychainBackend = makeDefaultBackend(
        isRunningTests: WolfWaveApp.isRunningTests
    )

    /// Kept internal so the test suite can pin the security-sensitive branch.
    static func makeDefaultBackend(isRunningTests: Bool) -> KeychainBackend {
        if isRunningTests {
            return InMemoryKeychainBackend()
        }
        return SystemKeychainBackend(service: service)
    }

    // MARK: - Private Helpers

    /// Validates then stores a value via the active backend.
    ///
    /// Empty-value rejection lives here (not in the backend) so the rule holds
    /// regardless of backend and stays unit-testable without the Keychain.
    private static func upsertItem(account: String, value: String) throws {
        guard !value.isEmpty else {
            Log.warn("Keychain: Attempted to save empty value for account \(account)", category: "Keychain")
            throw KeychainError.invalidData
        }
        try backend.save(account: account, value: value)
    }

    /// Loads a string value for the given account via the active backend.
    private static func loadItem(account: String) -> String? {
        do {
            return try backend.load(account: account)
        } catch {
            Log.error(
                "KeychainService: Failed to load item '\(account)' - \(error.localizedDescription)",
                category: "Keychain")
            return nil
        }
    }

    /// Deletes the item for the given account via the active backend.
    private static func deleteItem(account: String) throws {
        try backend.delete(account: account)
    }
}
