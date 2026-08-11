//
//  ClearQueueCommand.swift
//  WolfWave
//
//  Created by Nathanial Henniges on 2026-04-15.
//  Copyright © 2026 MrDemonWolf, Inc. All rights reserved.
//

import Foundation

/// Handles `!clearqueue` / `!cq`. Clears all song requests (mod/broadcaster only).
final class ClearQueueCommand: ServiceBoundCommand {
    // MARK: - BotCommand

    /// Chat triggers that invoke this command.
    var triggers: [String] { ["!clearqueue", "!cq"] }

    /// Human-readable description shown in the `!commands` listing.
    var description: String { "Clear all song requests (mod/broadcaster only)" }

    /// Channel-wide cooldown between invocations, in seconds.
    var globalCooldown: TimeInterval { 5.0 }

    /// Per-user cooldown between invocations, in seconds.
    var userCooldown: TimeInterval { 5.0 }

    /// UserDefaults key controlling whether the command is enabled.
    var enabledKey: String? { AppConstants.UserDefaults.clearQueueCommandEnabled }

    /// UserDefaults key holding custom trigger aliases.
    var aliasesKey: String? { AppConstants.UserDefaults.clearQueueCommandAliases }

    // MARK: - Properties

    /// Provides the active `SongRequestService`. Late-bound to break the
    /// AppDelegate ↔ command dependency cycle at startup.
    var songRequestService: (() -> SongRequestService?)?

    // MARK: - AsyncBotCommand

    /// Clears every entry in the song request queue.
    ///
    /// - Parameters:
    ///   - message: Raw chat message (unused).
    ///   - context: Sender context; must be mod or broadcaster.
    ///   - Returns: The queue result, or nil when unauthorized.
    func execute(message: String, context: BotCommandContext) async -> String? {
        guard !Task.isCancelled else { return nil }
        guard let service = requirePrivilegedService(context: context) else { return nil }

        guard !Task.isCancelled else { return nil }
        let count = await service.clearQueue()
        guard !Task.isCancelled else { return nil }
        if count > 0 {
            return "Queue cleared (\(count) \(count == 1 ? "song" : "songs") removed)"
        }
        return "Queue is already empty."
    }
}
