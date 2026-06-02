//
//  SettingsBackup.swift
//  WolfWave
//
//  Copyright © 2026 MrDemonWolf, Inc. All rights reserved.
//

import Foundation

/// On-disk representation of an exported WolfWave settings backup.
///
/// A backup carries portable preferences only. It never contains secrets:
/// Twitch OAuth tokens, user/channel IDs, and the WebSocket auth token live in
/// Keychain and are not read by the backup pipeline at all. The lone piece of
/// account identity a backup records is the Twitch channel *name* (public, shown
/// as your channel URL) so the import flow can offer "Reconnect Twitch (#name)".
///
/// The file is plain JSON so a user can open and inspect it. `format` and
/// `schemaVersion` let the importer reject foreign or future files cleanly.
nonisolated struct SettingsBackup: Codable, Equatable {
    /// Marker identifying the file as a WolfWave settings backup.
    static let currentFormat = "com.mrdemonwolf.wolfwave.settings"

    /// Current backup schema version. Bump only on a breaking shape change.
    static let currentSchemaVersion = 1

    /// Always `SettingsBackup.currentFormat` for files this app writes.
    var format: String

    /// Schema version of this file. The importer refuses a value greater than
    /// `currentSchemaVersion` (made by a newer WolfWave).
    var schemaVersion: Int

    /// Marketing version of the app that produced the backup (e.g. "1.4.0").
    var appVersion: String

    /// Build number of the app that produced the backup.
    var appBuild: String

    /// When the backup was created.
    var exportedAt: Date

    /// Portable preference values keyed by `AppConstants.UserDefaults` key.
    /// Only `AppConstants.UserDefaults.exportableKeys` are present.
    var settings: [String: BackupValue]

    /// Non-secret detection metadata for accounts the backup had configured,
    /// driving the per-integration reconnect choices on import.
    var integrations: Integrations

    /// Accounts present in the source install, without any credentials.
    nonisolated struct Integrations: Codable, Equatable {
        /// Present when the source install had a Twitch channel configured.
        var twitch: Twitch?

        /// Twitch presence marker. Carries the public channel name only.
        nonisolated struct Twitch: Codable, Equatable {
            var channelName: String
        }
    }
}

/// A type-tagged preference value.
///
/// UserDefaults is untyped and bridges `Bool`/`Int`/`Double` through `NSNumber`,
/// which makes a bare JSON scalar ambiguous on the way back in (a stored `1.0`
/// can decode as `Int`). Tagging the type keeps an export → import round trip
/// lossless. `BackupValue.make(from:)` does the one tricky job — telling a
/// boolean `NSNumber` apart from a numeric one.
nonisolated enum BackupValue: Codable, Equatable {
    case bool(Bool)
    case int(Int)
    case double(Double)
    case string(String)

    private enum CodingKeys: String, CodingKey {
        case type
        case value
    }

    private enum ValueType: String, Codable {
        case bool, int, double, string
    }

    /// Builds a `BackupValue` from a raw UserDefaults value, returning `nil` for
    /// unsupported types (arrays, data, dates, etc., which backups don't carry).
    ///
    /// Telling a boolean `NSNumber` from a numeric one needs the CoreFoundation
    /// type id, since `boolNumber as? Int` and `intNumber as? Bool` both succeed
    /// through bridging. Telling an `Int` from a `Double` needs the Objective-C
    /// type encoding, not the value, because an integral double like `15.0`
    /// compares equal to `15` and would otherwise collapse to `.int`.
    static func make(from raw: Any) -> BackupValue? {
        if let number = raw as? NSNumber {
            if CFGetTypeID(number) == CFBooleanGetTypeID() {
                return .bool(number.boolValue)
            }
            switch String(cString: number.objCType) {
            case "f", "d":
                return .double(number.doubleValue)
            default:
                return .int(number.intValue)
            }
        }
        if let flag = raw as? Bool { return .bool(flag) }
        if let i = raw as? Int { return .int(i) }
        if let d = raw as? Double { return .double(d) }
        if let s = raw as? String { return .string(s) }
        return nil
    }

    /// The value as a Foundation object suitable for `UserDefaults.set(_:forKey:)`.
    var userDefaultsValue: Any {
        switch self {
        case .bool(let b): return b
        case .int(let i): return i
        case .double(let d): return d
        case .string(let s): return s
        }
    }

    // MARK: Codable

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(ValueType.self, forKey: .type)
        switch type {
        case .bool: self = .bool(try container.decode(Bool.self, forKey: .value))
        case .int: self = .int(try container.decode(Int.self, forKey: .value))
        case .double: self = .double(try container.decode(Double.self, forKey: .value))
        case .string: self = .string(try container.decode(String.self, forKey: .value))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .bool(let b):
            try container.encode(ValueType.bool, forKey: .type)
            try container.encode(b, forKey: .value)
        case .int(let i):
            try container.encode(ValueType.int, forKey: .type)
            try container.encode(i, forKey: .value)
        case .double(let d):
            try container.encode(ValueType.double, forKey: .type)
            try container.encode(d, forKey: .value)
        case .string(let s):
            try container.encode(ValueType.string, forKey: .type)
            try container.encode(s, forKey: .value)
        }
    }
}
