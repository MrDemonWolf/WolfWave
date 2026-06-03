//
//  VoteSkipCommand.swift
//  WolfWave
//
//  Created by Nathanial Henniges on 2026-05-22.
//  Copyright © 2026 MrDemonWolf, Inc. All rights reserved.
//

import Foundation

/// Handles `!voteskip` / `!vs`. Lets chat vote to skip the current song.
///
/// Every viewer can vote. The actual tallying, time window, and skip action live
/// in `SkipVoteManager`; this command just forwards each invocation and formats
/// the chat reply. Cooldowns are `0` on purpose. `SkipVoteManager` owns per-user
/// deduplication and the session window, so the dispatcher's `CooldownManager`
/// must not drop votes.
final class VoteSkipCommand: AsyncBotCommand {
    // MARK: - BotCommand

    /// Chat triggers that invoke this command.
    var triggers: [String] { ["!voteskip", "!vs"] }

    /// Human-readable description shown in the `!commands` listing.
    var description: String { "Vote to skip the current song" }

    /// No global cooldown. `SkipVoteManager` governs vote pacing.
    var globalCooldown: TimeInterval { 0 }

    /// No per-user cooldown. `SkipVoteManager` deduplicates voters per session.
    var userCooldown: TimeInterval { 0 }

    /// UserDefaults key controlling whether the command is enabled.
    var enabledKey: String? { AppConstants.UserDefaults.voteSkipCommandEnabled }

    /// UserDefaults key holding custom trigger aliases.
    var aliasesKey: String? { AppConstants.UserDefaults.voteSkipCommandAliases }

    // MARK: - Properties

    /// Provides the active `SkipVoteManager`. Late-bound to break the
    /// AppDelegate ↔ command dependency cycle at startup.
    var skipVoteManager: (() -> SkipVoteManager?)?

    // MARK: - AsyncBotCommand

    /// Records the vote against the live `SkipVoteManager` and replies with progress.
    ///
    /// - Parameters:
    ///   - message: Raw chat message (unused).
    ///   - context: Sender context, used for per-user vote deduplication.
    ///   - reply: Closure invoked with the chat response.
    func execute(message: String, context: BotCommandContext, reply: @escaping (String) -> Void) {
        guard let manager = skipVoteManager?() else { return }

        Task {
            let outcome = await manager.recordVote(context: context)
            if let response = Self.format(outcome) {
                reply(response)
            }
        }
    }

    // MARK: - Reply Formatting

    /// Converts a `VoteOutcome` into a chat reply, or `nil` when the command
    /// should stay silent (feature disabled).
    static func format(_ outcome: SkipVoteManager.VoteOutcome) -> String? {
        switch outcome {
        case .disabled:
            return nil
        case .subscriberOnly:
            return "🔒 Vote-skip is subscriber-only right now."
        case .onCooldown(let remaining):
            return "⏳ Vote-skip is cooling down, try again in \(remaining)s."
        case .started(let count, let needed):
            return "🗳️ Vote to skip started: \(count)/\(needed). Type !voteskip to vote!"
        case .counted(let count, let needed):
            return "🗳️ \(count)/\(needed) votes to skip this song."
        case .alreadyVoted(let count, let needed):
            return "✅ You already voted: \(count)/\(needed) so far."
        case .passed(let count):
            return "🗳️ Vote passed with \(count) votes, skipping! 🎵"
        case .pollStarted:
            return "📊 Skip poll started. Vote in the Twitch poll!"
        case .pollInProgress:
            return "📊 A skip vote is already running."
        case .pollNotAllowed:
            return "🔒 Only the streamer or mods can start a skip poll."
        }
    }
}
