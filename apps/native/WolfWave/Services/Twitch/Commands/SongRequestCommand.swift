//
//  SongRequestCommand.swift
//  WolfWave
//
//  Created by Nathanial Henniges on 2026-04-15.
//  Copyright © 2026 MrDemonWolf, Inc. All rights reserved.
//

import Foundation

/// Handles `!sr` / `!request` / `!songrequest` — searches and queues a song.
///
/// Accepts plain text queries, Spotify links, and YouTube links.
/// Returns an immediate acknowledgment, then resolves asynchronously.
final class SongRequestCommand: AsyncBotCommand {
    // MARK: - BotCommand

    /// Chat triggers that invoke this command.
    var triggers: [String] { ["!sr", "!request", "!songrequest"] }

    /// Human-readable description shown in the `!commands` listing.
    var description: String { "Request a song by name or Spotify/YouTube link" }

    /// Channel-wide cooldown between invocations, in seconds.
    var globalCooldown: TimeInterval { 5.0 }

    /// Per-user cooldown between invocations, in seconds.
    var userCooldown: TimeInterval { 30.0 }

    /// UserDefaults key for the user-configurable global cooldown override.
    var globalCooldownKey: String? { AppConstants.UserDefaults.songRequestGlobalCooldown }

    /// UserDefaults key for the user-configurable per-user cooldown override.
    var userCooldownKey: String? { AppConstants.UserDefaults.songRequestUserCooldown }

    /// UserDefaults key controlling whether the command is enabled.
    var enabledKey: String? { AppConstants.UserDefaults.srCommandEnabled }

    /// UserDefaults key holding custom trigger aliases.
    var aliasesKey: String? { AppConstants.UserDefaults.srCommandAliases }

    // MARK: - Properties

    /// Provides the active `SongRequestService`. Late-bound to break the
    /// AppDelegate ↔ command dependency cycle at startup.
    var songRequestService: (() -> SongRequestService?)?

    // MARK: - AsyncBotCommand

    /// Parses the search query, dispatches to the resolver, and formats the
    /// chat reply for every `RequestResult` case.
    ///
    /// - Parameters:
    ///   - message: Raw chat message; trigger prefix is stripped to recover the query.
    ///   - context: Sender context; `username` is recorded with the queued item.
    ///   - reply: Closure invoked with the chat response.
    func execute(message: String, context: BotCommandContext, reply: @escaping (String) -> Void) {
        // Extract the query (everything after the trigger)
        let query = extractQuery(from: message)

        guard !query.isEmpty else {
            reply("Usage: !sr <song name or Spotify/YouTube link>")
            return
        }

        guard let service = songRequestService?() else {
            reply("Song requests aren't available right now.")
            return
        }

        Task {
            let result = await service.processRequest(
                query: query,
                username: context.username,
                source: .chatCommand(context)
            )

            let response: String
            switch result {
            case .added(let item, let position):
                response = "Added \"\(item.title)\" by \(item.artist) — #\(position) in queue"

            case .queueFull(let max):
                response = "Queue is full (\(max)/\(max)). Try again later!"

            case .userLimitReached(let max):
                response = "You already have \(max) songs queued. Wait for one to play!"

            case .alreadyInQueue:
                response = "That song is already in your queue."

            case .blocked:
                response = "Sorry, that song/artist is on the blocklist."

            case .notFound(let query):
                let truncated = query.count > 30 ? String(query.prefix(30)) + "..." : query
                response = "No results for \"\(truncated)\". Try a different search!"

            case .linkNotFound:
                response = "Couldn't find that on Apple Music. Try a song name instead!"

            case .notAuthorized:
                response = "Song requests aren't available right now."

            case .error(let message):
                response = message
            }

            reply(response)
        }
    }

    // MARK: - Private Helpers

    /// Strips the matched trigger prefix from `message` and returns the remaining
    /// search query, trimmed of surrounding whitespace.
    ///
    /// - Parameter message: Full chat message including the `!sr` prefix.
    /// - Returns: The query portion, or the entire message if no trigger matched.
    private func extractQuery(from message: String) -> String {
        let lowered = message.lowercased()
        for trigger in allTriggers {
            let triggerLowered = trigger.lowercased()
            if lowered.hasPrefix(triggerLowered) {
                let startIndex = message.index(message.startIndex, offsetBy: trigger.count)
                return String(message[startIndex...]).trimmingCharacters(in: .whitespaces)
            }
        }
        return message
    }
}
