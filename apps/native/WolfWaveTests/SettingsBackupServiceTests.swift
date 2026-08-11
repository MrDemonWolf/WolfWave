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

    func testApplyEnactsSystemBackedPreferences() {
        let suiteName = "SettingsBackupServiceTests.sideEffects.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            XCTFail("Could not create isolated UserDefaults suite")
            return
        }
        defer { defaults.removePersistentDomain(forName: suiteName) }

        var launchAtLoginEnabled = false
        var launchRequests: [Bool] = []
        var appliedAppearances: [String] = []
        var appliedUpdates: [SettingsBackupService.UpdatePreferences] = []
        let sideEffects = SettingsBackupService.SideEffects(
            isLaunchAtLoginEnabled: { launchAtLoginEnabled },
            setLaunchAtLogin: { enabled in
                launchRequests.append(enabled)
                launchAtLoginEnabled = enabled
                return .success
            },
            applyAppearance: { appliedAppearances.append($0) },
            applyUpdatePreferences: { appliedUpdates.append($0) }
        )

        let keys = AppConstants.UserDefaults.self
        let backup = makeBackup(settings: [
            keys.launchAtLogin: .bool(true),
            keys.appearancePreference: .string(AppConstants.Appearance.dark),
            keys.updateCheckEnabled: .bool(false),
            keys.updateChannel: .string(UpdateChannel.nightly.rawValue),
        ])

        let summary = SettingsBackupService(
            defaults: defaults,
            center: NotificationCenter(),
            sideEffects: sideEffects
        ).apply(backup, choices: .init())

        XCTAssertEqual(launchRequests, [true])
        XCTAssertEqual(appliedAppearances, [AppConstants.Appearance.dark])
        XCTAssertEqual(
            appliedUpdates,
            [.init(automaticCheckEnabled: false, channel: .nightly)]
        )
        XCTAssertEqual(summary.restoredCount, 4)
        XCTAssertTrue(summary.warnings.isEmpty)
    }

    func testApplyReconcilesRejectedLaunchAtLoginChange() {
        let suiteName = "SettingsBackupServiceTests.loginFailure.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            XCTFail("Could not create isolated UserDefaults suite")
            return
        }
        defer { defaults.removePersistentDomain(forName: suiteName) }

        var launchRequests: [Bool] = []
        let sideEffects = SettingsBackupService.SideEffects(
            isLaunchAtLoginEnabled: { false },
            setLaunchAtLogin: { enabled in
                launchRequests.append(enabled)
                return .failure
            },
            applyAppearance: { _ in },
            applyUpdatePreferences: { _ in }
        )
        let key = AppConstants.UserDefaults.launchAtLogin
        let backup = makeBackup(settings: [key: .bool(true)])

        let summary = SettingsBackupService(
            defaults: defaults,
            center: NotificationCenter(),
            sideEffects: sideEffects
        ).apply(backup, choices: .init())

        XCTAssertEqual(launchRequests, [true])
        XCTAssertFalse(defaults.bool(forKey: key))
        XCTAssertEqual(summary.restoredCount, 0)
        XCTAssertEqual(
            summary.warnings,
            ["Launch at Login couldn't be restored and remains off."]
        )
    }

    func testApplyCountsPendingLaunchAtLoginAndWarnsAboutSystemApproval() {
        let suiteName = "SettingsBackupServiceTests.loginApproval.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            XCTFail("Could not create isolated UserDefaults suite")
            return
        }
        defer { defaults.removePersistentDomain(forName: suiteName) }

        var launchAtLoginEnabled = false
        let sideEffects = SettingsBackupService.SideEffects(
            isLaunchAtLoginEnabled: { launchAtLoginEnabled },
            setLaunchAtLogin: { enabled in
                launchAtLoginEnabled = enabled
                return .requiresApproval
            },
            applyAppearance: { _ in },
            applyUpdatePreferences: { _ in }
        )
        let key = AppConstants.UserDefaults.launchAtLogin
        let backup = makeBackup(settings: [key: .bool(true)])

        let summary = SettingsBackupService(
            defaults: defaults,
            center: NotificationCenter(),
            sideEffects: sideEffects
        ).apply(backup, choices: .init())

        XCTAssertTrue(defaults.bool(forKey: key))
        XCTAssertEqual(summary.restoredCount, 1)
        XCTAssertEqual(
            summary.warnings,
            ["Launch at Login requires approval in System Settings → General → Login Items."]
        )
    }

    func testSongRequestsAreNotPreviewedOrRestoredBeforeSetupCompletes() {
        let suiteName = "SettingsBackupServiceTests.songRequestSetup.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            XCTFail("Could not create isolated UserDefaults suite")
            return
        }
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let keys = AppConstants.UserDefaults.self
        // Model a corrupted pre-import state too: resolving this backup must
        // leave the unsupported master toggle safely off.
        defaults.set(true, forKey: keys.songRequestEnabled)
        defaults.set(false, forKey: keys.songRequestSetupComplete)
        let backup = makeBackup(settings: [keys.songRequestEnabled: .bool(true)])
        let service = SettingsBackupService(defaults: defaults, center: NotificationCenter())

        XCTAssertEqual(service.restorableCount(backup), 0)

        let summary = service.apply(backup, choices: .init())

        XCTAssertFalse(defaults.bool(forKey: keys.songRequestEnabled))
        XCTAssertEqual(summary.restoredCount, 0)
        XCTAssertEqual(summary.ignoredCount, 1)
        XCTAssertEqual(
            summary.warnings,
            ["Song Requests weren't restored because setup isn't complete on this Mac."]
        )
    }

    func testSongRequestsArePreviewedAndRestoredAfterSetupCompletes() {
        let suiteName = "SettingsBackupServiceTests.songRequestReady.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            XCTFail("Could not create isolated UserDefaults suite")
            return
        }
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let keys = AppConstants.UserDefaults.self
        defaults.set(true, forKey: keys.songRequestSetupComplete)
        let backup = makeBackup(settings: [keys.songRequestEnabled: .bool(true)])
        let service = SettingsBackupService(defaults: defaults, center: NotificationCenter())

        XCTAssertEqual(service.restorableCount(backup), 1)

        let summary = service.apply(backup, choices: .init())

        XCTAssertTrue(defaults.bool(forKey: keys.songRequestEnabled))
        XCTAssertEqual(summary.restoredCount, 1)
        XCTAssertTrue(summary.warnings.isEmpty)
    }

    private func makeBackup(settings: [String: BackupValue]) -> SettingsBackup {
        SettingsBackup(
            format: SettingsBackup.currentFormat,
            schemaVersion: SettingsBackup.currentSchemaVersion,
            appVersion: "1.0.0",
            appBuild: "1",
            exportedAt: Date(timeIntervalSince1970: 0),
            settings: settings,
            integrations: .init(twitch: nil)
        )
    }
}
