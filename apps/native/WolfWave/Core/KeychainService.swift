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
/// - **WebSocket Auth Token**: Generic password for WebSocket authentication
/// - **Twitch OAuth Token**: User's OAuth token for Twitch API and chat
/// - **Twitch Username**: Bot account username for display and identification
/// - **Twitch User ID**: Bot account user ID for EventSub subscriptions
/// - **Twitch Channel ID**: Target channel for bot commands
///
/// Error Handling:
/// - All save operations throw `KeychainError` on failure
/// - Load operations return nil if not found or on error
/// - Delete operations succeed silently if item doesn't exist
///
/// Thread Safety:
/// - Keychain operations are thread-safe (backed by Security framework)
/// - Safe to call from any thread
///
/// Usage Example:
/// ```swift
/// try KeychainService.saveTwitchToken("oauth_token_here")
/// if let token = KeychainService.loadTwitchToken() {
///     // Use token for Twitch API calls
/// }
/// ```
nonisolated enum KeychainService {
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

    /// Account identifier for WebSocket auth token.
    private static let websocketAuthToken = "websocketAuthToken"

    /// Account identifier for Twitch OAuth token.
    private static let twitchBotAccountOauthToken = "twitchBotAccountOauthToken"

    /// Account identifier for Twitch bot username.
    private static let twitchBotAccountUsername = "twitchBotAccountUsername"

    /// Account identifier for Twitch bot user ID.
    private static let twitchBotAccountUserID = "twitchBotAccountUserID"

    /// Account identifier for Twitch channel ID.
    private static let twitchChannelIDAccount = "twitchChannelIDAccount"

    // MARK: - Error Types

    /// Errors that can occur during Keychain operations.
    enum KeychainError: LocalizedError {
        /// Failed to save data to Keychain with given Security framework status code.
        case saveFailed(OSStatus)

        /// Invalid or corrupted data read from Keychain.
        case invalidData

        var errorDescription: String? {
            switch self {
            case .saveFailed(let status):
                return "Failed to save token to Keychain (status: \(status))"
            case .invalidData:
                return "Invalid token data"
            }
        }
    }

    // MARK: - Public Methods - WebSocket Token

    /// Saves a WebSocket authentication token to Keychain.
    ///
    /// Uses update-or-add pattern for efficiency (single Keychain roundtrip when updating).
    ///
    /// - Parameter token: The authentication token to save.
    /// - Throws: `KeychainError.saveFailed(status)` if Keychain operation fails.
    static func saveToken(_ token: String) throws {
        try upsertItem(account: websocketAuthToken, value: token)
    }

    /// Loads the WebSocket authentication token from Keychain.
    ///
    /// - Returns: The stored token string, or nil if not found or on error.
    static func loadToken() -> String? {
        loadItem(account: websocketAuthToken)
    }

    /// Deletes the WebSocket authentication token from Keychain.
    ///
    /// Succeeds silently if token doesn't exist.
    static func deleteToken() {
        deleteItem(account: websocketAuthToken)
    }

    // MARK: - Public Methods - Twitch OAuth Token

    /// Saves the Twitch OAuth token to Keychain.
    ///
    /// - Parameter token: The OAuth token obtained from Twitch OAuth flow.
    /// - Throws: `KeychainError.saveFailed(status)` if Keychain operation fails.
    static func saveTwitchToken(_ token: String) throws {
        try upsertItem(account: twitchBotAccountOauthToken, value: token)
    }

    static func saveTwitchUsernameIfChanged(_ username: String) throws {
        if let existing = loadTwitchUsername(), existing == username {
            return
        }
        try saveTwitchUsername(username)
    }

    static func loadTwitchToken() -> String? {
        loadItem(account: twitchBotAccountOauthToken)
    }

    static func deleteTwitchToken() {
        deleteItem(account: twitchBotAccountOauthToken)
    }

    // MARK: - Twitch Username Methods

    static func saveTwitchUsername(_ username: String) throws {
        try upsertItem(account: twitchBotAccountUsername, value: username)
    }

    static func loadTwitchUsername() -> String? {
        loadItem(account: twitchBotAccountUsername)
    }

    static func deleteTwitchUsername() {
        deleteItem(account: twitchBotAccountUsername)
    }

    // MARK: - Twitch Bot User ID Methods

    static func saveTwitchBotUserID(_ userID: String) throws {
        try upsertItem(account: twitchBotAccountUserID, value: userID)
    }

    static func loadTwitchBotUserID() -> String? {
        loadItem(account: twitchBotAccountUserID)
    }

    static func deleteTwitchBotUserID() {
        deleteItem(account: twitchBotAccountUserID)
    }

    // MARK: - Twitch Channel ID Methods

    static func saveTwitchChannelID(_ channelID: String) throws {
        try upsertItem(account: twitchChannelIDAccount, value: channelID)
    }

    static func loadTwitchChannelID() -> String? {
        loadItem(account: twitchChannelIDAccount)
    }

    static func deleteTwitchChannelID() {
        deleteItem(account: twitchChannelIDAccount)
    }

    // MARK: - Backend Injection

    /// Raw storage backing every credential operation.
    ///
    /// Defaults to `SystemKeychainBackend` (Security framework). Unit tests swap
    /// in an in-memory double so the suite never touches the real Keychain.
    /// Ad-hoc test signing otherwise triggers an ACL prompt that blocks cold
    /// reads and fails CI. Mutated only from serialized tests.
    nonisolated(unsafe) static var backend: KeychainBackend = SystemKeychainBackend(service: service)

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
        backend.load(account: account)
    }

    /// Deletes the item for the given account via the active backend.
    private static func deleteItem(account: String) {
        backend.delete(account: account)
    }
}
