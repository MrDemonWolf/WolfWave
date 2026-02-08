//
//  KeychainService.swift
//  wolfwave
//
//  Created by MrDemonWolf, Inc. on 1/17/26.
//

import Foundation
import Security

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
enum KeychainService {
    // MARK: - Constants

    /// Service identifier for Keychain items (bundle-like identifier).
    private static let service = "com.mrdemonwolf.wolfwave"

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

    // MARK: - Private Helpers

    /// Builds a base query dictionary for the given account.
    private static func queryFor(account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }

    /// Loads a string value from the Keychain for the given account.
    private static func loadItem(account: String) -> String? {
        var query = queryFor(account: account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)

        guard status == errSecSuccess,
            let data = item as? Data,
            let value = String(data: data, encoding: .utf8)
        else {
            return nil
        }

        return value
    }

    /// Deletes a Keychain item for the given account. Succeeds silently if not found.
    private static func deleteItem(account: String) {
        let query = queryFor(account: account)
        SecItemDelete(query as CFDictionary)
    }

    /// Inserts or updates a Keychain item using SecItemUpdate with SecItemAdd fallback.
    ///
    /// This is more efficient than delete+add: a single Keychain roundtrip for updates,
    /// with an automatic fallback to add when the item doesn't exist yet.
    private static func upsertItem(account: String, value: String) throws {
        let data = Data(value.utf8)
        let searchQuery = queryFor(account: account)
        let updateAttributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
        ]

        let updateStatus = SecItemUpdate(searchQuery as CFDictionary, updateAttributes as CFDictionary)

        if updateStatus == errSecItemNotFound {
            // Item doesn't exist yet — add it
            var addQuery = searchQuery
            addQuery[kSecValueData as String] = data
            addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
            let addStatus = SecItemAdd(addQuery as CFDictionary, nil)

            guard addStatus == errSecSuccess else {
                Log.error("Failed to save \(account) - OSStatus \(addStatus)", category: "Keychain")
                throw KeychainError.saveFailed(addStatus)
            }
        } else if updateStatus != errSecSuccess {
            Log.error("Failed to update \(account) - OSStatus \(updateStatus)", category: "Keychain")
            throw KeychainError.saveFailed(updateStatus)
        }
    }
}
