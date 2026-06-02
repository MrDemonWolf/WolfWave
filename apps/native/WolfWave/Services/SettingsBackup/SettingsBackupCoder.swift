//
//  SettingsBackupCoder.swift
//  WolfWave
//
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
        /// Count of backup keys ignored because they are not exportable
        /// (account/runtime/unknown). Surfaced for transparency, never applied.
        var ignoredKeyCount: Int
    }

    // MARK: - Encode / Decode

    private var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    private var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

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
    /// silently skipped — a backup can only ever contain portable scalars.
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

    /// Resolves a backup plus the user's choices into an `ApplyPlan`.
    ///
    /// Merge semantics: only keys in `backup.settings` that are also in
    /// `exportableKeys` are written. Account-linked and unknown keys are ignored.
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
            if allow.contains(key) {
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
    /// review summary). Counts only keys that are still exportable.
    func restorableCount(backup: SettingsBackup, exportableKeys: [String]) -> Int {
        let allow = Set(exportableKeys)
        return backup.settings.keys.reduce(into: 0) { count, key in
            if allow.contains(key) { count += 1 }
        }
    }
}
