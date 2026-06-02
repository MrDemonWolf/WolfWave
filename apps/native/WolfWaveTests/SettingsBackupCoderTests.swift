//
//  SettingsBackupCoderTests.swift
//  WolfWaveTests
//
//  Copyright © 2026 MrDemonWolf, Inc. All rights reserved.
//

import Foundation
import Testing
@testable import WolfWave

/// Pure-logic coverage for the settings backup encode/decode/apply core.
/// No UserDefaults, Keychain, file system, or network is touched.
struct SettingsBackupCoderTests {

    private let coder = SettingsBackupCoder()
    private var exportable: [String] { AppConstants.UserDefaults.exportableKeys }

    private func makeBackup(
        snapshot: [String: Any],
        twitchChannelName: String? = nil
    ) -> SettingsBackup {
        coder.makeBackup(
            snapshot: snapshot,
            exportableKeys: exportable,
            twitchChannelName: twitchChannelName,
            appVersion: "1.0.0",
            appBuild: "1",
            exportedAt: Date(timeIntervalSince1970: 0)
        )
    }

    // MARK: - BackupValue typing

    @Test func backupValueClassifiesScalarTypes() {
        #expect(BackupValue.make(from: true) == .bool(true))
        #expect(BackupValue.make(from: false) == .bool(false))
        #expect(BackupValue.make(from: 8765) == .int(8765))
        #expect(BackupValue.make(from: 15.0) == .double(15.0))
        #expect(BackupValue.make(from: 30.5) == .double(30.5))
        #expect(BackupValue.make(from: "Neon") == .string("Neon"))
    }

    @Test func backupValueRejectsUnsupportedTypes() {
        #expect(BackupValue.make(from: Date()) == nil)
        #expect(BackupValue.make(from: [1, 2, 3]) == nil)
        #expect(BackupValue.make(from: Data([0x01])) == nil)
    }

    // MARK: - Round trip

    @Test func roundTripPreservesValueTypes() throws {
        let keys = AppConstants.UserDefaults.self
        let snapshot: [String: Any] = [
            keys.trackingEnabled: true,
            keys.websocketServerPort: 8765,
            keys.songCommandGlobalCooldown: 15.0,
            keys.widgetTheme: "Neon",
        ]
        let data = try coder.encode(makeBackup(snapshot: snapshot))
        let decoded = try coder.decode(data)

        #expect(decoded.settings[keys.trackingEnabled] == .bool(true))
        #expect(decoded.settings[keys.websocketServerPort] == .int(8765))
        #expect(decoded.settings[keys.songCommandGlobalCooldown] == .double(15.0))
        #expect(decoded.settings[keys.widgetTheme] == .string("Neon"))
        #expect(decoded.format == SettingsBackup.currentFormat)
        #expect(decoded.schemaVersion == SettingsBackup.currentSchemaVersion)
    }

    // MARK: - Export allow-list

    @Test func exportExcludesAccountAndRuntimeKeys() {
        let keys = AppConstants.UserDefaults.self
        var snapshot: [String: Any] = [keys.trackingEnabled: true]
        for key in keys.accountLinkedKeys { snapshot[key] = "sensitive" }
        for key in keys.runtimeStateKeys { snapshot[key] = "transient" }

        let backup = makeBackup(snapshot: snapshot, twitchChannelName: "mrdemonwolf")

        // Portable key survives.
        #expect(backup.settings[keys.trackingEnabled] == .bool(true))
        // No account or runtime key leaks into the payload.
        for key in keys.accountLinkedKeys { #expect(backup.settings[key] == nil) }
        for key in keys.runtimeStateKeys { #expect(backup.settings[key] == nil) }
        // The only account identity recorded is the public channel name.
        #expect(backup.integrations.twitch?.channelName == "mrdemonwolf")
    }

    @Test func exportSkipsUnsupportedValueTypes() {
        let keys = AppConstants.UserDefaults.self
        let backup = makeBackup(snapshot: [keys.trackingEnabled: Date()])
        #expect(backup.settings[keys.trackingEnabled] == nil)
    }

    @Test func exportOmitsTwitchWhenChannelEmpty() {
        let backup = makeBackup(snapshot: [:], twitchChannelName: "  ")
        #expect(backup.integrations.twitch == nil)
    }

    // MARK: - Decode validation

    @Test func decodeRejectsNonJSON() {
        let data = Data("definitely not json".utf8)
        #expect(throws: SettingsBackupCoder.BackupError.notReadable) {
            try coder.decode(data)
        }
    }

    @Test func decodeRejectsForeignFormat() throws {
        let json = """
        {"format":"com.example.other","schemaVersion":1,"appVersion":"1",\
        "appBuild":"1","exportedAt":"2026-01-01T00:00:00Z","settings":{},\
        "integrations":{}}
        """
        #expect(throws: SettingsBackupCoder.BackupError.notWolfWaveFile) {
            try coder.decode(Data(json.utf8))
        }
    }

    @Test func decodeRejectsNewerSchema() throws {
        let json = """
        {"format":"\(SettingsBackup.currentFormat)","schemaVersion":99,\
        "appVersion":"9","appBuild":"9","exportedAt":"2026-01-01T00:00:00Z",\
        "settings":{},"integrations":{}}
        """
        #expect(throws: SettingsBackupCoder.BackupError.unsupportedNewerSchema(99)) {
            try coder.decode(Data(json.utf8))
        }
    }

    @Test func decodeAcceptsCurrentSchemaRoundTrip() throws {
        let data = try coder.encode(makeBackup(snapshot: [:]))
        let decoded = try coder.decode(data)
        #expect(decoded.format == SettingsBackup.currentFormat)
    }

    // MARK: - Apply planning

    @Test func applyPlanRestoresPortableAndIgnoresOthers() {
        let keys = AppConstants.UserDefaults.self
        var backup = makeBackup(snapshot: [keys.trackingEnabled: true])
        // Sneak in a non-exportable account key and a since-removed unknown key.
        backup.settings[keys.twitchChannelName] = .string("mrdemonwolf")
        backup.settings["someRemovedLegacyKey"] = .bool(true)

        let plan = coder.makeApplyPlan(
            backup: backup,
            choices: SettingsBackupCoder.ImportChoices(reconnectTwitch: false),
            exportableKeys: exportable
        )

        #expect(plan.set[keys.trackingEnabled] == .bool(true))
        #expect(plan.set[keys.twitchChannelName] == nil)
        #expect(plan.set["someRemovedLegacyKey"] == nil)
        #expect(plan.ignoredKeyCount == 2)
    }

    @Test func applyPlanSkipsTwitchWhenNotOptedIn() {
        let backup = makeBackup(snapshot: [:], twitchChannelName: "mrdemonwolf")
        let plan = coder.makeApplyPlan(
            backup: backup,
            choices: SettingsBackupCoder.ImportChoices(reconnectTwitch: false),
            exportableKeys: exportable
        )
        #expect(plan.reconnectTwitch == false)
        #expect(plan.twitchChannelName == nil)
    }

    @Test func applyPlanReconnectsTwitchWhenOptedIn() {
        let backup = makeBackup(snapshot: [:], twitchChannelName: "mrdemonwolf")
        let plan = coder.makeApplyPlan(
            backup: backup,
            choices: SettingsBackupCoder.ImportChoices(reconnectTwitch: true),
            exportableKeys: exportable
        )
        #expect(plan.reconnectTwitch == true)
        #expect(plan.twitchChannelName == "mrdemonwolf")
    }

    @Test func applyPlanTwitchOptInIsNoOpWithoutTwitchInBackup() {
        let backup = makeBackup(snapshot: [:], twitchChannelName: nil)
        let plan = coder.makeApplyPlan(
            backup: backup,
            choices: SettingsBackupCoder.ImportChoices(reconnectTwitch: true),
            exportableKeys: exportable
        )
        #expect(plan.reconnectTwitch == false)
        #expect(plan.twitchChannelName == nil)
    }

    // MARK: - Summary

    @Test func restorableCountCountsOnlyExportableKeys() {
        let keys = AppConstants.UserDefaults.self
        var backup = makeBackup(snapshot: [keys.trackingEnabled: true, keys.widgetTheme: "Neon"])
        backup.settings["unknownKey"] = .bool(true)
        #expect(coder.restorableCount(backup: backup, exportableKeys: exportable) == 2)
    }
}
