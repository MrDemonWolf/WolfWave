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
        let lowered = message.lowercased()

        for trigger in triggers {
            if lowered.hasPrefix(trigger) {
                // Check if command is enabled
                if let isEnabled = isEnabled, !isEnabled() {
                    return nil
                }
                
                let result = getCurrentSongInfo?() ?? "No track currently playing"
                let maxLen = AppConstants.Twitch.maxMessageLength
                let suffix = AppConstants.Twitch.messageTruncationSuffix
                return result.count <= maxLen ? result : String(result.prefix(maxLen - suffix.count)) + suffix
            }
        }

        return nil
    }
}
