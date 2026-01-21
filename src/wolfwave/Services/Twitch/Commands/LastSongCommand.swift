//
//  LastSongCommand.swift
//  wolfwave
//
//  Created by MrDemonWolf, Inc. on 1/17/26.
//

import Foundation

/// Command that responds with the last played song.
///
/// Triggers: !last, !lastsong, !prevsong
final class LastSongCommand: BotCommand {
    let triggers = ["!last", "!lastsong", "!prevsong"]
    let description = "Displays the last played track"

    var getLastSongInfo: (() -> String)?
    var isEnabled: (() -> Bool)?

    func execute(message: String) -> String? {
        let trimmedMessage = message.trimmingCharacters(in: .whitespaces).lowercased()

        for trigger in triggers {
            if trimmedMessage.hasPrefix(trigger) {
                // Check if command is enabled
                if let isEnabled = isEnabled, !isEnabled() {
                    return nil
                }
                
                let result = getLastSongInfo?() ?? "No previous track available"
                return result.count <= 500 ? result : String(result.prefix(497)) + "..."
            }
        }

        return nil
    }
}
