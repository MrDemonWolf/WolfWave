//
//  LastSongCommand.swift
//  wolfwave
//
//  Created by MrDemonWolf, Inc. on 1/13/26.
//

import Foundation

/// Command that responds with the last played song.
///
/// Triggers: !last, !lastsong, !prevsong
final class LastSongCommand: BotCommand {
    let triggers = ["!last", "!lastsong", "!prevsong"]
    let description = "Displays the last played track"

    /// Callback to get the last song information
    var getLastSongInfo: (() -> String)?

    func execute(message: String) -> String? {
        let trimmedMessage = message.trimmingCharacters(in: .whitespaces).lowercased()

        // Check if message starts with any of our triggers
        for trigger in triggers {
            if trimmedMessage.hasPrefix(trigger) {
                return getLastSongInfo?()
            }
        }

        return nil
    }
}
