//
//  SkipCommand.swift
//  wolfwave
//
//  Created by MrDemonWolf, Inc. on 4/8/26.
//

import Foundation

/// Handles `!skip` / `!next` — skips the current song request (mod/broadcaster only).
final class SkipCommand: ServiceBoundCommand {
    // MARK: - BotCommand

    var triggers: [String] { ["!skip", "!next"] }

    var description: String { "Skip the current song request (mod/broadcaster only)" }

    var globalCooldown: TimeInterval { 3.0 }

    var userCooldown: TimeInterval { 3.0 }

    var enabledKey: String? { AppConstants.UserDefaults.skipCommandEnabled }

    var aliasesKey: String? { AppConstants.UserDefaults.skipCommandAliases }

    // MARK: - Properties

    /// Reference to the song request service.
    var songRequestService: (() -> SongRequestService?)?

    // MARK: - AsyncBotCommand

    func execute(message: String, context: BotCommandContext, reply: @escaping (String) -> Void) {
        guard let service = requirePrivilegedService(context: context) else { return }

        Task {
            if let next = await service.skip() {
                reply("Skipped — now playing: \"\(next.title)\" by \(next.artist) (requested by \(next.requesterUsername))")
            } else {
                reply("Skipped — queue is now empty.")
            }
        }
    }
}
