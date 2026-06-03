//
//  KeychainServiceTests.swift
//  WolfWave
//
//  Created by Nathanial Henniges on 2026-02-27.
//  Copyright © 2026 MrDemonWolf, Inc. All rights reserved.
//

import Testing
import Foundation
@testable import WolfWave

/// Comprehensive test suite for KeychainService.
///
/// Runs against an in-memory backend (`InMemoryKeychainBackend`) so the suite
/// never touches the real Keychain. Ad-hoc test signing otherwise triggers an
/// ACL prompt that blocks cold reads and fails CI. The system backend is
/// restored after each test so other suites see unchanged behavior.
///
/// Note: `.serialized` keeps tests sequential, matching the shared-backend model.
@Suite("Keychain Service Tests", .serialized)
final class KeychainServiceTests {

    private let previousBackend: KeychainBackend

    init() {
        previousBackend = KeychainService.backend
        KeychainService.backend = InMemoryKeychainBackend()
    }

    deinit {
        KeychainService.backend = previousBackend
    }

    // MARK: - Token Save/Load/Delete Tests

    @Test("Save and load token successfully")
    func testSaveAndLoadToken() async throws {
        let testToken = "test_token_\(UUID().uuidString)"

        // Save token
        try KeychainService.saveToken(testToken)

        // Load token
        let loadedToken = KeychainService.loadToken()

        // Verify
        #expect(loadedToken == testToken)

        // Cleanup
        KeychainService.deleteToken()
    }

    @Test("Delete token removes it from keychain")
    func testDeleteToken() async throws {
        let testToken = "test_token_delete"

        // Save token
        try KeychainService.saveToken(testToken)

        // Verify it exists
        #expect(KeychainService.loadToken() == testToken)

        // Delete token
        KeychainService.deleteToken()

        // Verify it's gone
        #expect(KeychainService.loadToken() == nil)
    }

    @Test("Save empty token throws error")
    func testSaveEmptyToken() async throws {
        // Attempt to save empty token should throw
        #expect(throws: KeychainService.KeychainError.self) {
            try KeychainService.saveToken("")
        }
    }

    @Test("Update existing token")
    func testUpdateToken() async throws {
        let token1 = "first_token"
        let token2 = "second_token"

        // Save first token
        try KeychainService.saveToken(token1)
        #expect(KeychainService.loadToken() == token1)

        // Update to second token
        try KeychainService.saveToken(token2)
        #expect(KeychainService.loadToken() == token2)

        // Cleanup
        KeychainService.deleteToken()
    }

    // MARK: - Twitch Token Tests

    @Test("Save and load Twitch token")
    func testTwitchToken() async throws {
        try assertKeychainRoundTrip(
            "twitch_oauth_\(UUID().uuidString)",
            save: KeychainService.saveTwitchToken,
            load: KeychainService.loadTwitchToken,
            delete: KeychainService.deleteTwitchToken
        )
    }

    @Test("Save empty Twitch token throws error")
    func testSaveEmptyTwitchToken() async throws {
        #expect(throws: KeychainService.KeychainError.self) {
            try KeychainService.saveTwitchToken("")
        }
    }

    // MARK: - Twitch Username Tests

    @Test("Save and load Twitch username")
    func testTwitchUsername() async throws {
        try assertKeychainRoundTrip(
            "testbot_\(UUID().uuidString)",
            save: KeychainService.saveTwitchUsername,
            load: KeychainService.loadTwitchUsername,
            delete: KeychainService.deleteTwitchUsername
        )
    }

    @Test("Save username only if changed")
    func testSaveUsernameIfChanged() async throws {
        let username = "unchangedbot"

        // Save initially
        try KeychainService.saveTwitchUsername(username)

        // Save again with same username (should not throw)
        try KeychainService.saveTwitchUsernameIfChanged(username)

        // Verify it's still the same
        #expect(KeychainService.loadTwitchUsername() == username)

        // Save with different username
        let newUsername = "changedbot"
        try KeychainService.saveTwitchUsernameIfChanged(newUsername)

        // Verify it changed
        #expect(KeychainService.loadTwitchUsername() == newUsername)

        // Cleanup
        KeychainService.deleteTwitchUsername()
    }

    // MARK: - Twitch Bot User ID Tests

    @Test("Save and load Twitch bot user ID")
    func testTwitchBotUserID() async throws {
        try assertKeychainRoundTrip(
            "12345678",
            save: KeychainService.saveTwitchBotUserID,
            load: KeychainService.loadTwitchBotUserID,
            delete: KeychainService.deleteTwitchBotUserID
        )
    }

    // MARK: - Twitch Channel ID Tests

    @Test("Save and load Twitch channel ID")
    func testTwitchChannelID() async throws {
        try assertKeychainRoundTrip(
            "testchannel",
            save: KeychainService.saveTwitchChannelID,
            load: KeychainService.loadTwitchChannelID,
            delete: KeychainService.deleteTwitchChannelID
        )
    }

    // MARK: - Special Characters Tests

    @Test("Handle special characters in saved values")
    func testSpecialCharacters() async throws {
        let specialToken = "token_with_!@#$%^&*()_+-=[]{}|;:',.<>?/~`"

        try KeychainService.saveToken(specialToken)
        let loaded = KeychainService.loadToken()

        #expect(loaded == specialToken)

        KeychainService.deleteToken()
    }

    @Test("Handle Unicode in saved values")
    func testUnicodeCharacters() async throws {
        let unicodeUsername = "testbot_🐺🎵"

        try KeychainService.saveTwitchUsername(unicodeUsername)
        let loaded = KeychainService.loadTwitchUsername()

        #expect(loaded == unicodeUsername)

        KeychainService.deleteTwitchUsername()
    }

    // MARK: - Concurrent Access Tests

    @Test("Concurrent save and load operations are thread-safe")
    func testConcurrentAccess() async throws {
        let iterations = 50
        let group = DispatchGroup()
        let queue = DispatchQueue(label: "keychain.stress", attributes: .concurrent)
        var readResults: [String?] = Array(repeating: nil, count: iterations)
        let resultsLock = NSLock()

        // Seed with a known value first
        try KeychainService.saveToken("seed_token")

        // Concurrent writes and reads on real threads
        for i in 0..<iterations {
            group.enter()
            queue.async {
                let token = "concurrent_token_\(i)"
                try? KeychainService.saveToken(token)
                group.leave()
            }

            group.enter()
            queue.async {
                let loaded = KeychainService.loadToken()
                resultsLock.lock()
                readResults[i] = loaded
                resultsLock.unlock()
                group.leave()
            }
        }

        await withCheckedContinuation { continuation in
            group.notify(queue: .global()) { continuation.resume() }
        }

        // Validate: every read should have returned a non-nil, non-empty token
        // (since we seeded and continuously wrote valid tokens)
        for (index, result) in readResults.enumerated() {
            #expect(result != nil, "Read at index \(index) returned nil: possible corruption")
            if let value = result {
                #expect(!value.isEmpty, "Read at index \(index) returned empty string: possible corruption")
            }
        }

        // Final state: a valid token should be loadable
        let finalToken = KeychainService.loadToken()
        #expect(finalToken != nil, "Final read after concurrent stress should return a valid token")

        // Cleanup
        KeychainService.deleteToken()
    }

    // MARK: - Error Handling Tests

    @Test("KeychainError has correct descriptions")
    func testKeychainErrorDescriptions() async throws {
        let saveError = KeychainService.KeychainError.saveFailed(-25300)
        #expect(saveError.errorDescription == "Failed to save token to Keychain (status: -25300)")

        let invalidError = KeychainService.KeychainError.invalidData
        #expect(invalidError.errorDescription == "Invalid token data")
    }

    @Test("Save failed errors with different status codes are distinct")
    func testSaveFailedWithDifferentStatus() async throws {
        let error1 = KeychainService.KeychainError.saveFailed(-25299)
        let error2 = KeychainService.KeychainError.saveFailed(-25300)
        #expect(error1.errorDescription != error2.errorDescription)
    }

    @Test("Delete nonexistent key does not throw")
    func testDeleteNonexistentKeyDoesNotThrow() async throws {
        KeychainService.deleteTwitchChannelID()
        KeychainService.deleteTwitchChannelID()
        // Should succeed silently
        #expect(true)
    }

    // MARK: - Overwrite Contract

    @Test("saveToken overwrites a pre-existing value")
    func testSaveTokenOverwritesExistingValue() async throws {
        // Seed a stale value, then overwrite via the public API. The upsert path
        // must replace it without throwing. (The SystemKeychainBackend's
        // duplicate-item self-heal (recovering from an errSecDuplicateItem with
        // a mismatched kSecAttrAccessible) is Security-framework specific and is
        // exercised only in integration, not against the in-memory backend.)
        try KeychainService.saveToken("stale_token")
        #expect(KeychainService.loadToken() == "stale_token")

        let fresh = "fresh_token_\(UUID().uuidString)"
        try KeychainService.saveToken(fresh)
        #expect(KeychainService.loadToken() == fresh)

        KeychainService.deleteToken()
    }
}
