//
//  KeychainService.swift
//  wolfwave
//
//  Created by MrDemonWolf, Inc. on 1/17/26.
//

import Foundation
import Security

/// Secure storage for authentication tokens using the macOS Keychain.
///
/// Stores:
/// - WebSocket auth token
/// - Twitch OAuth token, username, user ID
/// - Twitch channel ID
///
/// All items use `kSecAttrAccessibleAfterFirstUnlock` for persistent access after device unlock.
enum KeychainService {
    // MARK: - Constants

    private static let service = "com.mrdemonwolf.wolfwave"

    private static let websocketAuthToken = "websocketAuthToken"
    private static let twitchBotAccountOauthToken = "twitchBotAccountOauthToken"
    private static let twitchBotAccountUsername = "twitchBotAccountUsername"
    private static let twitchBotAccountUserID = "twitchBotAccountUserID"
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

    static func saveToken(_ token: String) throws {
        Log.debug("Saving WebSocket auth token", category: "Keychain")
        let data = Data(token.utf8)

        deleteToken()

        let query = buildQuery(withData: data)
        let status = SecItemAdd(query as CFDictionary, nil)

        guard status == errSecSuccess else {
            Log.error("Failed to save token - OSStatus \(status)", category: "Keychain")
            throw KeychainError.saveFailed(status)
        }
        Log.info("WebSocket auth token saved successfully", category: "Keychain")
    }

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

    static func deleteToken() {
        let query = buildBaseQuery()
        SecItemDelete(query as CFDictionary)
    }

    // MARK: - Twitch Token Methods

    static func saveTwitchToken(_ token: String) throws {
        Log.debug("Saving Twitch OAuth token", category: "Keychain")
        let data = Data(token.utf8)
        var query = buildBaseQuery()
        query[kSecAttrAccount as String] = twitchBotAccountOauthToken

        Log.debug("Removing existing Twitch OAuth token", category: "Keychain")
        SecItemDelete(query as CFDictionary)

        query[kSecValueData as String] = data
        query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        let status = SecItemAdd(query as CFDictionary, nil)

        guard status == errSecSuccess else {
            Log.error("Failed to save Twitch OAuth token - OSStatus \(status)", category: "Keychain")
            throw KeychainError.saveFailed(status)
        }
        Log.info("Twitch OAuth token saved successfully", category: "Keychain")
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
        Log.debug("Saving Twitch bot username: \(username)", category: "Keychain")
        let data = Data(username.utf8)
        var query = buildBaseQuery()
        query[kSecAttrAccount as String] = twitchBotAccountUsername

        Log.debug("Removing existing Twitch bot username", category: "Keychain")
        SecItemDelete(query as CFDictionary)

        query[kSecValueData as String] = data
        query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        let status = SecItemAdd(query as CFDictionary, nil)

        guard status == errSecSuccess else {
            Log.error("Failed to save Twitch bot username - OSStatus \(status)", category: "Keychain")
            throw KeychainError.saveFailed(status)
        }
        Log.info("Twitch bot username saved successfully", category: "Keychain")
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
