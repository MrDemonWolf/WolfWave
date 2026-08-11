//
//  SettingsBackupCoder.swift
//  WolfWave
//
//  Created by Nathanial Henniges on 2026-06-02.
//  Copyright © 2026 MrDemonWolf, Inc. All rights reserved.
//

import Foundation

/// Pure, dependency-free core of the settings backup feature.
///
/// Everything here is testable without touching UserDefaults, Keychain, the file
/// system, or the network. Callers pass in a plain `[String: Any]` snapshot and
/// receive a `SettingsBackup`, or pass a decoded backup plus the user's import
/// choices and receive an `ApplyPlan` describing exactly what to write. The
/// `@MainActor` `SettingsBackupService` adapter does the impure work around it.
nonisolated struct SettingsBackupCoder {

    // MARK: - Errors

    /// Why an import file could not be used.
    enum BackupError: Error, Equatable {
        /// The bytes were not valid JSON / not a readable backup object.
        case notReadable
        /// Valid JSON, but not a WolfWave settings backup (wrong `format`).
        case notWolfWaveFile
        /// A backup written by a newer WolfWave with an unsupported schema.
        case unsupportedNewerSchema(Int)
    }

    // MARK: - Import Choices & Plan

    /// The user's per-integration decisions from the import review sheet.
    struct ImportChoices: Equatable {
        /// Restore the Twitch channel and prompt a re-sign-in on import.
        var reconnectTwitch: Bool

        init(reconnectTwitch: Bool = false) {
            self.reconnectTwitch = reconnectTwitch
        }
    }

    /// A fully resolved description of what an import will change. The adapter
    /// applies this; it performs no I/O itself, so it is unit-testable.
    struct ApplyPlan: Equatable {
        /// Portable preference writes (key -> value).
        var set: [String: BackupValue]
        /// Whether to restore Twitch identity and trigger re-auth.
        var reconnectTwitch: Bool
        /// Twitch channel name to restore, when reconnecting.
        var twitchChannelName: String?
        /// Count of backup keys ignored because they are non-exportable, unknown,
        /// or fail validation. Surfaced for transparency, never applied.
        var ignoredKeyCount: Int
    }

    // MARK: - Encode / Decode

    private var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    // Shares the app-wide ISO-8601 decoder instead of allocating a fresh one
    // with the same config on every access.
    private var decoder: JSONDecoder { JSONCoders.camelCase }

    /// Builds a backup from a UserDefaults snapshot.
    ///
    /// - Parameters:
    ///   - snapshot: Raw `key -> value` pairs (typically from UserDefaults).
    ///   - exportableKeys: The allow-list of keys permitted in a backup.
    ///   - twitchChannelName: Connected channel name, if any (non-secret).
    ///   - appVersion: Marketing version stamped into the file.
    ///   - appBuild: Build number stamped into the file.
    ///   - exportedAt: Creation timestamp.
    ///
    /// Keys outside `exportableKeys`, and values of unsupported types, are
    /// silently skipped. A backup can only ever contain portable scalars.
    func makeBackup(
        snapshot: [String: Any],
        exportableKeys: [String],
        twitchChannelName: String?,
        appVersion: String,
        appBuild: String,
        exportedAt: Date
    ) -> SettingsBackup {
        let allow = Set(exportableKeys)
        var settings: [String: BackupValue] = [:]
        for (key, raw) in snapshot where allow.contains(key) {
            if let value = BackupValue.make(from: raw) {
                settings[key] = value
            }
        }

        let twitch = twitchChannelName
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .flatMap { $0.isEmpty ? nil : SettingsBackup.Integrations.Twitch(channelName: $0) }

        return SettingsBackup(
            format: SettingsBackup.currentFormat,
            schemaVersion: SettingsBackup.currentSchemaVersion,
            appVersion: appVersion,
            appBuild: appBuild,
            exportedAt: exportedAt,
            settings: settings,
            integrations: SettingsBackup.Integrations(twitch: twitch)
        )
    }

    /// Serializes a backup to pretty-printed JSON `Data`.
    func encode(_ backup: SettingsBackup) throws -> Data {
        try encoder.encode(backup)
    }

    /// Decodes and validates backup `Data`.
    ///
    /// Order of checks: readable JSON object -> WolfWave `format` -> supported
    /// schema -> full decode. This lets callers show a precise message
    /// ("not a WolfWave file" vs "made by a newer version" vs "unreadable").
    func decode(_ data: Data) throws -> SettingsBackup {
        // Cheap header probe first so format/version errors beat a generic
        // decode failure when optional fields are missing or reordered.
        struct Header: Decodable {
            var format: String
            var schemaVersion: Int
        }
        guard let header = try? decoder.decode(Header.self, from: data) else {
            throw BackupError.notReadable
        }
        guard header.format == SettingsBackup.currentFormat else {
            throw BackupError.notWolfWaveFile
        }
        guard header.schemaVersion <= SettingsBackup.currentSchemaVersion else {
            throw BackupError.unsupportedNewerSchema(header.schemaVersion)
        }
        do {
            return try decoder.decode(SettingsBackup.self, from: data)
        } catch {
            throw BackupError.notReadable
        }
    }

    // MARK: - Apply Planning

    /// Integer bounds for preferences whose consumers require a constrained
    /// value. Keeping the rules in one table ensures import preview and apply
    /// make the same decision for hand-edited backups.
    private static let integerBounds: [String: ClosedRange<Int>] = [
        // Zero means "use the default port"; positive values must fit UInt16.
        AppConstants.UserDefaults.websocketServerPort: 0...Int(UInt16.max),
        AppConstants.UserDefaults.widgetPort: 0...Int(UInt16.max),
        // These four pickers expose 1...20. Larger values can overflow when
        // several role contributions are stacked.
        AppConstants.UserDefaults.songRequestPerUserLimit: 1...20,
        AppConstants.UserDefaults.songRequestLimitSubscriber: 1...20,
        AppConstants.UserDefaults.songRequestLimitVIP: 1...20,
        AppConstants.UserDefaults.songRequestLimitModerator: 1...20,
    ]

    /// Whether a backup value is safe to write for the given key.
    /// Keys with an integer rule must have the expected type and bounds;
    /// everything else passes through unchanged.
    private func isValueAllowed(_ value: BackupValue, forKey key: String) -> Bool {
        guard let bounds = Self.integerBounds[key] else { return true }
        guard case .int(let integer) = value else { return false }
        return bounds.contains(integer)
    }

    /// Resolves a backup plus the user's choices into an `ApplyPlan`.
    ///
    /// Merge semantics: only keys in `backup.settings` that are also in
    /// `exportableKeys` are written. Account-linked and unknown keys are ignored,
    /// as are values rejected by the centralized key validation rules.
    /// No key is ever removed, so an import never wipes unrelated settings.
    /// Twitch is restored only when `choices.reconnectTwitch` is set and the
    /// backup actually had a Twitch channel.
    func makeApplyPlan(
        backup: SettingsBackup,
        choices: ImportChoices,
        exportableKeys: [String]
    ) -> ApplyPlan {
        let allow = Set(exportableKeys)
        var set: [String: BackupValue] = [:]
        var ignored = 0
        for (key, value) in backup.settings {
            if allow.contains(key), isValueAllowed(value, forKey: key) {
                set[key] = value
            } else {
                ignored += 1
            }
        }

        var reconnectTwitch = false
        var twitchChannelName: String?
        if choices.reconnectTwitch, let twitch = backup.integrations.twitch {
            reconnectTwitch = true
            twitchChannelName = twitch.channelName
        }

        return ApplyPlan(
            set: set,
            reconnectTwitch: reconnectTwitch,
            twitchChannelName: twitchChannelName,
            ignoredKeyCount: ignored
        )
    }

    /// How many portable preferences a backup would restore (for the import
    /// review summary). Uses the same validation as apply so the preview can
    /// never promise a preference that import will reject.
    func restorableCount(backup: SettingsBackup, exportableKeys: [String]) -> Int {
        makeApplyPlan(
            backup: backup,
            choices: ImportChoices(),
            exportableKeys: exportableKeys
        ).set.count
    }
}
