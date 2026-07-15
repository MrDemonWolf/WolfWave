//
//  BotCommand.swift
//  WolfWave
//
//  Created by Nathanial Henniges on 2026-01-08.
//  Copyright © 2026 MrDemonWolf, Inc. All rights reserved.
//

import Foundation

/// Protocol for Twitch bot command implementations.
///
/// Implementations must be thread-safe and validate input.
/// Maximum message response is 500 characters (enforced at dispatcher level).
protocol BotCommand {
    /// The command triggers that activate this command (e.g., ["!song", "!currentsong"]).
    /// Triggers are case-insensitive.
    var triggers: [String] { get }

    /// Description of what the command does.
    var description: String { get }

    /// Global cooldown in seconds between any uses of this command (0 = disabled).
    var globalCooldown: TimeInterval { get }

    /// Per-user cooldown in seconds between uses by the same user (0 = disabled).
    var userCooldown: TimeInterval { get }

    /// UserDefaults key for the global cooldown override. nil = use `globalCooldown` default.
    var globalCooldownKey: String? { get }

    /// UserDefaults key for the per-user cooldown override. nil = use `userCooldown` default.
    var userCooldownKey: String? { get }

    /// UserDefaults key controlling whether this command is enabled. nil = always enabled.
    var enabledKey: String? { get }

    /// UserDefaults key storing custom alias triggers (comma-separated). nil = no custom aliases.
    var aliasesKey: String? { get }

    /// Every trigger this command answers to: base triggers plus any aliases.
    /// A protocol requirement (not just an extension) so commands that carry
    /// their aliases inline (e.g. ``CustomBotCommand``) can override the default
    /// `UserDefaults`-backed implementation.
    var allTriggers: [String] { get }

    /// Whether `context` is permitted to run this command. Checked by the
    /// dispatcher before recording the cooldown, so a denied viewer can't warm
    /// the shared cooldown. Default: allow everyone.
    func isAllowed(context: BotCommandContext) -> Bool

    /// Execute the command and return the response message.
    /// Keep response time under 100ms for responsive chat experience.
    func execute(message: String) -> String?
}

// MARK: - Default Cooldown Values

extension BotCommand {
    /// Default global cooldown: 15 seconds between any uses.
    var globalCooldown: TimeInterval { 15.0 }

    /// Default per-user cooldown: 15 seconds between uses by the same user.
    var userCooldown: TimeInterval { 15.0 }

    /// Default: no UserDefaults override.
    var globalCooldownKey: String? { nil }

    /// Default: no UserDefaults override.
    var userCooldownKey: String? { nil }
}

// MARK: - Enable/Disable & Aliases

extension BotCommand {
    /// Default: no enable/disable key (always enabled).
    var enabledKey: String? { nil }

    /// Default: no custom aliases.
    var aliasesKey: String? { nil }

    /// Combined triggers: original triggers + any user-configured aliases from UserDefaults.
    var allTriggers: [String] {
        var result = triggers
        if let key = aliasesKey,
           let custom = Foundation.UserDefaults.standard.string(forKey: key) {
            let aliases = custom.split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
                .filter { !$0.isEmpty }
                .map { $0.hasPrefix("!") ? $0 : "!\($0)" }
            result += aliases
        }
        return result
    }

    /// Default: no permission gate; every viewer may run the command.
    func isAllowed(context: BotCommandContext) -> Bool { true }

    /// Whether this command is currently enabled.
    var isCommandEnabled: Bool {
        guard let key = enabledKey else { return true }
        // Use object(forKey:) to distinguish "not set" (default true) from explicit false
        let defaults = Foundation.UserDefaults.standard
        if defaults.object(forKey: key) == nil { return true }
        return defaults.bool(forKey: key)
    }
}

// MARK: - ServiceBoundCommand

/// Mixin for async commands that require a `SongRequestService` and mod/broadcaster privilege.
///
/// Conforming types get `requirePrivilegedService(context:)` for free, eliminating
/// the repeated guard/service-binding boilerplate in SkipCommand, ClearQueueCommand, etc.
protocol ServiceBoundCommand: AsyncBotCommand {
    var songRequestService: (() -> SongRequestService?)? { get set }
}

extension ServiceBoundCommand {
    /// Returns the service only if the context is privileged (mod or broadcaster).
    /// Silently returns `nil` for non-privileged users, matching the established pattern.
    func requirePrivilegedService(context: BotCommandContext) -> SongRequestService? {
        guard context.isPrivileged else { return nil }
        return songRequestService?()
    }
}
