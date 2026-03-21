//
//  KeychainServiceTests.swift
//  wolfwave
//
//  Created by MrDemonWolf, Inc. on 1/17/26.
//

import Testing
import Foundation
@testable import WolfWave

/// Comprehensive test suite for KeychainService
@Suite("Keychain Service Tests")
struct KeychainServiceTests {

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
        let testToken = "twitch_oauth_\(UUID().uuidString)"

        try KeychainService.saveTwitchToken(testToken)
        let loaded = KeychainService.loadTwitchToken()

        #expect(loaded == testToken)

        KeychainService.deleteTwitchToken()
        #expect(KeychainService.loadTwitchToken() == nil)
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
        let testUsername = "testbot_\(UUID().uuidString)"

        try KeychainService.saveTwitchUsername(testUsername)
        let loaded = KeychainService.loadTwitchUsername()

        #expect(loaded == testUsername)

        KeychainService.deleteTwitchUsername()
        #expect(KeychainService.loadTwitchUsername() == nil)
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
        let testUserID = "12345678"

        try KeychainService.saveTwitchBotUserID(testUserID)
        let loaded = KeychainService.loadTwitchBotUserID()

        #expect(loaded == testUserID)

        KeychainService.deleteTwitchBotUserID()
        #expect(KeychainService.loadTwitchBotUserID() == nil)
    }

    // MARK: - Twitch Channel ID Tests

    @Test("Save and load Twitch channel ID")
    func testTwitchChannelID() async throws {
        let testChannelID = "testchannel"

        try KeychainService.saveTwitchChannelID(testChannelID)
        let loaded = KeychainService.loadTwitchChannelID()

        #expect(loaded == testChannelID)

        KeychainService.deleteTwitchChannelID()
        #expect(KeychainService.loadTwitchChannelID() == nil)
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
        let iterations = 100

        await withTaskGroup(of: Void.self) { group in
            // Multiple concurrent writes
            for i in 0..<iterations {
                group.addTask {
                    let token = "concurrent_token_\(i)"
                    try? KeychainService.saveToken(token)
                }
            }

            // Multiple concurrent reads
            for _ in 0..<iterations {
                group.addTask {
                    _ = KeychainService.loadToken()
                }
            }
        }

        // Cleanup
        KeychainService.deleteToken()

        // Test should complete without crashes
        #expect(true)
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
}
