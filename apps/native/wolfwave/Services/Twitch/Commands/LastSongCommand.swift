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
        let lowered = message.lowercased()

        for trigger in triggers {
            if lowered.hasPrefix(trigger) {
                // Check if command is enabled
                if let isEnabled = isEnabled, !isEnabled() {
                    return nil
                }
                
                let result = getLastSongInfo?() ?? "No previous track available"
                let maxLen = AppConstants.Twitch.maxMessageLength
                let suffix = AppConstants.Twitch.messageTruncationSuffix
                guard result.count > maxLen else { return result }
                let prefixLen = max(maxLen - suffix.count, 0)
                return String(result.prefix(prefixLen)) + suffix
            }
        }

        return nil
    }
}
