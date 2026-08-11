//
//  SettingsBackupCoderTests.swift
//  WolfWave
//
//  Created by Nathanial Henniges on 2026-06-02.
//  Copyright © 2026 MrDemonWolf, Inc. All rights reserved.
//

import Foundation
import Testing
@testable import WolfWave

/// Pure-logic coverage for the settings backup encode/decode/apply core.
/// No UserDefaults, Keychain, file system, or network is touched.
struct SettingsBackupCoderTests {

    private let coder = SettingsBackupCoder()
    private var exportable: [AppConstants.UserDefaults.ExportablePreference] {
        AppConstants.UserDefaults.exportablePreferences
    }

    private func makeBackup(
        snapshot: [String: Any],
        twitchChannelName: String? = nil
    ) -> SettingsBackup {
        coder.makeBackup(
            snapshot: snapshot,
            exportablePreferences: exportable,
            twitchChannelName: twitchChannelName,
            appVersion: "1.0.0",
            appBuild: "1",
            exportedAt: Date(timeIntervalSince1970: 0)
        )
    }

    // MARK: - BackupValue typing

    @Test func backupValueClassifiesSupportedTypes() {
        #expect(BackupValue.make(from: true) == .bool(true))
        #expect(BackupValue.make(from: false) == .bool(false))
        #expect(BackupValue.make(from: 8765) == .int(8765))
        #expect(BackupValue.make(from: 15.0) == .double(15.0))
        #expect(BackupValue.make(from: 30.5) == .double(30.5))
        #expect(BackupValue.make(from: "Neon") == .string("Neon"))
        #expect(BackupValue.make(from: Data([0x01, 0x02])) == .data(Data([0x01, 0x02])))
    }

    @Test func backupValueRejectsUnsupportedTypes() {
        #expect(BackupValue.make(from: Date()) == nil)
        #expect(BackupValue.make(from: [1, 2, 3]) == nil)
    }

    // MARK: - Round trip

    @MainActor
    @Test func roundTripPreservesValueTypes() throws {
        let keys = AppConstants.UserDefaults.self
        let customCommands = Data("[]".utf8)
        let blocklist = try JSONCoders.camelCaseEncoder.encode([
            BlocklistItem(value: "Blocked Song", type: .song)
        ])
        let snapshot: [String: Any] = [
            keys.trackingEnabled: true,
            keys.websocketServerPort: 8765,
            keys.songCommandGlobalCooldown: 15.0,
            keys.widgetTheme: "Neon",
            keys.customCommands: customCommands,
            keys.songRequestBlocklist: blocklist,
        ]
        let data = try coder.encode(makeBackup(snapshot: snapshot))
        let decoded = try coder.decode(data)

        #expect(decoded.settings[keys.trackingEnabled] == .bool(true))
        #expect(decoded.settings[keys.websocketServerPort] == .int(8765))
        #expect(decoded.settings[keys.songCommandGlobalCooldown] == .double(15.0))
        #expect(decoded.settings[keys.widgetTheme] == .string("Neon"))
        #expect(decoded.settings[keys.customCommands] == .data(customCommands))
        #expect(decoded.settings[keys.songRequestBlocklist] == .data(blocklist))
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

    @Test func exportUsesTheSameTypeAndEnumSchemaAsImport() {
        let keys = AppConstants.UserDefaults.self
        let commandData = Data("[]".utf8)
        let backup = makeBackup(snapshot: [
            keys.trackingEnabled: "true",
            keys.dockVisibility: "floating",
            keys.customCommands: commandData,
        ])

        #expect(backup.settings[keys.trackingEnabled] == nil)
        #expect(backup.settings[keys.dockVisibility] == nil)
        #expect(backup.settings[keys.customCommands] == .data(commandData))
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

    @Test func decodeAcceptsOlderSchemaBackup() throws {
        var backup = makeBackup(snapshot: [AppConstants.UserDefaults.trackingEnabled: true])
        backup.schemaVersion = 1

        let decoded = try coder.decode(coder.encode(backup))

        #expect(decoded.schemaVersion == 1)
        #expect(decoded.settings[AppConstants.UserDefaults.trackingEnabled] == .bool(true))
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
            exportablePreferences: exportable
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
            exportablePreferences: exportable
        )
        #expect(plan.reconnectTwitch == false)
        #expect(plan.twitchChannelName == nil)
    }

    @Test func applyPlanReconnectsTwitchWhenOptedIn() {
        let backup = makeBackup(snapshot: [:], twitchChannelName: "mrdemonwolf")
        let plan = coder.makeApplyPlan(
            backup: backup,
            choices: SettingsBackupCoder.ImportChoices(reconnectTwitch: true),
            exportablePreferences: exportable
        )
        #expect(plan.reconnectTwitch == true)
        #expect(plan.twitchChannelName == "mrdemonwolf")
    }

    @Test func applyPlanTwitchOptInIsNoOpWithoutTwitchInBackup() {
        let backup = makeBackup(snapshot: [:], twitchChannelName: nil)
        let plan = coder.makeApplyPlan(
            backup: backup,
            choices: SettingsBackupCoder.ImportChoices(reconnectTwitch: true),
            exportablePreferences: exportable
        )
        #expect(plan.reconnectTwitch == false)
        #expect(plan.twitchChannelName == nil)
    }

    @Test func applyPlanDropsOutOfRangePortValues() {
        let keys = AppConstants.UserDefaults.self
        var backup = makeBackup(snapshot: [:])
        // A hand-edited backup can carry ports UInt16 can't hold. They must
        // never reach UserDefaults, where a later UInt16 conversion would trap.
        backup.settings[keys.websocketServerPort] = .int(70000)
        backup.settings[keys.widgetPort] = .int(-5)

        let plan = coder.makeApplyPlan(
            backup: backup,
            choices: SettingsBackupCoder.ImportChoices(reconnectTwitch: false),
            exportablePreferences: exportable
        )

        #expect(plan.set[keys.websocketServerPort] == nil)
        #expect(plan.set[keys.widgetPort] == nil)
        #expect(plan.ignoredKeyCount == 2)
    }

    @Test func applyPlanDropsNonIntegerPortValues() {
        let keys = AppConstants.UserDefaults.self
        var backup = makeBackup(snapshot: [:])
        backup.settings[keys.widgetPort] = .string("8766")

        let plan = coder.makeApplyPlan(
            backup: backup,
            choices: SettingsBackupCoder.ImportChoices(reconnectTwitch: false),
            exportablePreferences: exportable
        )

        #expect(plan.set[keys.widgetPort] == nil)
        #expect(plan.ignoredKeyCount == 1)
    }

    @Test func applyPlanDropsReservedPortValues() {
        let keys = AppConstants.UserDefaults.self
        var backup = makeBackup(snapshot: [:])
        backup.settings[keys.websocketServerPort] = .int(80)

        let plan = coder.makeApplyPlan(
            backup: backup,
            choices: SettingsBackupCoder.ImportChoices(),
            exportablePreferences: exportable
        )

        #expect(plan.set[keys.websocketServerPort] == nil)
        #expect(plan.ignoredKeyCount == 1)
    }

    @Test func applyPlanKeepsInRangePortValues() {
        let keys = AppConstants.UserDefaults.self
        let backup = makeBackup(snapshot: [
            keys.websocketServerPort: 8765,
            keys.widgetPort: 0, // 0 = "use the default"; legal to restore
        ])

        let plan = coder.makeApplyPlan(
            backup: backup,
            choices: SettingsBackupCoder.ImportChoices(reconnectTwitch: false),
            exportablePreferences: exportable
        )

        #expect(plan.set[keys.websocketServerPort] == .int(8765))
        #expect(plan.set[keys.widgetPort] == .int(0))
        #expect(plan.ignoredKeyCount == 0)
    }

    @Test func applyPlanDropsOutOfRangeRoleLimits() {
        let keys = AppConstants.UserDefaults.self
        var backup = makeBackup(snapshot: [:])
        backup.settings[keys.songRequestPerUserLimit] = .int(0)
        backup.settings[keys.songRequestLimitSubscriber] = .int(-1)
        backup.settings[keys.songRequestLimitVIP] = .int(21)
        backup.settings[keys.songRequestLimitModerator] = .int(Int.max)

        let plan = coder.makeApplyPlan(
            backup: backup,
            choices: SettingsBackupCoder.ImportChoices(),
            exportablePreferences: exportable
        )

        #expect(plan.set.isEmpty)
        #expect(plan.ignoredKeyCount == 4)
    }

    @Test func applyPlanKeepsRoleLimitBoundaries() {
        let keys = AppConstants.UserDefaults.self
        let backup = makeBackup(snapshot: [
            keys.songRequestPerUserLimit: 1,
            keys.songRequestLimitSubscriber: 20,
            keys.songRequestLimitVIP: 1,
            keys.songRequestLimitModerator: 20,
        ])

        let plan = coder.makeApplyPlan(
            backup: backup,
            choices: SettingsBackupCoder.ImportChoices(),
            exportablePreferences: exportable
        )

        #expect(plan.set.count == 4)
        #expect(plan.ignoredKeyCount == 0)
    }

    @Test func applyPlanRejectsMismatchedTypesForEverySupportedShape() {
        let keys = AppConstants.UserDefaults.self
        var backup = makeBackup(snapshot: [:])
        backup.settings = [
            // Each value is representable in a backup, but has the wrong tagged
            // shape for this particular preference.
            keys.trackingEnabled: .string("true"),
            keys.widgetFontFamily: .bool(true),
            keys.websocketServerPort: .double(8_765),
            keys.songCommandGlobalCooldown: .int(15),
            keys.customCommands: .string("[]"),
        ]

        let plan = coder.makeApplyPlan(
            backup: backup,
            choices: SettingsBackupCoder.ImportChoices(),
            exportablePreferences: exportable
        )

        #expect(plan.set.isEmpty)
        #expect(plan.ignoredKeyCount == 5)
        #expect(
            coder.restorableCount(
                backup: backup,
                exportablePreferences: exportable
            ) == 0
        )
    }

    @Test func applyPlanRejectsUnknownPickerAndStringListValues() {
        let keys = AppConstants.UserDefaults.self
        var backup = makeBackup(snapshot: [:])
        backup.settings = [
            keys.dockVisibility: .string("floating"),
            keys.updateChannel: .string("beta"),
            keys.widgetTheme: .string("Synthwave"),
            keys.songRequestChatAudience: .string("friends"),
            keys.statsCommandParts: .string("plays,secretMetric"),
        ]

        let plan = coder.makeApplyPlan(
            backup: backup,
            choices: SettingsBackupCoder.ImportChoices(),
            exportablePreferences: exportable
        )

        #expect(plan.set.isEmpty)
        #expect(plan.ignoredKeyCount == 5)
        #expect(
            coder.restorableCount(
                backup: backup,
                exportablePreferences: exportable
            ) == 0
        )
    }

    @Test func applyPlanRejectsNumericValuesSettingsControlsCannotRepresent() {
        let keys = AppConstants.UserDefaults.self
        var backup = makeBackup(snapshot: [:])
        backup.settings = [
            keys.songRequestMaxQueueSize: .int(6),
            keys.songRequestPerUserLimit: .int(4),
            keys.songRequestChannelPointsCost: .int(200),
            keys.songRequestBitsMinimum: .int(2),
            keys.voteSkipMinVotes: .int(4),
            keys.voteSkipWindowSeconds: .int(45),
            keys.voteSkipSessionCooldown: .double(10),
            keys.voteSkipPollDuration: .int(15),
            keys.historyRetentionDays: .int(1),
            keys.songCommandGlobalCooldown: .double(7),
        ]

        let plan = coder.makeApplyPlan(
            backup: backup,
            choices: SettingsBackupCoder.ImportChoices(),
            exportablePreferences: exportable
        )

        #expect(plan.set.isEmpty)
        #expect(plan.ignoredKeyCount == 10)
    }

    @Test func applyPlanRejectsMalformedPortableData() {
        let keys = AppConstants.UserDefaults.self
        var backup = makeBackup(snapshot: [:])
        backup.settings[keys.customCommands] = .data(Data("not custom-command JSON".utf8))
        backup.settings[keys.songRequestBlocklist] = .data(Data("{}".utf8))

        let plan = coder.makeApplyPlan(
            backup: backup,
            choices: SettingsBackupCoder.ImportChoices(),
            exportablePreferences: exportable
        )

        #expect(plan.set[keys.customCommands] == nil)
        #expect(plan.set[keys.songRequestBlocklist] == nil)
        #expect(plan.ignoredKeyCount == 2)
        #expect(
            coder.restorableCount(
                backup: backup,
                exportablePreferences: exportable
            ) == 0
        )
    }

    // MARK: - Summary

    @Test func restorableCountCountsOnlyExportableKeys() {
        let keys = AppConstants.UserDefaults.self
        var backup = makeBackup(snapshot: [keys.trackingEnabled: true, keys.widgetTheme: "Neon"])
        backup.settings["unknownKey"] = .bool(true)
        #expect(coder.restorableCount(backup: backup, exportablePreferences: exportable) == 2)
    }

    @Test func restorableCountUsesTheSameValidationAsApply() {
        let keys = AppConstants.UserDefaults.self
        var backup = makeBackup(snapshot: [keys.trackingEnabled: true])
        backup.settings[keys.websocketServerPort] = .int(70_000)
        backup.settings[keys.songRequestLimitSubscriber] = .int(Int.max)
        backup.settings["unknownKey"] = .bool(true)

        let plan = coder.makeApplyPlan(
            backup: backup,
            choices: SettingsBackupCoder.ImportChoices(),
            exportablePreferences: exportable
        )

        #expect(plan.set.count == 1)
        #expect(
            coder.restorableCount(
                backup: backup,
                exportablePreferences: exportable
            ) == plan.set.count
        )
    }

    // MARK: - Decode rejects malformed input (surfaces an error, never crashes)

    @Test func decodeRejectsGarbageBytesAsNotReadable() {
        #expect(throws: SettingsBackupCoder.BackupError.notReadable) {
            try coder.decode(Data("not a backup at all".utf8))
        }
    }

    @Test func decodeRejectsWrongFormatAsNotWolfWaveFile() {
        let json = #"{"format":"com.example.other","schemaVersion":1}"#
        #expect(throws: SettingsBackupCoder.BackupError.notWolfWaveFile) {
            try coder.decode(Data(json.utf8))
        }
    }

    @Test func decodeRejectsNewerSchemaAsUnsupported() {
        let newer = SettingsBackup.currentSchemaVersion + 1
        let json = """
        {"format":"\(SettingsBackup.currentFormat)","schemaVersion":\(newer)}
        """
        #expect(throws: SettingsBackupCoder.BackupError.unsupportedNewerSchema(newer)) {
            try coder.decode(Data(json.utf8))
        }
    }

    @Test func decodeRejectsValidHeaderButTruncatedBody() {
        // Correct format + supported schema, but the required backup fields
        // (appVersion, settings, integrations, …) are missing: the full decode
        // fails and surfaces as `.notReadable` instead of crashing.
        let json = """
        {"format":"\(SettingsBackup.currentFormat)","schemaVersion":\(SettingsBackup.currentSchemaVersion)}
        """
        #expect(throws: SettingsBackupCoder.BackupError.notReadable) {
            try coder.decode(Data(json.utf8))
        }
    }

    // MARK: - Preference noun pluralization

    @MainActor
    @Test func preferenceNounPluralizesByCount() {
        #expect(SettingsBackupService.ApplySummary.preferenceNoun(0) == "preferences")
        #expect(SettingsBackupService.ApplySummary.preferenceNoun(1) == "preference")
        #expect(SettingsBackupService.ApplySummary.preferenceNoun(2) == "preferences")
        #expect(SettingsBackupService.ApplySummary.preferenceNoun(42) == "preferences")
    }
}
