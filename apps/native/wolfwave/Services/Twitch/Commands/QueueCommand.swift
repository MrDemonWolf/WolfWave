//
//  QueueCommand.swift
//  wolfwave
//
//  Created by MrDemonWolf, Inc. on 4/8/26.
//

import Foundation

/// Handles `!queue` / `!songlist` / `!requests` — shows the current song request queue.
///
/// Displays the next 3-5 songs in queue with position, title, artist, and requester.
final class QueueCommand: BotCommand {
    // MARK: - BotCommand

    /// Chat triggers that invoke this command.
    var triggers: [String] { ["!queue", "!songlist", "!requests"] }

    /// Human-readable description shown in the `!commands` listing.
    var description: String { "Show the current song request queue" }

    /// Channel-wide cooldown between invocations, in seconds.
    var globalCooldown: TimeInterval { 10.0 }

    /// Per-user cooldown between invocations, in seconds.
    var userCooldown: TimeInterval { 15.0 }

    /// UserDefaults key controlling whether the command is enabled.
    var enabledKey: String? { AppConstants.UserDefaults.queueCommandEnabled }

    /// UserDefaults key holding custom trigger aliases.
    var aliasesKey: String? { AppConstants.UserDefaults.queueCommandAliases }

    // MARK: - Properties

    /// Provides the live `SongRequestQueue`. Late-bound to break the
    /// AppDelegate ↔ command dependency cycle at startup.
    var getQueue: (() -> SongRequestQueue?)?

    // MARK: - Execute

    /// Builds a chat-formatted summary of the now-playing track plus the next 5
    /// queued items. Truncates the tail with an "and N more" suffix.
    ///
    /// - Parameter message: Raw chat message (unused).
    /// - Returns: Chat response string, or `nil` if the queue is unavailable.
    func execute(message: String) -> String? {
        guard let queue = getQueue?() else { return nil }

        if queue.isEmpty && queue.nowPlaying == nil {
            return "Queue is empty. Request a song with !sr <song name>"
        }

        var parts: [String] = []

        if let nowPlaying = queue.nowPlaying {
            parts.append("Now playing: \"\(nowPlaying.title)\" — \(nowPlaying.artist) (\(nowPlaying.requesterUsername))")
        }

        let items = queue.items
        if items.isEmpty {
            if parts.isEmpty {
                return "Queue is empty. Request a song with !sr <song name>"
            }
            parts.append("Queue is empty.")
        } else {
            parts.append("Queue (\(items.count)):")
            let displayCount = min(items.count, 5)
            for i in 0..<displayCount {
                let item = items[i]
                parts.append("\(i + 1). \"\(item.title)\" — \(item.artist) (\(item.requesterUsername))")
            }
            if items.count > 5 {
                parts.append("...and \(items.count - 5) more")
            }
        }

        return parts.joined(separator: " | ")
    }
}
