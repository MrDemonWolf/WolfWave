//
//  CustomCommand.swift
//  WolfWave
//
//  Created by Nathanial Henniges on 2026-07-15.
//  Copyright © 2026 MrDemonWolf, Inc. All rights reserved.
//

import Foundation

// MARK: - CommandPermission

/// Who is allowed to run a custom command.
///
/// Levels are treated as a minimum bar: a broadcaster passes every gate, a
/// moderator passes everything below `broadcaster`, and so on. `subscriber` and
/// `vip` both grant to the badge holder plus anyone more privileged.
nonisolated enum CommandPermission: String, Codable, CaseIterable, Sendable, Identifiable {
    case everyone
    case subscriber
    case vip
    case moderator
    case broadcaster

    var id: String { rawValue }

    /// Short label for the settings picker.
    var label: String {
        switch self {
        case .everyone: return "Everyone"
        case .subscriber: return "Subscribers"
        case .vip: return "VIPs"
        case .moderator: return "Moderators"
        case .broadcaster: return "Broadcaster only"
        }
    }

    /// Whether `context` clears this permission bar.
    func allows(_ context: BotCommandContext) -> Bool {
        switch self {
        case .everyone:
            return true
        case .subscriber:
            return context.isSubscriber || context.isVIP || context.isPrivileged
        case .vip:
            return context.isVIP || context.isPrivileged
        case .moderator:
            return context.isPrivileged
        case .broadcaster:
            return context.isBroadcaster
        }
    }
}

// MARK: - CustomCommand

/// A user-defined chat command: a trigger that replies with a fixed template,
/// optionally interpolating variables (`$user`, `$song`, `$1`, …).
///
/// Persisted as JSON in `UserDefaults` by ``CustomCommandStore`` and turned into
/// a runtime ``CustomBotCommand`` for the dispatcher.
nonisolated struct CustomCommand: Codable, Identifiable, Sendable, Equatable {

    /// Bounds shared by persisted-command validation and the settings controls.
    static let globalCooldownRange: ClosedRange<Double> = 0...30
    static let userCooldownRange: ClosedRange<Double> = 0...60
    static let cooldownStep: Double = 5

    /// Stable identity across edits (also the SwiftUI list id).
    var id: UUID

    /// Primary trigger, normalized to a leading `!` and lowercased (e.g. `!hug`).
    var trigger: String

    /// Reply template. Supports the variables listed in ``CustomCommandRenderer``.
    var response: String

    /// Comma-separated extra triggers, same syntax as the built-in command alias
    /// fields (`hug2, embrace`).
    var aliases: String

    /// Who may run the command.
    var permission: CommandPermission

    /// Whether the command responds at all.
    var enabled: Bool

    /// Channel-wide cooldown in seconds (mods/broadcaster bypass).
    var globalCooldown: Double

    /// Per-user cooldown in seconds (mods/broadcaster bypass).
    var userCooldown: Double

    init(
        id: UUID = UUID(),
        trigger: String = "",
        response: String = "",
        aliases: String = "",
        permission: CommandPermission = .everyone,
        enabled: Bool = true,
        globalCooldown: Double = 15,
        userCooldown: Double = 15
    ) {
        self.id = id
        self.trigger = trigger
        self.response = response
        self.aliases = aliases
        self.permission = permission
        self.enabled = enabled
        self.globalCooldown = globalCooldown
        self.userCooldown = userCooldown
    }

    /// Trigger normalized for matching: trimmed, lowercased, single leading `!`.
    /// Empty when the raw trigger has no usable characters.
    var normalizedTrigger: String {
        CustomCommand.normalizeTrigger(trigger)
    }

    /// Normalizes a raw trigger string to the stored/matched form.
    static func normalizeTrigger(_ raw: String) -> String {
        let stripped = raw.trimmingCharacters(in: .whitespaces)
            .lowercased()
            .drop { $0 == "!" }
        return stripped.isEmpty ? "" : "!\(stripped)"
    }

    /// Validates and canonicalizes a decoded persisted command collection.
    ///
    /// Imports use the same trigger normalization as matching and reject the
    /// ambiguous identities that the editor prevents: empty or overlapping
    /// triggers, duplicate UUIDs, and cooldowns the sliders cannot represent.
    static func normalizedForImport(_ commands: [CustomCommand]) -> [CustomCommand]? {
        normalized(commands, droppingConflictingAliases: false)
    }

    /// Canonicalizes commands saved before alias-conflict validation existed.
    /// Primary triggers win; only shadowed or empty legacy aliases are dropped.
    static func normalizedForExistingStorage(_ commands: [CustomCommand]) -> [CustomCommand]? {
        normalized(commands, droppingConflictingAliases: true)
    }

    private static func normalized(
        _ commands: [CustomCommand],
        droppingConflictingAliases: Bool
    ) -> [CustomCommand]? {
        var seenIDs: Set<UUID> = []
        var primaryTriggers: Set<String> = []
        for command in commands {
            let primary = normalizeTrigger(command.trigger)
            guard !primary.isEmpty,
                  seenIDs.insert(command.id).inserted,
                  primaryTriggers.insert(primary).inserted,
                  isValidCooldown(command.globalCooldown, in: globalCooldownRange),
                  isValidCooldown(command.userCooldown, in: userCooldownRange) else {
                return nil
            }
        }

        var seenAliases: Set<String> = []
        var result: [CustomCommand] = []
        result.reserveCapacity(commands.count)

        for var command in commands {
            let trigger = normalizeTrigger(command.trigger)
            let rawAliases = command.aliases.trimmingCharacters(in: .whitespaces).isEmpty
                ? []
                : command.aliases
                    .split(separator: ",", omittingEmptySubsequences: false)
                    .map { normalizeTrigger(String($0)) }

            var aliases: [String] = []
            for alias in rawAliases {
                let conflicts = alias.isEmpty
                    || primaryTriggers.contains(alias)
                    || !seenAliases.insert(alias).inserted
                if conflicts {
                    guard droppingConflictingAliases else { return nil }
                } else {
                    aliases.append(alias)
                }
            }

            command.trigger = trigger
            command.aliases = aliases
                .map { String($0.dropFirst()) }
                .joined(separator: ", ")
            result.append(command)
        }

        return result
    }

    private static func isValidCooldown(
        _ value: Double,
        in range: ClosedRange<Double>
    ) -> Bool {
        guard value.isFinite, range.contains(value), cooldownStep > 0 else {
            return false
        }
        let stepCount = (value - range.lowerBound) / cooldownStep
        return abs(stepCount - stepCount.rounded()) < 1e-9
    }
}

// MARK: - CustomCommandVariables

/// Live values the renderer can substitute that come from app state rather than
/// the chat message. Fetched fresh per invocation.
nonisolated struct CustomCommandVariables: Sendable {
    var currentSong: String
    var lastSong: String

    static let empty = CustomCommandVariables(currentSong: "", lastSong: "")
}

// MARK: - CustomCommandRenderer

/// Pure variable interpolation for custom command responses. No state, no I/O,
/// so it is trivially unit-testable.
///
/// Supported tokens:
/// - `$user` / `$sender`: the sender's display name
/// - `$touser`: the first argument with a leading `@` stripped, else the sender
/// - `$args`: every argument after the trigger, space-joined
/// - `$1` … `$9`: individual arguments (empty when absent)
/// - `$song` / `$lastsong`: current / previously played track
nonisolated enum CustomCommandRenderer {

    /// The whitespace-separated arguments following the trigger token.
    static func arguments(from message: String) -> [String] {
        let parts = message.split(whereSeparator: \.isWhitespace).map(String.init)
        return Array(parts.dropFirst())
    }

    /// Interpolates `template` and truncates to Twitch's 500-char limit.
    static func render(
        template: String,
        sender: String,
        args: [String],
        vars: CustomCommandVariables
    ) -> String {
        let touser: String = {
            guard let first = args.first else { return sender }
            return first.hasPrefix("@") ? String(first.dropFirst()) : first
        }()

        var out = template
        // Longest-first so no token is a prefix of another it would corrupt.
        let named: [(String, String)] = [
            ("$lastsong", vars.lastSong),
            ("$sender", sender),
            ("$touser", touser),
            ("$args", args.joined(separator: " ")),
            ("$song", vars.currentSong),
            ("$user", sender)
        ]
        for (token, value) in named {
            out = out.replacingOccurrences(of: token, with: value)
        }
        // Positional $1…$9 (absent args resolve to empty).
        for index in 1...9 {
            let value = index <= args.count ? args[index - 1] : ""
            out = out.replacingOccurrences(of: "$\(index)", with: value)
        }
        return out.truncatedForChat()
    }
}
