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

    var triggers: [String] { ["!myqueue", "!mysongs"] }

    var description: String { "Show your requested songs and positions in queue" }

    var globalCooldown: TimeInterval { 10.0 }

    var userCooldown: TimeInterval { 15.0 }

    var enabledKey: String? { AppConstants.UserDefaults.myQueueCommandEnabled }

    var aliasesKey: String? { AppConstants.UserDefaults.myQueueCommandAliases }

    // MARK: - Properties

    /// Reference to the song request queue.
    var getQueue: (() -> SongRequestQueue?)?

    // MARK: - AsyncBotCommand

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
