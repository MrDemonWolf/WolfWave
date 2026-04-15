//
//  SongRequestCommand.swift
//  wolfwave
//
//  Created by MrDemonWolf, Inc. on 4/8/26.
//

import Foundation

/// Handles `!sr` / `!request` / `!songrequest` — searches and queues a song.
///
/// Accepts plain text queries, Spotify links, and YouTube links.
/// Returns an immediate acknowledgment, then resolves asynchronously.
final class SongRequestCommand: AsyncBotCommand {
    // MARK: - BotCommand

    var triggers: [String] { ["!sr", "!request", "!songrequest"] }

    var description: String { "Request a song by name or Spotify/YouTube link" }

    var globalCooldown: TimeInterval { 5.0 }

    var userCooldown: TimeInterval { 30.0 }

    var globalCooldownKey: String? { AppConstants.UserDefaults.songRequestGlobalCooldown }

    var userCooldownKey: String? { AppConstants.UserDefaults.songRequestUserCooldown }

    var enabledKey: String? { AppConstants.UserDefaults.srCommandEnabled }

    var aliasesKey: String? { AppConstants.UserDefaults.srCommandAliases }

    // MARK: - Properties

    /// Reference to the song request service for processing.
    var songRequestService: (() -> SongRequestService?)?

    // MARK: - AsyncBotCommand

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
                context: context
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

    /// Extract the search query from the full message (strip the trigger prefix).
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
