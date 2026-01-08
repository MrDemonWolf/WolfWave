//
//  KeychainService.swift
//  packtrack
//
//  Created by Nathanial Henniges on 1/8/26.
//

import Foundation
import Security

/// A service that handles secure storage and retrieval of authentication tokens using macOS Keychain.
/// This ensures sensitive data like JWT tokens are never stored in UserDefaults or plain text files.
enum KeychainService {
    /// The service identifier for keychain items
    static let service = "com.mrdemonwolf.packtrack"
    
    /// The account name for the WebSocket authentication token
    static let account = "websocketAuthToken"

    /// Saves an authentication token securely to the macOS Keychain.
    ///
    /// This method will first delete any existing token with the same service and account,
    /// then add the new token to ensure no duplicates exist.
    ///
    /// - Parameter token: The authentication token string to save
    /// - Throws: NSError if the token cannot be saved to the Keychain
    static func saveToken(_ token: String) throws {
        let data = Data(token.utf8)

        // Remove existing item if present
        let deleteQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(deleteQuery as CFDictionary)

        // Add new item
        let addQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]

        let status = SecItemAdd(addQuery as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw NSError(domain: "Keychain", code: Int(status))
        }
    }

    /// Retrieves the stored authentication token from the macOS Keychain.
    ///
    /// - Returns: The stored token string if found, or nil if no token exists or an error occurs
    static func loadToken() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)

        guard
            status == errSecSuccess,
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
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]

        SecItemDelete(query as CFDictionary)
    }
}
