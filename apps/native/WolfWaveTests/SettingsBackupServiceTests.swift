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

    override func setUp() async throws {
        try await super.setUp()
        await SharedTestStateIsolation.acquireAsync()
        previousBackend = KeychainService.backend
        KeychainService.backend = InMemoryKeychainBackend()
    }

    override func tearDown() async throws {
        KeychainService.backend = previousBackend
        SharedTestStateIsolation.release()
        try await super.tearDown()
    }

    func testApplyBroadcastsCompleteResolvedOverlayConfiguration() async {
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
                keys.widgetPort: .int(9_123)
            ],
            integrations: .init(twitch: nil)
        )

        let service = SettingsBackupService(
            defaults: defaults,
            center: center,
            twitchChannelProvider: { nil },
            replaceCustomCommands: { _ in false },
            replaceSongRequestBlocklist: { _ in false }
        )
        _ = await service.apply(
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
            twitchChannelProvider: { "canonical_channel" }
        )

        let backup = try service.makeBackup(exportedAt: Date(timeIntervalSince1970: 0))

        XCTAssertEqual(backup.integrations.twitch?.channelName, "canonical_channel")
    }

    func testBackupRoundTripsPortableCollectionsThroughLiveOwners() async throws {
        let suiteName = "SettingsBackupCollections." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let importedCommands = [
            CustomCommand(trigger: "!hello", response: "Hi!")
        ]
        let importedBlocklist = [
            BlocklistItem(value: "Blocked Artist", type: .artist)
        ]
        let importedCommandsData = try JSONCoders.defaultEncoder.encode(importedCommands)
        let importedBlocklistData = try JSONCoders.camelCaseEncoder.encode(importedBlocklist)
        let expectedBlocklist = try JSONCoders.camelCase.decode(
            [BlocklistItem].self,
            from: importedBlocklistData
        )
        defaults.set(importedCommandsData, forKey: AppConstants.UserDefaults.customCommands)
        defaults.set(importedBlocklistData, forKey: AppConstants.UserDefaults.songRequestBlocklist)

        let exportService = SettingsBackupService(
            defaults: defaults,
            center: NotificationCenter(),
            twitchChannelProvider: { nil },
            replaceCustomCommands: { _ in false },
            replaceSongRequestBlocklist: { _ in false }
        )
        let encoded = try exportService.makeBackupData(exportedAt: Date(timeIntervalSince1970: 0))

        let staleCommands = [CustomCommand(trigger: "!stale", response: "Old")]
        let staleBlocklist = [BlocklistItem(value: "Stale Song", type: .song)]
        defaults.set(
            try JSONCoders.defaultEncoder.encode(staleCommands),
            forKey: AppConstants.UserDefaults.customCommands
        )
        defaults.set(
            try JSONCoders.camelCaseEncoder.encode(staleBlocklist),
            forKey: AppConstants.UserDefaults.songRequestBlocklist
        )
        let commandStore = CustomCommandStore(defaults: defaults)
        let blocklist = SongBlocklist(
            storage: UserDefaultsBlocklistStorage(defaults: defaults)
        )
        let importService = SettingsBackupService(
            defaults: defaults,
            center: NotificationCenter(),
            twitchChannelProvider: { nil },
            replaceCustomCommands: { data in
                commandStore.replaceFromImportedData(data)
            },
            replaceSongRequestBlocklist: { data in
                await blocklist.replaceFromImportedData(data)
            }
        )
        let backup = try importService.decode(encoded)

        let summary = await importService.apply(
            backup,
            choices: .init(reconnectTwitch: false)
        )

        XCTAssertEqual(summary.restoredCount, 2)
        XCTAssertEqual(summary.ignoredCount, 0)
        XCTAssertEqual(commandStore.commands, importedCommands)
        let liveBlocklist = await blocklist.allEntries
        XCTAssertEqual(liveBlocklist, expectedBlocklist)
        let persistedCommandsData = try XCTUnwrap(
            defaults.data(forKey: AppConstants.UserDefaults.customCommands)
        )
        XCTAssertEqual(
            try JSONCoders.default.decode(
                [CustomCommand].self,
                from: persistedCommandsData
            ),
            importedCommands
        )
        let persistedBlocklistData = try XCTUnwrap(
            defaults.data(forKey: AppConstants.UserDefaults.songRequestBlocklist)
        )
        XCTAssertEqual(
            try JSONCoders.camelCase.decode(
                [BlocklistItem].self,
                from: persistedBlocklistData
            ),
            expectedBlocklist
        )

        let expectedImportedBlockID = try XCTUnwrap(expectedBlocklist.first?.id)
        try await assertSubsequentMutationsRetainImportedState(
            commandStore: commandStore,
            blocklist: blocklist,
            defaults: defaults,
            importedCommands: importedCommands,
            importedBlockID: expectedImportedBlockID
        )
    }

    private func assertSubsequentMutationsRetainImportedState(
        commandStore: CustomCommandStore,
        blocklist: SongBlocklist,
        defaults: UserDefaults,
        importedCommands: [CustomCommand],
        importedBlockID: UUID
    ) async throws {
        let laterCommand = CustomCommand(trigger: "!later", response: "Still here")
        let laterBlockedSong = BlocklistItem(value: "Later Song", type: .song)
        commandStore.add(laterCommand)
        await blocklist.add(laterBlockedSong)

        let persistedCommandsData = try XCTUnwrap(
            defaults.data(forKey: AppConstants.UserDefaults.customCommands)
        )
        let persistedCommands = try JSONCoders.default.decode(
            [CustomCommand].self,
            from: persistedCommandsData
        )
        let persistedBlocklistData = try XCTUnwrap(
            defaults.data(forKey: AppConstants.UserDefaults.songRequestBlocklist)
        )
        let persistedBlocklist = try JSONCoders.camelCase.decode(
            [BlocklistItem].self,
            from: persistedBlocklistData
        )

        XCTAssertEqual(persistedCommands, importedCommands + [laterCommand])
        XCTAssertTrue(persistedBlocklist.contains { item in
            item.id == importedBlockID
        })
        XCTAssertTrue(persistedBlocklist.contains { item in
            item.id == laterBlockedSong.id
        })
    }

    func testMalformedPortableCollectionsPreserveLiveAndPersistedState() async throws {
        let suiteName = "SettingsBackupMalformedCollections." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let priorCommands = [CustomCommand(trigger: "!keep", response: "Kept")]
        let priorBlocklist = [BlocklistItem(value: "Keep Artist", type: .artist)]
        let priorCommandsData = try JSONCoders.defaultEncoder.encode(priorCommands)
        let priorBlocklistData = try JSONCoders.camelCaseEncoder.encode(priorBlocklist)
        let expectedBlocklist = try JSONCoders.camelCase.decode(
            [BlocklistItem].self,
            from: priorBlocklistData
        )
        defaults.set(priorCommandsData, forKey: AppConstants.UserDefaults.customCommands)
        defaults.set(priorBlocklistData, forKey: AppConstants.UserDefaults.songRequestBlocklist)
        let commandStore = CustomCommandStore(defaults: defaults)
        let blocklist = SongBlocklist(
            storage: UserDefaultsBlocklistStorage(defaults: defaults)
        )
        let customReplacementCalls = ThreadSafeBox(0)
        let blocklistReplacementCalls = ThreadSafeBox(0)
        let service = SettingsBackupService(
            defaults: defaults,
            center: NotificationCenter(),
            twitchChannelProvider: { nil },
            replaceCustomCommands: { data in
                customReplacementCalls.mutate { value in value += 1 }
                return commandStore.replaceFromImportedData(data)
            },
            replaceSongRequestBlocklist: { data in
                blocklistReplacementCalls.mutate { value in value += 1 }
                return await blocklist.replaceFromImportedData(data)
            }
        )
        let keys = AppConstants.UserDefaults.self
        let backup = SettingsBackup(
            format: SettingsBackup.currentFormat,
            schemaVersion: SettingsBackup.currentSchemaVersion,
            appVersion: "1.0.0",
            appBuild: "1",
            exportedAt: Date(timeIntervalSince1970: 0),
            settings: [
                keys.customCommands: .data(Data("not-json".utf8)),
                keys.songRequestBlocklist: .data(Data("{}".utf8))
            ],
            integrations: .init(twitch: nil)
        )

        let summary = await service.apply(
            backup,
            choices: .init(reconnectTwitch: false)
        )

        XCTAssertEqual(summary.restoredCount, 0)
        XCTAssertEqual(summary.ignoredCount, 2)
        XCTAssertEqual(customReplacementCalls.value, 0)
        XCTAssertEqual(blocklistReplacementCalls.value, 0)
        XCTAssertEqual(commandStore.commands, priorCommands)
        let liveBlocklist = await blocklist.allEntries
        XCTAssertEqual(liveBlocklist, expectedBlocklist)
        XCTAssertEqual(
            defaults.data(forKey: AppConstants.UserDefaults.customCommands),
            priorCommandsData
        )
        XCTAssertEqual(
            defaults.data(forKey: AppConstants.UserDefaults.songRequestBlocklist),
            priorBlocklistData
        )
    }

    func testApplyDisablesUnsafeSongRequestsBeforePortableOwnerSuspends() async throws {
        let suiteName = "SettingsBackupSongRequestSafety." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let blocklistData = try JSONCoders.camelCaseEncoder.encode([
            BlocklistItem(value: "Blocked Song", type: .song)
        ])
        let keys = AppConstants.UserDefaults.self
        let backup = SettingsBackup(
            format: SettingsBackup.currentFormat,
            schemaVersion: SettingsBackup.currentSchemaVersion,
            appVersion: "1.0.0",
            appBuild: "1",
            exportedAt: Date(timeIntervalSince1970: 0),
            settings: [
                keys.songRequestEnabled: .bool(true),
                keys.songRequestSetupComplete: .bool(false),
                keys.songRequestBlocklist: .data(blocklistData)
            ],
            integrations: .init(twitch: nil)
        )
        let gate = SettingsBackupAsyncGate()
        let service = SettingsBackupService(
            defaults: defaults,
            center: NotificationCenter(),
            twitchChannelProvider: { nil },
            replaceCustomCommands: { _ in false },
            replaceSongRequestBlocklist: { _ in
                await gate.suspend()
                return true
            }
        )

        let applyTask = Task {
            await service.apply(backup, choices: .init(reconnectTwitch: false))
        }
        let replacementSuspended = await waitUntil { await gate.suspended }

        XCTAssertTrue(replacementSuspended)
        XCTAssertFalse(defaults.bool(forKey: keys.songRequestEnabled))

        await gate.resume()
        _ = await applyTask.value
    }

    func testBackupFailsInsteadOfSilentlyOmittingChannelOnKeychainReadError() throws {
        let failingBackend = InspectableKeychainBackend()
        KeychainService.backend = failingBackend
        try KeychainService.saveTwitchCredentialGrant(
            .init(accessToken: "ACCESS", channelID: "canonical_channel")
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

    func testTwitchImportStagesPendingChannelWithoutMutatingCanonicalGrant() async throws {
        let suiteName = "SettingsBackupPendingChannel.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let original = KeychainService.TwitchCredentialGrant(
            accessToken: "ACCESS",
            refreshToken: "REFRESH",
            username: "wolf",
            userID: "123",
            channelID: "canonical_channel"
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
                twitch: .init(channelName: "imported_channel")
            )
        )

        let summary = await SettingsBackupService(
            defaults: defaults,
            center: NotificationCenter(),
            replaceCustomCommands: { _ in false },
            replaceSongRequestBlocklist: { _ in false }
        ).apply(backup, choices: .init(reconnectTwitch: true))

        XCTAssertTrue(summary.reconnectedTwitch)
        XCTAssertEqual(
            defaults.string(
                forKey: AppConstants.UserDefaults.twitchPendingImportedChannelName),
            "imported_channel"
        )
        XCTAssertNil(defaults.string(forKey: AppConstants.UserDefaults.twitchChannelName))
        XCTAssertTrue(defaults.bool(forKey: AppConstants.UserDefaults.twitchReauthNeeded))
        XCTAssertEqual(KeychainService.loadTwitchCredentialGrant(), original)
    }
    func testApplyEnactsSystemBackedPreferences() async throws {
        let suiteName = "SettingsBackupServiceTests.sideEffects.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
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
        let backup = SettingsBackup(
            format: SettingsBackup.currentFormat,
            schemaVersion: SettingsBackup.currentSchemaVersion,
            appVersion: "1.0.0",
            appBuild: "1",
            exportedAt: Date(timeIntervalSince1970: 0),
            settings: [
                keys.launchAtLogin: .bool(true),
                keys.appearancePreference: .string(AppConstants.Appearance.dark),
                keys.updateCheckEnabled: .bool(false),
                keys.updateChannel: .string(UpdateChannel.nightly.rawValue)
            ],
            integrations: .init(twitch: nil)
        )

        let summary = await SettingsBackupService(
            defaults: defaults,
            center: NotificationCenter(),
            replaceCustomCommands: { _ in false },
            replaceSongRequestBlocklist: { _ in false },
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

    func testApplyReconcilesRejectedLaunchAtLoginChange() async throws {
        let suiteName = "SettingsBackupServiceTests.loginFailure.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
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
        let backup = SettingsBackup(
            format: SettingsBackup.currentFormat,
            schemaVersion: SettingsBackup.currentSchemaVersion,
            appVersion: "1.0.0",
            appBuild: "1",
            exportedAt: Date(timeIntervalSince1970: 0),
            settings: [key: .bool(true)],
            integrations: .init(twitch: nil)
        )

        let summary = await SettingsBackupService(
            defaults: defaults,
            center: NotificationCenter(),
            replaceCustomCommands: { _ in false },
            replaceSongRequestBlocklist: { _ in false },
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
    func testApplyCountsPendingLaunchAtLoginAndWarnsAboutSystemApproval() async {
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

        let summary = await SettingsBackupService(
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

    func testSongRequestsAreNotPreviewedOrRestoredBeforeSetupCompletes() async {
        let suiteName = "SettingsBackupServiceTests.songRequestSetup.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            XCTFail("Could not create isolated UserDefaults suite")
            return
        }
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let keys = AppConstants.UserDefaults.self
        defaults.set(true, forKey: keys.songRequestEnabled)
        defaults.set(false, forKey: keys.songRequestSetupComplete)
        let backup = makeBackup(settings: [keys.songRequestEnabled: .bool(true)])
        let service = SettingsBackupService(defaults: defaults, center: NotificationCenter())

        XCTAssertEqual(service.restorableCount(backup), 0)
        let summary = await service.apply(backup, choices: .init())

        XCTAssertFalse(defaults.bool(forKey: keys.songRequestEnabled))
        XCTAssertEqual(summary.restoredCount, 0)
        XCTAssertEqual(summary.ignoredCount, 1)
        XCTAssertEqual(
            summary.warnings,
            ["Song Requests weren't restored because setup isn't complete on this Mac."]
        )
    }

    func testSongRequestsArePreviewedAndRestoredAfterSetupCompletes() async {
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
        let summary = await service.apply(backup, choices: .init())

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

private actor SettingsBackupAsyncGate {
    private(set) var suspended = false
    private var released = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func suspend() async {
        suspended = true
        guard !released else { return }
        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }

    func resume() {
        released = true
        waiters.forEach { continuation in continuation.resume() }
        waiters.removeAll()
    }
}
