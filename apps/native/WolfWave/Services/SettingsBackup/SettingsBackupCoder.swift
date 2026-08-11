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
    ///   - exportablePreferences: Portable keys and their value validation rules.
    ///   - twitchChannelName: Connected channel name, if any (non-secret).
    ///   - appVersion: Marketing version stamped into the file.
    ///   - appBuild: Build number stamped into the file.
    ///   - exportedAt: Creation timestamp.
    ///
    /// Keys outside `exportablePreferences`, unsupported value shapes, and
    /// values that fail their preference rule are silently skipped.
    func makeBackup(
        snapshot: [String: Any],
        exportablePreferences: [AppConstants.UserDefaults.ExportablePreference],
        twitchChannelName: String?,
        appVersion: String,
        appBuild: String,
        exportedAt: Date
    ) -> SettingsBackup {
        let schema = Dictionary(
            uniqueKeysWithValues: exportablePreferences.map { ($0.key, $0.rule) }
        )
        var settings: [String: BackupValue] = [:]
        for (key, raw) in snapshot {
            guard
                let rule = schema[key],
                let value = BackupValue.make(from: raw),
                isValueAllowed(value, by: rule)
            else { continue }
            settings[key] = value
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

    /// Whether a tagged backup value exactly matches a schema rule.
    ///
    /// This is the sole validator used for export, import preview, and apply.
    /// Hand-edited backups therefore cannot exploit type bridging in
    /// `UserDefaults` or install unknown raw values for a picker-backed enum.
    private func isValueAllowed(
        _ value: BackupValue,
        by rule: AppConstants.UserDefaults.ExportedValueRule
    ) -> Bool {
        switch (rule, value) {
        case (.bool, .bool):
            return true
        case (.int(let domain), .int(let integer)):
            switch domain {
            case .values(let values):
                return values.contains(integer)
            case .zeroOrRange(let range):
                return integer == 0 || range.contains(integer)
            }
        case (.double(let domain), .double(let number)):
            guard number.isFinite, domain.range.contains(number), domain.step > 0 else {
                return false
            }
            let stepCount = (number - domain.range.lowerBound) / domain.step
            return abs(stepCount - stepCount.rounded()) < 1e-9
        case (.string(let allowedValues), .string(let string)):
            return allowedValues?.contains(string) ?? true
        case (.stringList(let allowedValues), .string(let string)):
            let values = string
                .split(separator: ",", omittingEmptySubsequences: false)
                .map { $0.trimmingCharacters(in: .whitespaces) }
            return !values.isEmpty
                && values.allSatisfy { !$0.isEmpty && allowedValues.contains($0) }
        case (.data(let format), .data(let data)):
            switch format {
            case .customCommands:
                return (try? JSONCoders.default.decode([CustomCommand].self, from: data)) != nil
            }
        default:
            return false
        }
    }

    /// Resolves a backup plus the user's choices into an `ApplyPlan`.
    ///
    /// Merge semantics: only keys in `backup.settings` that are also in
    /// `exportablePreferences` are written. Account-linked and unknown keys are
    /// ignored, as are values rejected by the centralized validation schema.
    /// No key is ever removed, so an import never wipes unrelated settings.
    /// Twitch is restored only when `choices.reconnectTwitch` is set and the
    /// backup actually had a Twitch channel.
    func makeApplyPlan(
        backup: SettingsBackup,
        choices: ImportChoices,
        exportablePreferences: [AppConstants.UserDefaults.ExportablePreference]
    ) -> ApplyPlan {
        let schema = Dictionary(
            uniqueKeysWithValues: exportablePreferences.map { ($0.key, $0.rule) }
        )
        var set: [String: BackupValue] = [:]
        var ignored = 0
        for (key, value) in backup.settings {
            if let rule = schema[key], isValueAllowed(value, by: rule) {
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
    func restorableCount(
        backup: SettingsBackup,
        exportablePreferences: [AppConstants.UserDefaults.ExportablePreference]
    ) -> Int {
        makeApplyPlan(
            backup: backup,
            choices: ImportChoices(),
            exportablePreferences: exportablePreferences
        ).set.count
    }
}
