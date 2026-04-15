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

    var triggers: [String] { ["!queue", "!songlist", "!requests"] }

    var description: String { "Show the current song request queue" }

    var globalCooldown: TimeInterval { 10.0 }

    var userCooldown: TimeInterval { 15.0 }

    var enabledKey: String? { AppConstants.UserDefaults.queueCommandEnabled }

    var aliasesKey: String? { AppConstants.UserDefaults.queueCommandAliases }

    // MARK: - Properties

    /// Reference to the song request queue.
    var getQueue: (() -> SongRequestQueue?)?

    // MARK: - Execute

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
