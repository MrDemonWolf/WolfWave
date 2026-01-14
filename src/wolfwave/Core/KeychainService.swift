//
//  KeychainService.swift
//  wolfwave
//
//  Created by MrDemonWolf, Inc. on 1/8/26.
//

import Foundation
import Security

/// A service that handles secure storage and retrieval of authentication tokens using the macOS Keychain.
///
/// Stored items (service: `com.mrdemonwolf.wolfwave`):
/// - WebSocket auth token (`websocketAuthToken`)
/// - Twitch OAuth token (`twitchBotAccountOauthToken`)
/// - Twitch bot username (`twitchBotAccountUsername`)
/// - Twitch bot user ID (`twitchBotAccountUserID`)
/// - Twitch channel ID (`twitchChannelIDAccount`)
///
/// Notes:
/// - Items are saved with `kSecAttrAccessibleAfterFirstUnlock` so they remain
///   accessible while the device is unlocked after a restart.
/// - All methods are synchronous wrappers around Keychain APIs and will throw
///   `KeychainError` on save failures.
enum KeychainService {
    // MARK: - Constants

    /// The service identifier for keychain items
    private static let service = "com.mrdemonwolf.wolfwave"

    /// The account name for the WebSocket authentication token
    private static let websocketAuthToken = "websocketAuthToken"

    /// The account name for the Twitch OAuth token
    private static let twitchBotAccountOauthToken = "twitchBotAccountOauthToken"

    /// The account name for the Twitch bot username
    private static let twitchBotAccountUsername = "twitchBotAccountUsername"

    /// The account name for the Twitch bot user ID
    private static let twitchBotAccountUserID = "twitchBotAccountUserID"

    /// The account name for the Twitch channel ID
    private static let twitchChannelIDAccount = "twitchChannelIDAccount"

    // MARK: - Error

    enum KeychainError: LocalizedError {
        case saveFailed(OSStatus)
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

    // MARK: - Public Methods

    /// Saves an authentication token securely to the macOS Keychain.
    ///
    /// This method will first delete any existing token with the same service and account,
    /// then add the new token to ensure no duplicates exist.
    ///
    /// - Parameter token: The authentication token string to save
    /// - Throws: KeychainError if the token cannot be saved to the Keychain
    static func saveToken(_ token: String) throws {
        Log.debug("Keychain: Saving WebSocket auth token", category: "Keychain")
        let data = Data(token.utf8)

        // Remove existing item to avoid duplicates
        deleteToken()

        // Add new item
        let query = buildQuery(withData: data)
        let status = SecItemAdd(query as CFDictionary, nil)

        guard status == errSecSuccess else {
            Log.error("Keychain: Failed to save token - OSStatus \(status)", category: "Keychain")
            throw KeychainError.saveFailed(status)
        }
        Log.info("Keychain: WebSocket auth token saved successfully", category: "Keychain")
    }

    /// Retrieves the stored authentication token from the macOS Keychain.
    ///
    /// - Returns: The stored token string if found, or nil if no token exists or an error occurs
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

    /// Removes the stored authentication token from the macOS Keychain.
    ///
    /// This method will silently succeed even if no token exists.
    static func deleteToken() {
        let query = buildBaseQuery()
        SecItemDelete(query as CFDictionary)
    }

    // MARK: - Twitch Token Methods

    /// Saves a Twitch OAuth token securely to the macOS Keychain.
    ///
    /// - Parameter token: The Twitch OAuth token string to save
    /// - Throws: KeychainError if the token cannot be saved to the Keychain
    static func saveTwitchToken(_ token: String) throws {
        Log.debug("Keychain: Saving Twitch OAuth token", category: "Keychain")
        let data = Data(token.utf8)
        var query = buildBaseQuery()
        query[kSecAttrAccount as String] = twitchBotAccountOauthToken

        // Remove existing item to avoid duplicates
        Log.debug("Keychain: Removing existing Twitch OAuth token", category: "Keychain")
        SecItemDelete(query as CFDictionary)

        // Add new item
        query[kSecValueData as String] = data
        query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        let status = SecItemAdd(query as CFDictionary, nil)

        guard status == errSecSuccess else {
            Log.error(
                "Keychain: Failed to save Twitch OAuth token - OSStatus \(status)",
                category: "Keychain")
            throw KeychainError.saveFailed(status)
        }
        Log.info("Keychain: Twitch OAuth token saved successfully", category: "Keychain")
    }

    /// Retrieves the stored Twitch OAuth token from the macOS Keychain.
    ///
    /// - Returns: The stored Twitch OAuth token string if found, or nil if no token exists
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

    /// Removes the stored Twitch OAuth token from the macOS Keychain.
    static func deleteTwitchToken() {
        var query = buildBaseQuery()
        query[kSecAttrAccount as String] = twitchBotAccountOauthToken
        SecItemDelete(query as CFDictionary)
    }

    // MARK: - Twitch Username Methods

    /// Saves a Twitch bot username to the macOS Keychain.
    ///
    /// - Parameter username: The Twitch bot username to save
    /// - Throws: KeychainError if the username cannot be saved to the Keychain
    static func saveTwitchUsername(_ username: String) throws {
        Log.debug("Keychain: Saving Twitch bot username: \(username)", category: "Keychain")
        let data = Data(username.utf8)
        var query = buildBaseQuery()
        query[kSecAttrAccount as String] = twitchBotAccountUsername

        // Remove existing item to avoid duplicates
        Log.debug("Keychain: Removing existing Twitch bot username", category: "Keychain")
        SecItemDelete(query as CFDictionary)

        // Add new item
        query[kSecValueData as String] = data
        query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        let status = SecItemAdd(query as CFDictionary, nil)

        guard status == errSecSuccess else {
            Log.error(
                "Keychain: Failed to save Twitch bot username - OSStatus \(status)",
                category: "Keychain")
            throw KeychainError.saveFailed(status)
        }
        Log.info("Keychain: Twitch bot username saved successfully", category: "Keychain")
    }

    /// Retrieves the stored Twitch bot username from the macOS Keychain.
    ///
    /// - Returns: The stored Twitch bot username if found, or nil if no username exists
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

    /// Removes the stored Twitch bot username from the macOS Keychain.
    static func deleteTwitchUsername() {
        var query = buildBaseQuery()
        query[kSecAttrAccount as String] = twitchBotAccountUsername
        SecItemDelete(query as CFDictionary)
    }

    // MARK: - Twitch Bot User ID Methods

    /// Saves a Twitch bot user ID to the macOS Keychain.
    static func saveTwitchBotUserID(_ userID: String) throws {
        let data = Data(userID.utf8)
        var query = buildBaseQuery()
        query[kSecAttrAccount as String] = twitchBotAccountUserID

        SecItemDelete(query as CFDictionary)

        query[kSecValueData as String] = data
        query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        let status = SecItemAdd(query as CFDictionary, nil)

        guard status == errSecSuccess else {
            throw KeychainError.saveFailed(status)
        }
    }

    /// Retrieves the stored Twitch bot user ID from the macOS Keychain.
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

    /// Removes the stored Twitch bot user ID from the macOS Keychain.
    static func deleteTwitchBotUserID() {
        var query = buildBaseQuery()
        query[kSecAttrAccount as String] = twitchBotAccountUserID
        SecItemDelete(query as CFDictionary)
    }

    // MARK: - Twitch Channel ID Methods

    /// Saves a Twitch channel ID to the macOS Keychain.
    ///
    /// - Parameter channelID: The Twitch channel ID to save
    /// - Throws: KeychainError if the channel ID cannot be saved to the Keychain
    static func saveTwitchChannelID(_ channelID: String) throws {
        let data = Data(channelID.utf8)
        var query = buildBaseQuery()
        query[kSecAttrAccount as String] = twitchChannelIDAccount

        // Remove existing item to avoid duplicates
        SecItemDelete(query as CFDictionary)

        // Add new item
        query[kSecValueData as String] = data
        query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        let status = SecItemAdd(query as CFDictionary, nil)

        guard status == errSecSuccess else {
            throw KeychainError.saveFailed(status)
        }
    }

    /// Retrieves the stored Twitch channel ID from the macOS Keychain.
    ///
    /// - Returns: The stored Twitch channel ID if found, or nil if no channel ID exists
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

    /// Removes the stored Twitch channel ID from the macOS Keychain.
    static func deleteTwitchChannelID() {
        var query = buildBaseQuery()
        query[kSecAttrAccount as String] = twitchChannelIDAccount
        SecItemDelete(query as CFDictionary)
    }

    // MARK: - Private Helpers

    /// Builds the base keychain query dictionary
    private static func buildBaseQuery() -> [String: Any] {
        return [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: websocketAuthToken,
        ]
    }

    /// Builds a keychain query with data for saving
    private static func buildQuery(withData data: Data) -> [String: Any] {
        var query = buildBaseQuery()
        query[kSecValueData as String] = data
        query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        return query
    }
}
