//
//  MyQueueCommand.swift
//  wolfwave
//
//  Created by MrDemonWolf, Inc. on 4/8/26.
//

import Foundation

/// Handles `!myqueue` / `!mysongs` — shows the requester's songs in the queue.
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

    /// Looks up the sender's queued songs and replies with their positions.
    ///
    /// - Parameters:
    ///   - message: Raw chat message (unused).
    ///   - context: Sender context; `username` is matched against queue entries.
    ///   - reply: Closure invoked with the chat response.
    func execute(message: String, context: BotCommandContext, reply: @escaping (String) -> Void) {
        guard let queue = getQueue?() else { return }

        let positions = queue.positions(for: context.username)

        if positions.isEmpty {
            reply("You don't have any songs in the queue. Use !sr <song name> to request one!")
            return
        }

        let parts = positions.map { "#\($0.position) \"\($0.item.title)\" — \($0.item.artist)" }
        reply("Your requests: \(parts.joined(separator: ", "))")
    }
}
