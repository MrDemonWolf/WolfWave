//
//  HoldCommand.swift
//  wolfwave
//
//  Created by MrDemonWolf, Inc. on 4/8/26.
//

import Foundation

/// Handles `!hold` / `!resume` / `!unhold` — pauses or resumes song request auto-play (mod/broadcaster only).
///
/// While held, new `!sr` requests continue to be accepted and buffered into the queue,
/// but nothing plays automatically. When resumed, the first buffered request starts immediately.
final class HoldCommand: ServiceBoundCommand {
    // MARK: - BotCommand

    var triggers: [String] { ["!hold", "!resume", "!unhold"] }

    var description: String { "Hold or resume song request auto-play (mod/broadcaster only)" }

    var globalCooldown: TimeInterval { 3.0 }

    var userCooldown: TimeInterval { 3.0 }

    // MARK: - Properties

    var songRequestService: (() -> SongRequestService?)?

    // MARK: - AsyncBotCommand

    func execute(message: String, context: BotCommandContext, reply: @escaping (String) -> Void) {
        guard let service = requirePrivilegedService(context: context) else { return }

        let trigger = message.lowercased().components(separatedBy: " ").first ?? ""
        let shouldHold = (trigger == "!hold")

        Task {
            await service.setHold(shouldHold)
            if shouldHold {
                reply("Song requests are on hold — requests will queue but won't play until !resume")
            } else {
                reply("Song requests resumed — playing buffered requests now")
            }
        }
    }
}
