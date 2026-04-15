//
//  ClearQueueCommand.swift
//  wolfwave
//
//  Created by MrDemonWolf, Inc. on 4/8/26.
//

import Foundation

/// Handles `!clearqueue` / `!cq` — clears all song requests (mod/broadcaster only).
final class ClearQueueCommand: ServiceBoundCommand {
    // MARK: - BotCommand

    var triggers: [String] { ["!clearqueue", "!cq"] }

    var description: String { "Clear all song requests (mod/broadcaster only)" }

    var globalCooldown: TimeInterval { 5.0 }

    var userCooldown: TimeInterval { 5.0 }

    var enabledKey: String? { AppConstants.UserDefaults.clearQueueCommandEnabled }

    var aliasesKey: String? { AppConstants.UserDefaults.clearQueueCommandAliases }

    // MARK: - Properties

    /// Reference to the song request service.
    var songRequestService: (() -> SongRequestService?)?

    // MARK: - AsyncBotCommand

    func execute(message: String, context: BotCommandContext, reply: @escaping (String) -> Void) {
        guard let service = requirePrivilegedService(context: context) else { return }

        Task {
            let count = await service.clearQueue()
            if count > 0 {
                reply("Queue cleared (\(count) \(count == 1 ? "song" : "songs") removed)")
            } else {
                reply("Queue is already empty.")
            }
        }
    }
}
