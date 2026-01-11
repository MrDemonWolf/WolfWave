//
//  SongCommand.swift
//  wolfwave
//
//  Created by MrDemonWolf, Inc. on 1/8/26.
//

import Foundation

/// Command that responds with the currently playing song.
///
/// Triggers: !song, !currentsong, !nowplaying
final class SongCommand: BotCommand {
    let triggers = ["!song", "!currentsong", "!nowplaying"]
    let description = "Displays the currently playing track"

    /// Callback to get the current song information
    var getCurrentSongInfo: (() -> String)?

    func execute(message: String) -> String? {
        let trimmedMessage = message.trimmingCharacters(in: .whitespaces).lowercased()

        // Check if message starts with any of our triggers
        for trigger in triggers {
            if trimmedMessage.hasPrefix(trigger) {
                return getCurrentSongInfo?()
            }
        }

        return nil
    }
}
