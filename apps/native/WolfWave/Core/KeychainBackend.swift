//
//  KeychainBackend.swift
//  WolfWave
//
//  Created by Nathanial Henniges on 2026-06-02.
//  Copyright © 2026 MrDemonWolf, Inc. All rights reserved.
//

import Foundation
import Security

/// Raw key/value storage backing `KeychainService`.
///
/// `KeychainService` owns the credential semantics (account names, empty-value
/// validation, error types, "save username only if changed"). It delegates the
/// actual store/fetch/remove to a `KeychainBackend`. Production uses
/// `SystemKeychainBackend` (Security framework); unit tests inject an in-memory
/// double so the suite never touches the real Keychain. Ad-hoc test signing
/// otherwise triggers an ACL prompt that blocks cold reads and fails CI.
nonisolated protocol KeychainBackend: Sendable {
    /// Stores `value` for `account`, overwriting any existing entry.
    /// - Throws: `KeychainService.KeychainError.saveFailed` on a store failure.
    func save(account: String, value: String) throws

    /// Returns the stored string for `account`, or nil if absent / on error.
    func load(account: String) -> String?

    /// Removes the entry for `account`. Succeeds silently if absent.
    func delete(account: String)

    /// Removes every entry for the backend's service in one sweep.
    /// Succeeds silently if nothing is stored. Used by the factory reset.
    func deleteAll()
}

/// `KeychainBackend` backed by the macOS Security framework (generic passwords).
///
/// Moved out of `KeychainService` verbatim so the credential layer stays
/// unit-testable without the Security framework. All items use
/// `kSecAttrAccessibleAfterFirstUnlock` for persistence after first unlock.
nonisolated final class SystemKeychainBackend: KeychainBackend {
    /// Keychain service identifier (the running bundle id, scoping DEBUG vs release).
    private let service: String

    /// Whether to attach `kSecUseDataProtectionKeychain` to queries.
    ///
    /// The data-protection keychain requires the binary to be signed with a
    /// team identifier matching a declared `keychain-access-groups` entitlement.
    /// Properly signed builds (Apple Development / Developer ID) satisfy this
    /// and benefit from team-ID scoping that survives Xcode dev rebuilds.
    /// Ad-hoc signed builds (CI runners with placeholder configs, "Sign to Run
    /// Locally" without a team) trip `errSecMissingEntitlement` (-34018). For
    /// those we transparently fall back to the legacy file keychain.
    ///
    /// Probed once at init and cached.
    private let useDataProtectionKeychain: Bool

    init(service: String) {
        self.service = service
        self.useDataProtectionKeychain = SystemKeychainBackend.probeDataProtectionKeychain(service: service)
    }

    // MARK: - KeychainBackend

    /// Stores `value` for `account` via `SecItemUpdate`, falling back to
    /// `SecItemAdd`, and self-healing a duplicate whose only difference is
    /// `kSecAttrAccessible`. Throws `KeychainService.KeychainError.saveFailed`.
    func save(account: String, value: String) throws {
        let data = Data(value.utf8)
        let searchQuery = queryFor(account: account)
        let updateAttributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
        ]

        let updateStatus = SecItemUpdate(searchQuery as CFDictionary, updateAttributes as CFDictionary)

        if updateStatus == errSecItemNotFound {
            // Item doesn't exist yet, add it
            var addQuery = searchQuery
            addQuery[kSecValueData as String] = data
            addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
            let addStatus = SecItemAdd(addQuery as CFDictionary, nil)

            if addStatus == errSecDuplicateItem {
                // Update said "not found" but Add says "duplicate": an existing
                // entry differs only in `kSecAttrAccessible`, which `searchQuery`
                // doesn't include and `SecItemUpdate` evaluates as a non-match.
                // Self-heal: delete the mismatched entry and retry once.
                SecItemDelete(searchQuery as CFDictionary)
                let retryStatus = SecItemAdd(addQuery as CFDictionary, nil)
                guard retryStatus == errSecSuccess else {
                    Log.error(
                        "Failed to save \(account) after duplicate-item recovery - OSStatus \(retryStatus)",
                        category: "Keychain"
                    )
                    throw KeychainService.KeychainError.saveFailed(retryStatus)
                }
            } else if addStatus != errSecSuccess {
                Log.error("Failed to save \(account) - OSStatus \(addStatus)", category: "Keychain")
                throw KeychainService.KeychainError.saveFailed(addStatus)
            }
        } else if updateStatus != errSecSuccess {
            Log.error("Failed to update \(account) - OSStatus \(updateStatus)", category: "Keychain")
            throw KeychainService.KeychainError.saveFailed(updateStatus)
        }
    }

    /// Returns the stored string for `account` via `SecItemCopyMatching`, or nil
    /// if absent or on a non-`errSecItemNotFound` error.
    func load(account: String) -> String? {
        var query = queryFor(account: account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)

        guard status == errSecSuccess,
            let data = item as? Data,
            let value = String(data: data, encoding: .utf8)
        else {
            if status != errSecSuccess && status != errSecItemNotFound {
                Log.error("KeychainService: Failed to load item '\(account)' - OSStatus \(status)", category: "Keychain")
            }
            return nil
        }

        return value
    }

    /// Removes the entry for `account` via `SecItemDelete`. Treats a missing
    /// item as success.
    func delete(account: String) {
        let query = queryFor(account: account)
        let status = SecItemDelete(query as CFDictionary)
        if status != errSecSuccess && status != errSecItemNotFound {
            Log.error("KeychainService: Failed to delete item '\(account)' - OSStatus \(status)", category: "Keychain")
        }
    }

    /// Removes every generic-password item for this service via a single
    /// account-less `SecItemDelete`. Treats "nothing matched" as success.
    func deleteAll() {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
        ]
        if useDataProtectionKeychain {
            query[kSecUseDataProtectionKeychain as String] = true
        }
        let status = SecItemDelete(query as CFDictionary)
        if status != errSecSuccess && status != errSecItemNotFound {
            Log.error("KeychainService: Failed to delete all items - OSStatus \(status)", category: "Keychain")
        }
    }

    // MARK: - Private Helpers

    /// Builds a base query dictionary for the given account.
    ///
    /// When the data-protection keychain is available, sets
    /// `kSecUseDataProtectionKeychain` so items are team-ID scoped (modern
    /// backend) rather than bound to the creating binary's code-signing
    /// requirement (legacy file keychain). This makes Xcode dev rebuilds keep
    /// saved tokens across runs, matching release behavior.
    private func queryFor(account: String) -> [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        if useDataProtectionKeychain {
            query[kSecUseDataProtectionKeychain as String] = true
        }
        return query
    }

    /// One-shot capability probe: try to add + delete a throwaway item with the
    /// data-protection flag set. If that yields `errSecMissingEntitlement`, the
    /// binary lacks the team-ID-bound entitlement needed for the modern backend
    /// (typically ad-hoc signing in CI), and we fall back to the legacy keychain.
    private static func probeDataProtectionKeychain(service: String) -> Bool {
        let probeAccount = "__wolfwave_dp_probe__"
        let probeData = Data("probe".utf8)
        let addQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: probeAccount,
            kSecValueData as String: probeData,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
            kSecUseDataProtectionKeychain as String: true,
        ]
        let addStatus = SecItemAdd(addQuery as CFDictionary, nil)

        // Already-exists from a prior probe is fine, backend supports it.
        let supports = addStatus == errSecSuccess || addStatus == errSecDuplicateItem

        if supports {
            let deleteQuery: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecAttrAccount as String: probeAccount,
                kSecUseDataProtectionKeychain as String: true,
            ]
            _ = SecItemDelete(deleteQuery as CFDictionary)
        }
        return supports
    }
}
