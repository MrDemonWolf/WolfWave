//
//  MyQueueCommand.swift
//  WolfWave
//
//  Created by Nathanial Henniges on 2026-04-15.
//  Copyright © 2026 MrDemonWolf, Inc. All rights reserved.
//

import Foundation

/// Handles `!myqueue` / `!mysongs`: shows the requester's songs in the queue.
final class MyQueueCommand: AsyncBotCommand {
    // MARK: - BotCommand

    /// Chat triggers that invoke this command.
    var triggers: [String] { ["!myqueue", "!mysongs"] }

    /// Human-readable description shown in the `!commands` listing.
    var description: String { "Show your requested songs and positions in queue" }

    /// Channel-wide cooldown between invocations, in seconds.
    var globalCooldown: TimeInterval { 10.0 }

    /// Per-user cooldown between invocations, in seconds.
    var userCooldown: TimeInterval { 15.0 }

    /// UserDefaults key controlling whether the command is enabled.
    var enabledKey: String? { AppConstants.UserDefaults.myQueueCommandEnabled }

    /// UserDefaults key holding custom trigger aliases.
    var aliasesKey: String? { AppConstants.UserDefaults.myQueueCommandAliases }

    // MARK: - Properties

    /// Provides the live `SongRequestQueue`. Late-bound to break the
    /// AppDelegate ↔ command dependency cycle at startup.
    var getQueue: (() -> SongRequestQueue?)?

    // MARK: - AsyncBotCommand

    /// Looks up the sender's queued songs and returns their positions.
    ///
    /// - Parameters:
    ///   - message: Raw chat message (unused).
    ///   - context: Sender context; `username` is matched against queue entries.
    ///   - Returns: The formatted queue response, or nil when unavailable.
    func execute(message: String, context: BotCommandContext) async -> String? {
        guard let queue = getQueue?() else { return nil }

        let positions = queue.positions(for: context.username)
        guard !positions.isEmpty else {
            return "You don't have any songs in the queue. Use !sr <song name> to request one!"
        }

        let parts = positions.map { "#\($0.position) \"\($0.item.title)\" · \($0.item.artist)" }
        return "Your requests: \(parts.joined(separator: ", "))"
    }
}
