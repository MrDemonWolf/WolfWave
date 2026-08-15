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
/// ACL prompt that blocks cold reads and fails CI. The previous backend is
/// restored after each test so other suites see unchanged behavior.
///
/// Note: `.serialized` keeps tests sequential, matching the shared-backend model.
@Suite("Keychain Service Tests", .serialized, .isolatedKeychainBackend)
final class KeychainServiceTests {

    private let previousBackend: KeychainBackend

    init() {
        KeychainBackendTestIsolation.acquire()
        previousBackend = KeychainService.backend
        KeychainService.backend = InMemoryKeychainBackend()
    }

    deinit {
        KeychainService.backend = previousBackend
        KeychainBackendTestIsolation.release()
    }

    @Test("Test hosts default to process-local credentials")
    func testHostUsesInMemoryBackend() {
        #expect(WolfWaveApp.isRunningTests)
        #expect(previousBackend is InMemoryKeychainBackend)
        #expect(KeychainService.makeDefaultBackend(isRunningTests: true) is InMemoryKeychainBackend)
    }

    // MARK: - Suite Isolation

    /// Pins `.isolatedKeychainBackend`. A trait that silently stopped binding
    /// would leave every test below passing while the suite went back to sharing
    /// one process-wide backend with the suites running beside it.
    @Test("Suite runs against a task-scoped backend")
    func testSuiteBindsTaskScopedBackend() {
        #expect(KeychainService.backendBox != nil)
    }

    /// The property the whole suite depends on: a backend installed in here is
    /// unreachable from a task outside the scope, so a parallel suite can
    /// neither observe nor mutate it.
    @Test("Backends installed in the suite stay invisible to outside tasks")
    func testInstalledBackendIsInvisibleOutsideTheSuite() async {
        let originalBackend = KeychainService.backend
        let marker = InspectableKeychainBackend()
        KeychainService.backend = marker
        defer { KeychainService.backend = originalBackend }

        let outside = await Task.detached { KeychainService.backend }.value

        #expect(KeychainService.backend as AnyObject === marker)
        #expect(outside as AnyObject !== marker)
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
        try KeychainService.deleteToken()
    }

    @Test("Delete token removes it from keychain")
    func testDeleteToken() async throws {
        let testToken = "test_token_delete"

        // Save token
        try KeychainService.saveToken(testToken)

        // Verify it exists
        #expect(KeychainService.loadToken() == testToken)

        // Delete token
        try KeychainService.deleteToken()

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
        try KeychainService.deleteToken()
    }

    @Test("Control token has independent save, load, and delete lifecycle")
    func testControlTokenRoundTrip() async throws {
        let token = "control_token"

        try KeychainService.saveControlToken(token)

        #expect(KeychainService.loadControlToken() == token)
        #expect(KeychainService.loadToken() == nil)

        try KeychainService.deleteControlToken()
        #expect(KeychainService.loadControlToken() == nil)
    }

    @Test("Save empty control token throws error")
    func testSaveEmptyControlToken() async throws {
        #expect(throws: KeychainService.KeychainError.self) {
            try KeychainService.saveControlToken("")
        }
    }

    // MARK: - Twitch Token Tests

    @Test("Legacy Twitch fields migrate only after the atomic grant saves")
    func testLegacyTwitchCredentialsMigrateCopyThenDelete() {
        let originalBackend = KeychainService.backend
        let backend = InspectableKeychainBackend()
        KeychainService.backend = backend
        defer { KeychainService.backend = originalBackend }

        backend.seed(account: "twitchBotAccountOauthToken", value: "ACCESS")
        backend.seed(
            account: AppConstants.Keychain.twitchBotAccountRefreshToken,
            value: "REFRESH")
        backend.seed(account: "twitchBotAccountUsername", value: "wolf")
        backend.seed(account: "twitchBotAccountUserID", value: "123")
        backend.seed(account: "twitchChannelIDAccount", value: "channel")

        #expect(
            KeychainService.loadTwitchCredentialGrant()
                == .init(
                    accessToken: "ACCESS",
                    refreshToken: "REFRESH",
                    username: "wolf",
                    userID: "123",
                    channelID: "channel")
        )
        #expect(backend.rawValue(account: KeychainService.twitchCredentialGrantAccount) != nil)
        #expect(backend.rawValue(account: "twitchBotAccountOauthToken") == nil)
        #expect(
            backend.rawValue(
                account: AppConstants.Keychain.twitchBotAccountRefreshToken) == nil)
        #expect(backend.rawValue(account: "twitchBotAccountUsername") == nil)
        #expect(backend.rawValue(account: "twitchBotAccountUserID") == nil)
        #expect(backend.rawValue(account: "twitchChannelIDAccount") == nil)
    }

    @Test("Version-one grant and separate channel migrate copy-then-delete")
    func testVersionOneGrantAndChannelMigrateCopyThenDelete() throws {
        let originalBackend = KeychainService.backend
        let backend = InspectableKeychainBackend()
        KeychainService.backend = backend
        defer { KeychainService.backend = originalBackend }
        let versionOne = KeychainService.TwitchCredentialGrant(
            accessToken: "ACCESS",
            refreshToken: "REFRESH",
            username: "wolf",
            userID: "123"
        )
        let encoded = try #require(
            String(data: JSONEncoder().encode(versionOne), encoding: .utf8)
        )
        backend.seed(
            account: KeychainService.legacyTwitchCredentialGrantAccount,
            value: encoded
        )
        backend.seed(account: "twitchChannelIDAccount", value: "channel")

        let migrated = try KeychainService.loadTwitchCredentialGrantChecked()

        #expect(migrated == .init(
            accessToken: "ACCESS",
            refreshToken: "REFRESH",
            username: "wolf",
            userID: "123",
            channelID: "channel"
        ))
        #expect(backend.rawValue(account: KeychainService.twitchCredentialGrantAccount) != nil)
        #expect(
            backend.rawValue(
                account: KeychainService.legacyTwitchCredentialGrantAccount) == nil)
        #expect(backend.rawValue(account: "twitchChannelIDAccount") == nil)
    }

    @Test("Failed version-one migration preserves both sources for retry")
    func testVersionOneMigrationFailurePreservesGrantAndChannel() throws {
        let originalBackend = KeychainService.backend
        let backend = InspectableKeychainBackend()
        KeychainService.backend = backend
        defer { KeychainService.backend = originalBackend }
        let versionOne = KeychainService.TwitchCredentialGrant(
            accessToken: "ACCESS",
            refreshToken: "REFRESH"
        )
        let encoded = try #require(
            String(data: JSONEncoder().encode(versionOne), encoding: .utf8)
        )
        backend.seed(
            account: KeychainService.legacyTwitchCredentialGrantAccount,
            value: encoded
        )
        backend.seed(account: "twitchChannelIDAccount", value: "channel")
        backend.failNextSave(for: KeychainService.twitchCredentialGrantAccount)

        let inMemory = try KeychainService.loadTwitchCredentialGrantChecked()

        #expect(inMemory.channelID == "channel")
        #expect(backend.rawValue(account: KeychainService.twitchCredentialGrantAccount) == nil)
        #expect(
            backend.rawValue(
                account: KeychainService.legacyTwitchCredentialGrantAccount) == encoded)
        #expect(backend.rawValue(account: "twitchChannelIDAccount") == "channel")
        #expect(try KeychainService.loadTwitchCredentialGrantChecked() == inMemory)
        #expect(backend.rawValue(account: KeychainService.twitchCredentialGrantAccount) != nil)
        #expect(
            backend.rawValue(
                account: KeychainService.legacyTwitchCredentialGrantAccount) == nil)
        #expect(backend.rawValue(account: "twitchChannelIDAccount") == nil)
    }

    @Test("Version-two grant never adopts a stale separate channel")
    func testCurrentGrantWinsOverStaleLegacyChannel() throws {
        let originalBackend = KeychainService.backend
        let backend = InspectableKeychainBackend()
        KeychainService.backend = backend
        defer { KeychainService.backend = originalBackend }
        let current = KeychainService.TwitchCredentialGrant(accessToken: "ACCESS")
        try KeychainService.saveTwitchCredentialGrant(current)
        backend.seed(account: "twitchChannelIDAccount", value: "stale-channel")

        #expect(try KeychainService.loadTwitchCredentialGrantChecked() == current)
        #expect(KeychainService.loadTwitchChannelID() == nil)
    }

    @Test("Failed atomic migration leaves every legacy field for retry")
    func testLegacyTwitchMigrationFailurePreservesSourceFields() {
        let originalBackend = KeychainService.backend
        let backend = InspectableKeychainBackend()
        KeychainService.backend = backend
        defer { KeychainService.backend = originalBackend }

        backend.seed(account: "twitchBotAccountOauthToken", value: "ACCESS")
        backend.seed(
            account: AppConstants.Keychain.twitchBotAccountRefreshToken,
            value: "REFRESH")
        backend.seed(account: "twitchBotAccountUsername", value: "wolf")
        backend.seed(account: "twitchBotAccountUserID", value: "123")
        backend.seed(account: "twitchChannelIDAccount", value: "channel")
        backend.failNextSave(for: KeychainService.twitchCredentialGrantAccount)

        let legacy = KeychainService.loadTwitchCredentialGrant()
        #expect(legacy.accessToken == "ACCESS")
        #expect(legacy.refreshToken == "REFRESH")
        #expect(legacy.channelID == "channel")
        #expect(backend.rawValue(account: KeychainService.twitchCredentialGrantAccount) == nil)
        #expect(backend.rawValue(account: "twitchBotAccountOauthToken") == "ACCESS")
        #expect(
            backend.rawValue(
                account: AppConstants.Keychain.twitchBotAccountRefreshToken) == "REFRESH")
        #expect(backend.rawValue(account: "twitchBotAccountUsername") == "wolf")
        #expect(backend.rawValue(account: "twitchBotAccountUserID") == "123")
        #expect(backend.rawValue(account: "twitchChannelIDAccount") == "channel")

        // The one-shot failure is gone, so the next read retries migration.
        #expect(KeychainService.loadTwitchCredentialGrant() == legacy)
        #expect(backend.rawValue(account: KeychainService.twitchCredentialGrantAccount) != nil)
        #expect(backend.rawValue(account: "twitchBotAccountOauthToken") == nil)
        #expect(backend.rawValue(account: "twitchBotAccountUsername") == nil)
        #expect(backend.rawValue(account: "twitchBotAccountUserID") == nil)
        #expect(backend.rawValue(account: "twitchChannelIDAccount") == nil)
    }

    @Test("Malformed atomic Twitch grant fails closed instead of mixing legacy fields")
    func testMalformedAtomicTwitchGrantRequiresReauthentication() {
        let originalBackend = KeychainService.backend
        let backend = InspectableKeychainBackend()
        KeychainService.backend = backend
        Preferences.setTwitchReauthNeeded(false)
        defer {
            Preferences.setTwitchReauthNeeded(false)
            KeychainService.backend = originalBackend
        }

        backend.seed(
            account: KeychainService.twitchCredentialGrantAccount,
            value: "not-json")
        backend.seed(account: "twitchBotAccountOauthToken", value: "STALE_ACCESS")

        #expect(KeychainService.loadTwitchCredentialGrant() == .empty)
        #expect(KeychainService.loadTwitchCredentialGrant() == .empty)
        #expect(Preferences.twitchReauthNeeded)
        #expect(
            backend.rawValue(
                account: KeychainService.twitchCredentialGrantAccount) == "not-json")
        #expect(backend.rawValue(account: "twitchBotAccountOauthToken") == "STALE_ACCESS")
    }

    @Test("Malformed version-one grant stays authoritative across repeated reads")
    func testMalformedVersionOneGrantNeverExposesPerFieldFallback() {
        let originalBackend = KeychainService.backend
        let backend = InspectableKeychainBackend()
        KeychainService.backend = backend
        Preferences.setTwitchReauthNeeded(false)
        defer {
            Preferences.setTwitchReauthNeeded(false)
            KeychainService.backend = originalBackend
        }
        backend.seed(
            account: KeychainService.legacyTwitchCredentialGrantAccount,
            value: "not-json"
        )
        backend.seed(account: "twitchBotAccountOauthToken", value: "STALE_ACCESS")
        backend.seed(account: "twitchChannelIDAccount", value: "stale-channel")

        #expect(KeychainService.loadTwitchCredentialGrant() == .empty)
        #expect(KeychainService.loadTwitchCredentialGrant() == .empty)
        #expect(Preferences.twitchReauthNeeded)
        #expect(
            backend.rawValue(
                account: KeychainService.legacyTwitchCredentialGrantAccount)
                == "not-json"
        )
        #expect(backend.rawValue(account: "twitchBotAccountOauthToken") == "STALE_ACCESS")
        #expect(backend.rawValue(account: "twitchChannelIDAccount") == "stale-channel")
        #expect(backend.rawValue(account: KeychainService.twitchCredentialGrantAccount) == nil)
    }

    @Test("Malformed per-field grant remains intact across repeated reads")
    func testMalformedPerFieldGrantNeverExposesPartialCredential() {
        let originalBackend = KeychainService.backend
        let backend = InspectableKeychainBackend()
        KeychainService.backend = backend
        Preferences.setTwitchReauthNeeded(false)
        defer {
            Preferences.setTwitchReauthNeeded(false)
            KeychainService.backend = originalBackend
        }
        backend.seed(account: "twitchBotAccountOauthToken", value: "")
        backend.seed(
            account: AppConstants.Keychain.twitchBotAccountRefreshToken,
            value: "REFRESH"
        )
        backend.seed(account: "twitchChannelIDAccount", value: "channel")

        #expect(KeychainService.loadTwitchCredentialGrant() == .empty)
        #expect(KeychainService.loadTwitchCredentialGrant() == .empty)
        #expect(Preferences.twitchReauthNeeded)
        #expect(backend.rawValue(account: "twitchBotAccountOauthToken") == "")
        #expect(
            backend.rawValue(
                account: AppConstants.Keychain.twitchBotAccountRefreshToken)
                == "REFRESH"
        )
        #expect(backend.rawValue(account: "twitchChannelIDAccount") == "channel")
        #expect(backend.rawValue(account: KeychainService.twitchCredentialGrantAccount) == nil)
    }

    @Test("Atomic grant read failure never probes or mutates legacy credentials")
    func testAtomicGrantLoadFailureDoesNotInspectLegacy() throws {
        let originalBackend = KeychainService.backend
        let backend = InspectableKeychainBackend()
        KeychainService.backend = backend
        defer { KeychainService.backend = originalBackend }

        let legacyFields = [
            (KeychainService.legacyTwitchCredentialGrantAccount, "v1"),
            ("twitchBotAccountOauthToken", "ACCESS"),
            (AppConstants.Keychain.twitchBotAccountRefreshToken, "REFRESH"),
            ("twitchBotAccountUsername", "wolf"),
            ("twitchBotAccountUserID", "123"),
            ("twitchChannelIDAccount", "channel"),
        ]
        for (account, value) in legacyFields {
            backend.seed(account: account, value: value)
        }
        backend.failNextLoad(
            for: KeychainService.twitchCredentialGrantAccount,
            status: -25308)

        #expect(throws: KeychainService.KeychainError.self) {
            _ = try KeychainService.loadTwitchCredentialGrantChecked()
        }
        #expect(
            backend.loadCount(
                account: KeychainService.twitchCredentialGrantAccount) == 1)
        for (account, value) in legacyFields {
            #expect(backend.loadCount(account: account) == 0)
            #expect(backend.rawValue(account: account) == value)
        }
    }

    @Test("Every legacy delete failure preserves the canonical Twitch grant")
    func testLegacyDeleteFailuresPreserveCanonicalGrant() throws {
        let originalBackend = KeychainService.backend
        defer { KeychainService.backend = originalBackend }
        let legacyAccounts = [
            KeychainService.legacyTwitchCredentialGrantAccount,
            "twitchBotAccountOauthToken",
            AppConstants.Keychain.twitchBotAccountRefreshToken,
            "twitchBotAccountUsername",
            "twitchBotAccountUserID",
            "twitchChannelIDAccount",
        ]
        let grant = KeychainService.TwitchCredentialGrant(
            accessToken: "ACCESS",
            refreshToken: "REFRESH",
            username: "wolf",
            userID: "123")

        for failingAccount in legacyAccounts {
            let backend = InspectableKeychainBackend()
            KeychainService.backend = backend
            try KeychainService.saveTwitchCredentialGrant(grant)
            for account in legacyAccounts {
                backend.seed(account: account, value: "legacy-\(account)")
            }
            let canonical = backend.rawValue(
                account: KeychainService.twitchCredentialGrantAccount)
            backend.failNextDelete(for: failingAccount)

            #expect(throws: KeychainService.KeychainError.self) {
                try KeychainService.deleteTwitchCredentialGrant()
            }
            #expect(
                backend.rawValue(
                    account: KeychainService.twitchCredentialGrantAccount)
                    == canonical)
            let surviving = try KeychainService.loadTwitchCredentialGrantChecked()
            #expect(surviving == grant)
        }
    }

    @Test("Every version-one clear prefix materializes the complete v2 grant")
    func testVersionOneClearPrefixesRemainCoherent() throws {
        let originalBackend = KeychainService.backend
        defer { KeychainService.backend = originalBackend }
        let legacyAccounts = [
            KeychainService.legacyTwitchCredentialGrantAccount,
            "twitchBotAccountOauthToken",
            AppConstants.Keychain.twitchBotAccountRefreshToken,
            "twitchBotAccountUsername",
            "twitchBotAccountUserID",
            "twitchChannelIDAccount",
            KeychainService.twitchCredentialGrantAccount,
        ]
        let versionOne = KeychainService.TwitchCredentialGrant(
            accessToken: "ACCESS",
            refreshToken: "REFRESH",
            username: "wolf",
            userID: "123"
        )
        let encoded = try #require(
            String(data: JSONEncoder().encode(versionOne), encoding: .utf8)
        )
        let expected = KeychainService.TwitchCredentialGrant(
            accessToken: "ACCESS",
            refreshToken: "REFRESH",
            username: "wolf",
            userID: "123",
            channelID: "channel"
        )

        for failingAccount in legacyAccounts {
            let backend = InspectableKeychainBackend()
            KeychainService.backend = backend
            backend.seed(
                account: KeychainService.legacyTwitchCredentialGrantAccount,
                value: encoded
            )
            backend.seed(account: "twitchChannelIDAccount", value: "channel")
            backend.failNextDelete(for: failingAccount)

            #expect(throws: KeychainService.KeychainError.self) {
                try KeychainService.deleteTwitchCredentialGrant()
            }
            #expect(
                try KeychainService.loadTwitchCredentialGrantChecked()
                    == expected
            )
        }
    }

    @Test("Every per-field clear prefix materializes the complete v2 grant")
    func testPerFieldClearPrefixesRemainCoherent() throws {
        let originalBackend = KeychainService.backend
        defer { KeychainService.backend = originalBackend }
        let legacyValues = [
            "twitchBotAccountOauthToken": "ACCESS",
            AppConstants.Keychain.twitchBotAccountRefreshToken: "REFRESH",
            "twitchBotAccountUsername": "wolf",
            "twitchBotAccountUserID": "123",
            "twitchChannelIDAccount": "channel",
        ]
        let deleteAccounts = [
            KeychainService.legacyTwitchCredentialGrantAccount,
            "twitchBotAccountOauthToken",
            AppConstants.Keychain.twitchBotAccountRefreshToken,
            "twitchBotAccountUsername",
            "twitchBotAccountUserID",
            "twitchChannelIDAccount",
            KeychainService.twitchCredentialGrantAccount,
        ]
        let expected = KeychainService.TwitchCredentialGrant(
            accessToken: "ACCESS",
            refreshToken: "REFRESH",
            username: "wolf",
            userID: "123",
            channelID: "channel"
        )

        for failingAccount in deleteAccounts {
            let backend = InspectableKeychainBackend()
            KeychainService.backend = backend
            for (account, value) in legacyValues {
                backend.seed(account: account, value: value)
            }
            backend.failNextDelete(for: failingAccount)

            #expect(throws: KeychainService.KeychainError.self) {
                try KeychainService.deleteTwitchCredentialGrant()
            }
            #expect(
                try KeychainService.loadTwitchCredentialGrantChecked()
                    == expected
            )
        }
    }

    @Test("Malformed legacy clear prefixes remain behind an authoritative tombstone")
    func testMalformedLegacyClearPrefixesNeverExposeFallback() throws {
        let originalBackend = KeychainService.backend
        defer {
            Preferences.setTwitchReauthNeeded(false)
            KeychainService.backend = originalBackend
        }
        let deleteAccounts = [
            KeychainService.legacyTwitchCredentialGrantAccount,
            "twitchBotAccountOauthToken",
            AppConstants.Keychain.twitchBotAccountRefreshToken,
            "twitchBotAccountUsername",
            "twitchBotAccountUserID",
            "twitchChannelIDAccount",
            KeychainService.twitchCredentialGrantAccount,
        ]

        for failingAccount in deleteAccounts {
            let backend = InspectableKeychainBackend()
            KeychainService.backend = backend
            Preferences.setTwitchReauthNeeded(false)
            backend.seed(
                account: KeychainService.legacyTwitchCredentialGrantAccount,
                value: "not-json"
            )
            backend.seed(account: "twitchBotAccountOauthToken", value: "STALE_ACCESS")
            backend.seed(account: "twitchChannelIDAccount", value: "stale-channel")
            backend.failNextDelete(for: failingAccount)

            #expect(throws: KeychainService.KeychainError.self) {
                try KeychainService.deleteTwitchCredentialGrant()
            }
            #expect(try KeychainService.loadTwitchCredentialGrantChecked() == .empty)
            #expect(
                backend.rawValue(
                    account: KeychainService.twitchCredentialGrantAccount) != nil
            )
            #expect(Preferences.twitchReauthNeeded)
        }
    }

    @Test("Clear aborts before deleting legacy data when the v2 barrier cannot save")
    func testLegacyClearBarrierSaveFailurePreservesEverySource() throws {
        let originalBackend = KeychainService.backend
        let backend = InspectableKeychainBackend()
        KeychainService.backend = backend
        defer { KeychainService.backend = originalBackend }
        let fields = [
            "twitchBotAccountOauthToken": "ACCESS",
            AppConstants.Keychain.twitchBotAccountRefreshToken: "REFRESH",
            "twitchBotAccountUsername": "wolf",
            "twitchBotAccountUserID": "123",
            "twitchChannelIDAccount": "channel",
        ]
        for (account, value) in fields {
            backend.seed(account: account, value: value)
        }
        backend.failNextSave(for: KeychainService.twitchCredentialGrantAccount)

        #expect(throws: InspectableKeychainBackend.InjectedError.self) {
            try KeychainService.deleteTwitchCredentialGrant()
        }

        for (account, value) in fields {
            #expect(backend.rawValue(account: account) == value)
        }
        #expect(backend.rawValue(account: KeychainService.twitchCredentialGrantAccount) == nil)
    }

    @Test("Channel-preserving clear failure preserves the account and revision")
    func testChannelPreservingClearFailurePreservesAccountAndRevision() throws {
        let originalBackend = KeychainService.backend
        let backend = InspectableKeychainBackend()
        KeychainService.backend = backend
        defer { KeychainService.backend = originalBackend }
        let grant = KeychainService.TwitchCredentialGrant(
            accessToken: "ACCESS",
            refreshToken: "REFRESH",
            username: "wolf",
            userID: "123",
            channelID: "channel")
        try KeychainService.saveTwitchCredentialGrant(grant)
        let snapshot = try #require(
            TwitchCredentialStore.shared.connectionSnapshot(
                matchingAccessToken: "ACCESS"))
        backend.failNextSave(
            for: KeychainService.twitchCredentialGrantAccount)

        #expect(throws: InspectableKeychainBackend.InjectedError.self) {
            try TwitchCredentialStore.shared.clearCredentials(
                includingChannel: false)
        }

        #expect(try KeychainService.loadTwitchCredentialGrantChecked() == grant)
        #expect(
            TwitchCredentialStore.shared.revision(
                matchingAccessToken: "ACCESS") == snapshot.revision)
    }

    @Test("Channel-preserving clear atomically leaves only the channel")
    func testChannelPreservingClearLeavesChannelOnly() throws {
        let originalBackend = KeychainService.backend
        let backend = InspectableKeychainBackend()
        KeychainService.backend = backend
        defer { KeychainService.backend = originalBackend }
        try KeychainService.saveTwitchCredentialGrant(
            .init(
                accessToken: "ACCESS",
                refreshToken: "REFRESH",
                username: "wolf",
                userID: "123",
                channelID: "channel"
            )
        )

        try TwitchCredentialStore.shared.clearCredentials(includingChannel: false)

        #expect(
            try KeychainService.loadTwitchCredentialGrantChecked()
                == .init(channelID: "channel"))
        #expect(KeychainService.loadTwitchToken() == nil)
        #expect(KeychainService.loadTwitchChannelID() == "channel")
    }

    @Test("Full clear failure preserves the complete account and revision")
    func testFullClearFailurePreservesAccountAndRevision() throws {
        let originalBackend = KeychainService.backend
        let backend = InspectableKeychainBackend()
        KeychainService.backend = backend
        defer { KeychainService.backend = originalBackend }
        let grant = KeychainService.TwitchCredentialGrant(
            accessToken: "ACCESS",
            refreshToken: "REFRESH",
            username: "wolf",
            userID: "123",
            channelID: "channel"
        )
        try KeychainService.saveTwitchCredentialGrant(grant)
        let snapshot = try #require(
            TwitchCredentialStore.shared.connectionSnapshot(
                matchingAccessToken: "ACCESS")
        )
        backend.failNextDelete(
            for: KeychainService.twitchCredentialGrantAccount
        )

        #expect(throws: KeychainService.KeychainError.self) {
            try TwitchCredentialStore.shared.clearCredentials(
                includingChannel: true)
        }

        #expect(try KeychainService.loadTwitchCredentialGrantChecked() == grant)
        #expect(
            TwitchCredentialStore.shared.connectionSnapshot(
                matchingAccessToken: "ACCESS") == snapshot
        )
    }

    @Test("Channel updates preserve the grant and stale CAS cannot overwrite it")
    func testChannelUpdateAndCompareAndSwap() throws {
        let originalBackend = KeychainService.backend
        let backend = InspectableKeychainBackend()
        KeychainService.backend = backend
        defer { KeychainService.backend = originalBackend }
        let grant = KeychainService.TwitchCredentialGrant(
            accessToken: "ACCESS",
            refreshToken: "REFRESH",
            username: "wolf",
            userID: "123",
            channelID: "old-channel"
        )
        try KeychainService.saveTwitchCredentialGrant(grant)
        let original = try #require(
            TwitchCredentialStore.shared.connectionSnapshot(
                matchingAccessToken: "ACCESS")
        )

        try TwitchCredentialStore.shared.updateChannelID("old-channel")
        #expect(
            TwitchCredentialStore.shared.connectionSnapshot(
                matchingAccessToken: "ACCESS") == original
        )

        try TwitchCredentialStore.shared.updateChannelID("new-channel")
        let updated = try KeychainService.loadTwitchCredentialGrantChecked()
        #expect(updated.accessToken == grant.accessToken)
        #expect(updated.refreshToken == grant.refreshToken)
        #expect(updated.username == grant.username)
        #expect(updated.userID == grant.userID)
        #expect(updated.channelID == "new-channel")
        let staleCommit = try TwitchCredentialStore.shared.commitChannelID(
            "stale-channel",
            expected: original
        )
        #expect(staleCommit == nil)
        #expect(
            try KeychainService.loadTwitchCredentialGrantChecked().channelID
                == "new-channel"
        )
    }

    @Test("Channel CAS commits once, no-ops unchanged, and preserves state on failure")
    func testChannelCompareAndSwapCommitLifecycle() throws {
        let originalBackend = KeychainService.backend
        let backend = InspectableKeychainBackend()
        KeychainService.backend = backend
        defer { KeychainService.backend = originalBackend }
        let originalGrant = KeychainService.TwitchCredentialGrant(
            accessToken: "ACCESS",
            refreshToken: "REFRESH",
            username: "wolf",
            userID: "123",
            channelID: "old-channel"
        )
        try KeychainService.saveTwitchCredentialGrant(originalGrant)
        let originalSnapshot = try #require(
            TwitchCredentialStore.shared.connectionSnapshot(
                matchingAccessToken: "ACCESS")
        )

        let commitResult = try TwitchCredentialStore.shared.commitChannelID(
            "new-channel",
            expected: originalSnapshot
        )
        let committed = try #require(commitResult)
        #expect(committed.channelID == "new-channel")
        #expect(committed.revision == originalSnapshot.revision &+ 1)
        let afterCommit = try KeychainService.loadTwitchCredentialGrantChecked()
        #expect(afterCommit.accessToken == originalGrant.accessToken)
        #expect(afterCommit.refreshToken == originalGrant.refreshToken)
        #expect(afterCommit.username == originalGrant.username)
        #expect(afterCommit.userID == originalGrant.userID)
        #expect(afterCommit.channelID == "new-channel")

        let unchangedResult = try TwitchCredentialStore.shared.commitChannelID(
            "new-channel",
            expected: committed
        )
        let unchanged = try #require(unchangedResult)
        #expect(unchanged == committed)

        backend.failNextSave(
            for: KeychainService.twitchCredentialGrantAccount
        )
        #expect(throws: InspectableKeychainBackend.InjectedError.self) {
            try TwitchCredentialStore.shared.commitChannelID(
                "failed-channel",
                expected: unchanged
            )
        }
        #expect(try KeychainService.loadTwitchCredentialGrantChecked() == afterCommit)
        #expect(
            TwitchCredentialStore.shared.connectionSnapshot(
                matchingAccessToken: "ACCESS") == unchanged
        )
    }

    @Test("Credential clear removes every legacy field and canonical grant")
    func testCredentialClearRemovesLegacyAndCanonicalItems() throws {
        let originalBackend = KeychainService.backend
        let backend = InspectableKeychainBackend()
        KeychainService.backend = backend
        defer { KeychainService.backend = originalBackend }
        let legacyAccounts = [
            KeychainService.legacyTwitchCredentialGrantAccount,
            "twitchBotAccountOauthToken",
            AppConstants.Keychain.twitchBotAccountRefreshToken,
            "twitchBotAccountUsername",
            "twitchBotAccountUserID",
            "twitchChannelIDAccount",
        ]
        try KeychainService.saveTwitchCredentialGrant(
            .init(
                accessToken: "ACCESS",
                refreshToken: "REFRESH",
                username: "wolf",
                userID: "123"))
        for account in legacyAccounts {
            backend.seed(account: account, value: "legacy")
        }

        try KeychainService.deleteTwitchCredentialGrant()

        for account in legacyAccounts {
            #expect(backend.rawValue(account: account) == nil)
        }
        #expect(
            backend.rawValue(
                account: KeychainService.twitchCredentialGrantAccount) == nil)
        #expect(try KeychainService.loadTwitchCredentialGrantChecked() == .empty)
    }

    @Test("Factory reset Keychain deletion failure preserves stored data")
    func testDeleteAllFailurePreservesCredentials() throws {
        let originalBackend = KeychainService.backend
        let backend = InspectableKeychainBackend()
        KeychainService.backend = backend
        defer { KeychainService.backend = originalBackend }
        try KeychainService.saveToken("overlay-token")
        backend.failNextDeleteAll(status: -25308)

        #expect(throws: KeychainService.KeychainError.self) {
            try KeychainService.deleteAll()
        }
        #expect(KeychainService.loadToken() == "overlay-token")
    }

    @Test("Auth clear failure preserves credentials, UI, and validation owner")
    func testClearAuthFailurePreservesState() async throws {
        let originalBackend = KeychainService.backend
        let backend = InspectableKeychainBackend()
        KeychainService.backend = backend
        defer { KeychainService.backend = originalBackend }
        let grant = KeychainService.TwitchCredentialGrant(
            accessToken: "ACCESS",
            refreshToken: "REFRESH",
            username: "wolf",
            userID: "123",
            channelID: "channel")
        try KeychainService.saveTwitchCredentialGrant(grant)
        let revision = try #require(
            TwitchCredentialStore.shared.revision(
                matchingAccessToken: "ACCESS"))
        let cancellations = ThreadSafeBox(0)
        let restarts = ThreadSafeBox(0)
        let viewModel = await MainActor.run {
            let viewModel = TwitchViewModel(
                cancelTokenValidationSchedule: {
                    cancellations.mutate { $0 += 1 }
                },
                restartTokenValidationSchedule: {
                    restarts.mutate { $0 += 1 }
                },
                leaveAccountService: { _, _ in true })
            viewModel.botUsername = "wolf"
            viewModel.oauthToken = "ACCESS"
            viewModel.channelID = "channel"
            viewModel.credentialsSaved = true
            return viewModel
        }
        backend.failNextSave(
            for: KeychainService.twitchCredentialGrantAccount)

        let cleared = await viewModel.clearAuthOnly()
        let viewState = await MainActor.run {
            (
                botUsername: viewModel.botUsername,
                oauthToken: viewModel.oauthToken,
                channelID: viewModel.channelID,
                credentialsSaved: viewModel.credentialsSaved,
                errorID: viewModel.connectionError?.id,
                isAccountTeardownInProgress: viewModel.isAccountTeardownInProgress
            )
        }

        #expect(!cleared)
        #expect(viewState.botUsername == "wolf")
        #expect(viewState.oauthToken == "ACCESS")
        #expect(viewState.channelID == "channel")
        #expect(viewState.credentialsSaved)
        #expect(viewState.errorID == "twitch.credentialClearFailed")
        #expect(!viewState.isAccountTeardownInProgress)
        #expect(cancellations.value == 1)
        #expect(restarts.value == 1)
        #expect(try KeychainService.loadTwitchCredentialGrantChecked() == grant)
        #expect(
            TwitchCredentialStore.shared.revision(
                matchingAccessToken: "ACCESS") == revision)
    }

    @Test("Full Twitch grant backs every read convenience")
    func testFullTwitchGrantReadConveniences() throws {
        let grant = KeychainService.TwitchCredentialGrant(
            accessToken: "ACCESS",
            refreshToken: "REFRESH",
            username: "wolf",
            userID: "123",
            channelID: "channel"
        )

        try KeychainService.saveTwitchCredentialGrant(grant)

        #expect(KeychainService.loadTwitchToken() == "ACCESS")
        #expect(KeychainService.loadTwitchRefreshToken() == "REFRESH")
        #expect(KeychainService.loadTwitchUsername() == "wolf")
        #expect(KeychainService.loadTwitchBotUserID() == "123")
        #expect(KeychainService.loadTwitchChannelID() == "channel")
    }

    @Test("Empty field in full Twitch grant throws error")
    func testEmptyTwitchGrantFieldThrows() {
        #expect(throws: KeychainService.KeychainError.self) {
            try KeychainService.saveTwitchCredentialGrant(.init(accessToken: ""))
        }
    }

    // MARK: - Special Characters Tests

    @Test("Handle special characters in saved values")
    func testSpecialCharacters() async throws {
        let specialToken = "token_with_!@#$%^&*()_+-=[]{}|;:',.<>?/~`"

        try KeychainService.saveToken(specialToken)
        let loaded = KeychainService.loadToken()

        #expect(loaded == specialToken)

        try KeychainService.deleteToken()
    }

    @Test("Handle Unicode in saved values")
    func testUnicodeCharacters() async throws {
        let unicodeUsername = "testbot_🐺🎵"

        try KeychainService.saveTwitchCredentialGrant(
            .init(accessToken: "ACCESS", username: unicodeUsername)
        )
        let loaded = KeychainService.loadTwitchUsername()

        #expect(loaded == unicodeUsername)

        try KeychainService.deleteTwitchCredentialGrant()
    }

    // MARK: - Concurrent Access Tests

    @Test("Concurrent save and load operations are thread-safe")
    func testConcurrentAccess() async throws {
        let iterations = 50
        let group = DispatchGroup()
        let queue = DispatchQueue(label: "keychain.stress", attributes: .concurrent)
        let readResults = ThreadSafeBox<[String?]>(
            Array(repeating: nil, count: iterations))

        // These blocks run on GCD threads, outside this test's task tree, so the
        // suite's task-scoped backend does not reach them on its own. Rebinding
        // it keeps the stress on real threads rather than the cooperative pool.
        let box = KeychainService.backendBox

        // Seed with a known value first
        try KeychainService.saveToken("seed_token")

        // Concurrent writes and reads on real threads
        for i in 0..<iterations {
            group.enter()
            queue.async {
                let token = "concurrent_token_\(i)"
                KeychainService.$backendBox.withValue(box) {
                    try? KeychainService.saveToken(token)
                }
                group.leave()
            }

            group.enter()
            queue.async {
                let loaded = KeychainService.$backendBox.withValue(box) {
                    KeychainService.loadToken()
                }
                readResults.mutate { $0[i] = loaded }
                group.leave()
            }
        }

        await withCheckedContinuation { continuation in
            group.notify(queue: .global()) { continuation.resume() }
        }

        // Validate: every read should have returned a non-nil, non-empty token
        // (since we seeded and continuously wrote valid tokens)
        for (index, result) in readResults.value.enumerated() {
            #expect(result != nil, "Read at index \(index) returned nil: possible corruption")
            if let value = result {
                #expect(!value.isEmpty, "Read at index \(index) returned empty string: possible corruption")
            }
        }

        // Final state: a valid token should be loadable
        let finalToken = KeychainService.loadToken()
        #expect(finalToken != nil, "Final read after concurrent stress should return a valid token")

        // Cleanup
        try KeychainService.deleteToken()
    }

    // MARK: - Error Handling Tests

    @Test("KeychainError has correct descriptions")
    func testKeychainErrorDescriptions() async throws {
        let saveError = KeychainService.KeychainError.saveFailed(-25300)
        #expect(saveError.errorDescription == "Failed to save token to Keychain (status: -25300)")

        let loadError = KeychainService.KeychainError.loadFailed(-25308)
        #expect(loadError.errorDescription == "Failed to load token from Keychain (status: -25308)")

        let deleteError = KeychainService.KeychainError.deleteFailed(-25308)
        #expect(deleteError.errorDescription == "Failed to delete token from Keychain (status: -25308)")

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
        try KeychainService.deleteTwitchCredentialGrant()
        try KeychainService.deleteTwitchCredentialGrant()
        // Should succeed silently
        #expect(true)
    }

    // MARK: - Overwrite Contract

    @Test("saveToken overwrites a pre-existing value")
    func testSaveTokenOverwritesExistingValue() async throws {
        // Seed a stale value, then overwrite via the public API. The upsert path
        // must replace it without throwing. (The SystemKeychainBackend's
        // duplicate-add race fallback performs a value-only update without
        // deleting the existing ACL/accessibility metadata. That Security-only
        // path is exercised in integration, not by the in-memory backend.)
        try KeychainService.saveToken("stale_token")
        #expect(KeychainService.loadToken() == "stale_token")

        let fresh = "fresh_token_\(UUID().uuidString)"
        try KeychainService.saveToken(fresh)
        #expect(KeychainService.loadToken() == fresh)

        try KeychainService.deleteToken()
    }

    // MARK: - Factory Reset

    @Test("deleteAll removes every stored credential")
    func testDeleteAllRemovesEveryCredential() async throws {
        // Seed one of each credential the factory reset must wipe.
        try KeychainService.saveToken("ws_token")
        try KeychainService.saveControlToken("ws_control_token")
        try KeychainService.saveTwitchCredentialGrant(
            .init(
                accessToken: "twitch_oauth",
                refreshToken: "twitch_refresh",
                username: "wolf",
                userID: "12345",
                channelID: "67890"
            )
        )

        try KeychainService.deleteAll()

        #expect(KeychainService.loadToken() == nil)
        #expect(KeychainService.loadControlToken() == nil)
        #expect(KeychainService.loadTwitchToken() == nil)
        #expect(KeychainService.loadTwitchRefreshToken() == nil)
        #expect(KeychainService.loadTwitchUsername() == nil)
        #expect(KeychainService.loadTwitchBotUserID() == nil)
        #expect(KeychainService.loadTwitchChannelID() == nil)
    }

    @Test("deleteAll on an empty store succeeds silently")
    func testDeleteAllWhenEmpty() async throws {
        try KeychainService.deleteAll()
        #expect(KeychainService.loadToken() == nil)
        #expect(KeychainService.loadControlToken() == nil)
    }
}
