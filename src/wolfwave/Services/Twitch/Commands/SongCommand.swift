//
//  SongCommand.swift
//  wolfwave
//
//  Created by MrDemonWolf, Inc. on 1/17/26.
//

import Foundation

/// Command that responds with the currently playing song.
///
/// Triggers: !song, !currentsong, !nowplaying
final class SongCommand: BotCommand {
    let triggers = ["!song", "!currentsong", "!nowplaying"]
    let description = "Displays the currently playing track"

    var getCurrentSongInfo: (() -> String)?
    var isEnabled: (() -> Bool)?

    func execute(message: String) -> String? {
        let trimmedMessage = message.trimmingCharacters(in: .whitespaces).lowercased()

        for trigger in triggers {
            if trimmedMessage.hasPrefix(trigger) {
                // Check if command is enabled
                if let isEnabled = isEnabled, !isEnabled() {
                    Log.info("SongCommand: Command triggered but disabled, ignoring: \(trimmedMessage)", category: "BotCommands")
                    return nil
                }
                
                let result = getCurrentSongInfo?() ?? "No track currently playing"
                return result.count <= 500 ? result : String(result.prefix(497)) + "..."
            }
        }

        return nil
    }
}
