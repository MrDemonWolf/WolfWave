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

    /// Chat triggers that invoke this command. `!hold` pauses; `!resume`/`!unhold` resume.
    var triggers: [String] { ["!hold", "!resume", "!unhold"] }

    /// Human-readable description shown in the `!commands` listing.
    var description: String { "Hold or resume song request auto-play (mod/broadcaster only)" }

    /// Channel-wide cooldown between invocations, in seconds.
    var globalCooldown: TimeInterval { 3.0 }

    /// Per-user cooldown between invocations, in seconds.
    var userCooldown: TimeInterval { 3.0 }

    // MARK: - Properties

    /// Provides the active `SongRequestService`. Late-bound to break the
    /// AppDelegate ↔ command dependency cycle at startup.
    var songRequestService: (() -> SongRequestService?)?

    // MARK: - AsyncBotCommand

    /// Toggles the hold state based on which trigger was used.
    ///
    /// - Parameters:
    ///   - message: Raw chat message; first word is matched against triggers.
    ///   - context: Sender context; must be mod or broadcaster.
    ///   - reply: Closure invoked with the chat response.
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
