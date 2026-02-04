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
    /// Removes any existing token before saving to ensure only one token exists.
    ///
    /// - Parameter token: The authentication token to save.
    /// - Throws: `KeychainError.saveFailed(status)` if Keychain operation fails.
    static func saveToken(_ token: String) throws {
        // Avoid unnecessary Keychain writes when the token hasn't changed.
        if let existing = loadToken(), existing == token {
            return
        }

        let data = Data(token.utf8)

        deleteToken()

        let query = buildQuery(withData: data)
        let status = SecItemAdd(query as CFDictionary, nil)

        guard status == errSecSuccess else {
            Log.error("Failed to save token - OSStatus \(status)", category: "Keychain")
            throw KeychainError.saveFailed(status)
        }
    }

    /// Loads the WebSocket authentication token from Keychain.
    ///
    /// - Returns: The stored token string, or nil if not found or on error.
    static func loadToken() -> String? {
        var query = buildBaseQuery()
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)

        guard status == errSecSuccess,
            let data = item as? Data,
            let token = String(data: data, encoding: .utf8)
        else {
            return nil
        }

        return token
    }

    /// Deletes the WebSocket authentication token from Keychain.
    ///
    /// Succeeds silently if token doesn't exist.
    static func deleteToken() {
        let query = buildBaseQuery()
        SecItemDelete(query as CFDictionary)
    }

    // MARK: - Public Methods - Twitch OAuth Token

    /// Saves the Twitch OAuth token to Keychain.
    ///
    /// - Parameter token: The OAuth token obtained from Twitch OAuth flow.
    /// - Throws: `KeychainError.saveFailed(status)` if Keychain operation fails.
    static func saveTwitchToken(_ token: String) throws {
        // Avoid unnecessary Keychain writes when the token hasn't changed.
        if let existing = loadTwitchToken(), existing == token {
            return
        }

        let data = Data(token.utf8)
        var query = buildBaseQuery()
        query[kSecAttrAccount as String] = twitchBotAccountOauthToken

        SecItemDelete(query as CFDictionary)

        query[kSecValueData as String] = data
        query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        let status = SecItemAdd(query as CFDictionary, nil)

        guard status == errSecSuccess else {
            Log.error(
                "Failed to save Twitch OAuth token - OSStatus \(status)", category: "Keychain")
            throw KeychainError.saveFailed(status)
        }
    }

    static func saveTwitchUsernameIfChanged(_ username: String) throws {
        if let existing = loadTwitchUsername(), existing == username {
            return
        }
        try saveTwitchUsername(username)
    }

    static func loadTwitchToken() -> String? {
        var query = buildBaseQuery()
        query[kSecAttrAccount as String] = twitchBotAccountOauthToken
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)

        guard status == errSecSuccess,
            let data = item as? Data,
            let token = String(data: data, encoding: .utf8)
        else {
            return nil
        }

        return token
    }

    static func deleteTwitchToken() {
        var query = buildBaseQuery()
        query[kSecAttrAccount as String] = twitchBotAccountOauthToken
        SecItemDelete(query as CFDictionary)
    }

    // MARK: - Twitch Username Methods

    static func saveTwitchUsername(_ username: String) throws {
        let data = Data(username.utf8)
        var query = buildBaseQuery()
        query[kSecAttrAccount as String] = twitchBotAccountUsername

        SecItemDelete(query as CFDictionary)

        query[kSecValueData as String] = data
        query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        let status = SecItemAdd(query as CFDictionary, nil)

        guard status == errSecSuccess else {
            Log.error(
                "Failed to save Twitch bot username - OSStatus \(status)", category: "Keychain")
            throw KeychainError.saveFailed(status)
        }
    }

    static func loadTwitchUsername() -> String? {
        var query = buildBaseQuery()
        query[kSecAttrAccount as String] = twitchBotAccountUsername
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)

        guard status == errSecSuccess,
            let data = item as? Data,
            let username = String(data: data, encoding: .utf8)
        else {
            return nil
        }

        return username
    }

    static func deleteTwitchUsername() {
        var query = buildBaseQuery()
        query[kSecAttrAccount as String] = twitchBotAccountUsername
        SecItemDelete(query as CFDictionary)
    }

    // MARK: - Twitch Bot User ID Methods

    static func saveTwitchBotUserID(_ userID: String) throws {
        let data = Data(userID.utf8)
        var query = buildBaseQuery()
        query[kSecAttrAccount as String] = twitchBotAccountUserID

        SecItemDelete(query as CFDictionary)

        query[kSecValueData as String] = data
        query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        let status = SecItemAdd(query as CFDictionary, nil)

        guard status == errSecSuccess else {
            Log.error(
                "Failed to save Twitch bot user ID - OSStatus \(status)", category: "Keychain")
            throw KeychainError.saveFailed(status)
        }
    }

    static func loadTwitchBotUserID() -> String? {
        var query = buildBaseQuery()
        query[kSecAttrAccount as String] = twitchBotAccountUserID
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)

        guard status == errSecSuccess,
            let data = item as? Data,
            let userID = String(data: data, encoding: .utf8)
        else {
            return nil
        }

        return userID
    }

    static func deleteTwitchBotUserID() {
        var query = buildBaseQuery()
        query[kSecAttrAccount as String] = twitchBotAccountUserID
        SecItemDelete(query as CFDictionary)
    }

    // MARK: - Twitch Channel ID Methods

    static func saveTwitchChannelID(_ channelID: String) throws {
        let data = Data(channelID.utf8)
        var query = buildBaseQuery()
        query[kSecAttrAccount as String] = twitchChannelIDAccount

        SecItemDelete(query as CFDictionary)

        query[kSecValueData as String] = data
        query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        let status = SecItemAdd(query as CFDictionary, nil)

        guard status == errSecSuccess else {
            Log.error(
                "Failed to save Twitch channel ID - OSStatus \(status)", category: "Keychain")
            throw KeychainError.saveFailed(status)
        }
    }

    static func loadTwitchChannelID() -> String? {
        var query = buildBaseQuery()
        query[kSecAttrAccount as String] = twitchChannelIDAccount
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)

        guard status == errSecSuccess,
            let data = item as? Data,
            let channelID = String(data: data, encoding: .utf8)
        else {
            return nil
        }

        return channelID
    }

    static func deleteTwitchChannelID() {
        var query = buildBaseQuery()
        query[kSecAttrAccount as String] = twitchChannelIDAccount
        SecItemDelete(query as CFDictionary)
    }

    // MARK: - Private Helpers

    private static func buildBaseQuery() -> [String: Any] {
        return [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: websocketAuthToken,
        ]
    }

    private static func buildQuery(withData data: Data) -> [String: Any] {
        var query = buildBaseQuery()
        query[kSecValueData as String] = data
        query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        return query
    }
}
