//
//  SettingsBackupServiceTests.swift
//  WolfWave
//
//  Created by Nathanial Henniges on 2026-07-30.
//  Copyright © 2026 MrDemonWolf, Inc. All rights reserved.
//

import XCTest

@testable import WolfWave

@MainActor
final class SettingsBackupServiceTests: XCTestCase {

    private var previousBackend: KeychainBackend!

    override func setUp() {
        super.setUp()
        KeychainBackendTestIsolation.acquire()
        previousBackend = KeychainService.backend
        KeychainService.backend = InMemoryKeychainBackend()
    }

    override func tearDown() {
        KeychainService.backend = previousBackend
        KeychainBackendTestIsolation.release()
        super.tearDown()
    }

    func testApplyBroadcastsCompleteResolvedOverlayConfiguration() {
        let suiteName = "SettingsBackupServiceTests.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            XCTFail("Could not create isolated UserDefaults suite")
            return
        }
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let center = NotificationCenter()
        let received = ThreadSafeBox<Notification?>(nil)
        let observer = center.addObserver(
            forName: .websocketServerChanged,
            object: nil,
            queue: nil
        ) { notification in
            received.mutate { $0 = notification }
        }
        defer { center.removeObserver(observer) }

        let keys = AppConstants.UserDefaults.self
        let backup = SettingsBackup(
            format: SettingsBackup.currentFormat,
            schemaVersion: SettingsBackup.currentSchemaVersion,
            appVersion: "1.0.0",
            appBuild: "1",
            exportedAt: Date(timeIntervalSince1970: 0),
            settings: [
                keys.websocketEnabled: .bool(true),
                keys.widgetHTTPEnabled: .bool(true),
                keys.websocketServerPort: .int(0),
                keys.widgetPort: .int(9_123),
            ],
            integrations: .init(twitch: nil)
        )

        let service = SettingsBackupService(defaults: defaults, center: center)
        _ = service.apply(
            backup,
            choices: .init(reconnectTwitch: false)
        )

        XCTAssertEqual(received.value?.enabledFlag, true)
        XCTAssertEqual(received.value?.widgetHTTPEnabledFlag, true)
        XCTAssertEqual(received.value?.portValue, AppConstants.WebSocketServer.defaultPort)
        XCTAssertEqual(received.value?.widgetPortValue, 9_123)
    }

    func testBackupUsesCanonicalChannelProviderInsteadOfLegacyDefault() throws {
        let suiteName = "SettingsBackupCanonicalChannel.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set("stale-channel", forKey: AppConstants.UserDefaults.twitchChannelName)
        let service = SettingsBackupService(
            defaults: defaults,
            center: NotificationCenter(),
            twitchChannelProvider: { "canonical-channel" }
        )

        let backup = try service.makeBackup(exportedAt: Date(timeIntervalSince1970: 0))

        XCTAssertEqual(backup.integrations.twitch?.channelName, "canonical-channel")
    }

    func testBackupFailsInsteadOfSilentlyOmittingChannelOnKeychainReadError() throws {
        let failingBackend = InspectableKeychainBackend()
        KeychainService.backend = failingBackend
        try KeychainService.saveTwitchCredentialGrant(
            .init(accessToken: "ACCESS", channelID: "canonical-channel")
        )
        failingBackend.failNextLoad(
            for: KeychainService.twitchCredentialGrantAccount
        )

        XCTAssertThrowsError(try SettingsBackupService().makeBackup())
        XCTAssertNotNil(
            failingBackend.rawValue(
                account: KeychainService.twitchCredentialGrantAccount)
        )
    }

    func testTwitchImportStagesPendingChannelWithoutMutatingCanonicalGrant() throws {
        let suiteName = "SettingsBackupPendingChannel.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let original = KeychainService.TwitchCredentialGrant(
            accessToken: "ACCESS",
            refreshToken: "REFRESH",
            username: "wolf",
            userID: "123",
            channelID: "canonical-channel"
        )
        try KeychainService.saveTwitchCredentialGrant(original)
        defaults.set("legacy-stale", forKey: AppConstants.UserDefaults.twitchChannelName)
        let backup = SettingsBackup(
            format: SettingsBackup.currentFormat,
            schemaVersion: SettingsBackup.currentSchemaVersion,
            appVersion: "1.0.0",
            appBuild: "1",
            exportedAt: Date(timeIntervalSince1970: 0),
            settings: [:],
            integrations: .init(
                twitch: .init(channelName: "imported-channel")
            )
        )

        let summary = SettingsBackupService(
            defaults: defaults,
            center: NotificationCenter()
        ).apply(backup, choices: .init(reconnectTwitch: true))

        XCTAssertTrue(summary.reconnectedTwitch)
        XCTAssertEqual(
            defaults.string(
                forKey: AppConstants.UserDefaults.twitchPendingImportedChannelName),
            "imported-channel"
        )
        XCTAssertNil(defaults.string(forKey: AppConstants.UserDefaults.twitchChannelName))
        XCTAssertTrue(defaults.bool(forKey: AppConstants.UserDefaults.twitchReauthNeeded))
        XCTAssertEqual(KeychainService.loadTwitchCredentialGrant(), original)
    }
}
