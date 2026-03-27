//
//  TrackInfoCommand.swift
//  wolfwave
//
//  Created by MrDemonWolf, Inc. on 3/22/26.
//

import Foundation

/// A parameterized bot command that responds with track information.
///
/// Used for both current song and last song commands, avoiding
/// duplicated execute/truncation logic.
final class TrackInfoCommand: BotCommand {
    let triggers: [String]
    let description: String

    var getTrackInfo: (() -> String)?
    var isEnabled: (() -> Bool)?

    private let defaultMessage: String

    init(triggers: [String], description: String, defaultMessage: String) {
        self.triggers = triggers
        self.description = description
        self.defaultMessage = defaultMessage
    }

    func execute(message: String) -> String? {
        let lowered = message.lowercased()

        for trigger in triggers {
            if lowered.hasPrefix(trigger) {
                if let isEnabled = isEnabled, !isEnabled() {
                    return nil
                }

                let result = getTrackInfo?() ?? defaultMessage
                return result.truncatedForChat()
            }
        }

        return nil
    }
}

// MARK: - String Truncation

extension String {
    /// Truncates the string to fit within Twitch chat message limits.
    func truncatedForChat() -> String {
        let maxLen = AppConstants.Twitch.maxMessageLength
        let suffix = AppConstants.Twitch.messageTruncationSuffix
        guard count > maxLen else { return self }
        let prefixLen = max(maxLen - suffix.count, 0)
        return String(prefix(prefixLen)) + suffix
    }
}
