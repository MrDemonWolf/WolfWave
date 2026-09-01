//
//  SettingsSyncServiceTests.swift
//  WolfWave
//
//  Created by Nathanial Henniges on 2026-09-01.
//  Copyright © 2026 MrDemonWolf, Inc. All rights reserved.
//

import XCTest

@testable import WolfWave

/// In-memory stand-in for `NSUbiquitousKeyValueStore`. Never touches iCloud.
private final class FakeSyncStore: SettingsSyncStore {
    var storage: [String: Data] = [:]
    var writes = 0
    let externalChangeNotificationName = Notification.Name("FakeSyncStore.changed")

    func data(forKey key: String) -> Data? { storage[key] }
    func set(_ data: Data?, forKey key: String) {
        writes += 1
        storage[key] = data
    }
    func synchronize() -> Bool { true }
}

@MainActor
final class SettingsSyncServiceTests: XCTestCase {

    private var previousBackend: KeychainBackend!
    private var suiteName = ""
    private var defaults: UserDefaults!
    private var center: NotificationCenter!
    private var store: FakeSyncStore!
    private var backup: SettingsBackupService!

    override func setUp() async throws {
        try await super.setUp()
        await SharedTestStateIsolation.acquireAsync()
        previousBackend = KeychainService.backend
        KeychainService.backend = InMemoryKeychainBackend()

        suiteName = "SettingsSyncServiceTests.\(UUID().uuidString)"
        defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        center = NotificationCenter()
        store = FakeSyncStore()
        backup = SettingsBackupService(
            defaults: defaults,
            center: center,
            twitchChannelProvider: { nil },
            replaceCustomCommands: { _ in false },
            replaceSongRequestBlocklist: { _ in false },
            sideEffects: SettingsBackupService.SideEffects(
                isLaunchAtLoginEnabled: { false },
                setLaunchAtLogin: { _ in .success },
                applyAppearance: { _ in },
                applyUpdatePreferences: { _ in }
            )
        )
    }

    override func tearDown() async throws {
        defaults.removePersistentDomain(forName: suiteName)
        KeychainService.backend = previousBackend
        SharedTestStateIsolation.release()
        try await super.tearDown()
    }

    private func makeService(debounce: Duration = .zero) -> SettingsSyncService {
        SettingsSyncService(
            store: store, backup: backup, defaults: defaults, center: center, debounce: debounce)
    }

    private func cloudPayload(exportedAt: Date, discordEnabled: Bool) throws -> Data {
        let payload = SettingsBackup(
            format: SettingsBackup.currentFormat,
            schemaVersion: SettingsBackup.currentSchemaVersion,
            appVersion: "1.0.0",
            appBuild: "1",
            exportedAt: exportedAt,
            settings: [AppConstants.UserDefaults.discordPresenceEnabled: .bool(discordEnabled)],
            integrations: .init(twitch: nil)
        )
        return try SettingsBackupCoder().encode(payload)
    }

    // MARK: Tests

    func testDisabledServiceNeverWrites() {
        let service = makeService()
        service.push()
        XCTAssertEqual(store.writes, 0)
    }

    func testPushWritesEncodedBackup() throws {
        defaults.set(true, forKey: AppConstants.UserDefaults.discordPresenceEnabled)
        let service = makeService()
        service.setEnabled(true)
        service.push(now: Date(timeIntervalSince1970: 100))

        let data = try XCTUnwrap(store.storage[SettingsSyncService.payloadKey])
        let decoded = try SettingsBackupCoder().decode(data)
        XCTAssertEqual(decoded.settings[AppConstants.UserDefaults.discordPresenceEnabled], .bool(true))
        XCTAssertEqual(
            defaults.double(forKey: AppConstants.UserDefaults.iCloudSettingsSyncLastAppliedAt), 100)
    }

    func testPushSkipsWhenNothingChanged() {
        let service = makeService()
        service.setEnabled(true)
        service.push(now: Date(timeIntervalSince1970: 100))
        let writes = store.writes
        service.push(now: Date(timeIntervalSince1970: 200))
        XCTAssertEqual(store.writes, writes)
    }

    func testPullAppliesNewerCloudPayload() async throws {
        store.storage[SettingsSyncService.payloadKey] = try cloudPayload(
            exportedAt: Date(timeIntervalSince1970: 500), discordEnabled: true)
        let service = makeService()

        let applied = await service.pull()

        XCTAssertTrue(applied)
        XCTAssertTrue(defaults.bool(forKey: AppConstants.UserDefaults.discordPresenceEnabled))
        XCTAssertEqual(
            defaults.double(forKey: AppConstants.UserDefaults.iCloudSettingsSyncLastAppliedAt), 500)
    }

    func testPullIgnoresOlderCloudPayload() async throws {
        defaults.set(1_000.0, forKey: AppConstants.UserDefaults.iCloudSettingsSyncLastAppliedAt)
        store.storage[SettingsSyncService.payloadKey] = try cloudPayload(
            exportedAt: Date(timeIntervalSince1970: 500), discordEnabled: true)
        let service = makeService()

        let applied = await service.pull()

        XCTAssertFalse(applied)
        XCTAssertFalse(defaults.bool(forKey: AppConstants.UserDefaults.discordPresenceEnabled))
    }

    func testOwnPushIsNotReappliedOnPull() async {
        let service = makeService()
        service.setEnabled(true)
        service.push(now: Date(timeIntervalSince1970: 100))
        let applied = await service.pull()
        XCTAssertFalse(applied)
    }

    func testLocalChangeSchedulesPush() async throws {
        let service = makeService()
        service.setEnabled(true)
        // Drain the start-up pull/push so the write counter is stable.
        await Task.yield()
        service.push(now: Date(timeIntervalSince1970: 100))
        let writes = store.writes

        defaults.set(true, forKey: AppConstants.UserDefaults.discordPresenceEnabled)
        center.post(name: UserDefaults.didChangeNotification, object: defaults)
        await service.pendingPush?.value

        XCTAssertEqual(store.writes, writes + 1)
    }

    func testExternalChangeTriggersPull() async throws {
        let service = makeService()
        service.setEnabled(true)
        store.storage[SettingsSyncService.payloadKey] = try cloudPayload(
            exportedAt: Date.distantFuture, discordEnabled: true)

        center.post(name: store.externalChangeNotificationName, object: store)
        // The observer hops through a Task; give it a few turns.
        for _ in 0..<20 where !defaults.bool(forKey: AppConstants.UserDefaults.discordPresenceEnabled) {
            try await Task.sleep(for: .milliseconds(10))
        }

        XCTAssertTrue(defaults.bool(forKey: AppConstants.UserDefaults.discordPresenceEnabled))
    }
}
