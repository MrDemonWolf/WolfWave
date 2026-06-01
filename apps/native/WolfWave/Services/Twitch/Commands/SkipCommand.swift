//
//  SkipCommand.swift
//  WolfWave
//
//  Created by Nathanial Henniges on 2026-04-15.
//  Copyright © 2026 MrDemonWolf, Inc. All rights reserved.
//

import Foundation

/// Handles `!skip` / `!next` — skips the current song request.
///
/// Restricted to moderators and the broadcaster. Replies with the next track
/// or a queue-empty notice.
final class SkipCommand: ServiceBoundCommand {
    // MARK: - BotCommand

    /// Chat triggers that invoke this command.
    var triggers: [String] { ["!skip", "!next"] }

    /// Human-readable description shown in the `!commands` listing.
    var description: String { "Skip the current song request (mod/broadcaster only)" }

    /// Channel-wide cooldown between invocations, in seconds.
    var globalCooldown: TimeInterval { 3.0 }

    /// Per-user cooldown between invocations, in seconds.
    var userCooldown: TimeInterval { 3.0 }

    /// UserDefaults key controlling whether the command is enabled.
    var enabledKey: String? { AppConstants.UserDefaults.skipCommandEnabled }

    /// UserDefaults key holding custom trigger aliases.
    var aliasesKey: String? { AppConstants.UserDefaults.skipCommandAliases }

    // MARK: - Properties

    /// Provides the active `SongRequestService`. Late-bound to break the
    /// AppDelegate ↔ command dependency cycle at startup.
    var songRequestService: (() -> SongRequestService?)?

    // MARK: - AsyncBotCommand

    /// Executes the skip action against the live song request service.
    ///
    /// - Parameters:
    ///   - message: Raw chat message (unused).
    ///   - context: Sender context; must be mod or broadcaster.
    ///   - reply: Closure invoked with the chat response.
    func execute(message: String, context: BotCommandContext, reply: @escaping (String) -> Void) {
        guard let service = requirePrivilegedService(context: context) else { return }

        Task {
            if let next = await service.skip() {
                reply("Skipped. Now playing: \"\(next.title)\" by \(next.artist) (requested by \(next.requesterUsername))")
            } else {
                reply("Skipped. Queue is now empty.")
            }
        }
    }
}
