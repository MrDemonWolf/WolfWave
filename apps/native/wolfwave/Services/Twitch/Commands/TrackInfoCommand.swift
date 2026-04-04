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
///
/// Thread Safety: The `getTrackInfo` and `isEnabled` closure properties are
/// set by BotCommandDispatcher but read by `execute()` from background threads.
/// All access is protected by NSLock.
final class TrackInfoCommand: BotCommand {
    let triggers: [String]
    let description: String

    private let lock = NSLock()

    private var _getTrackInfo: (() -> String)?
    /// Closure that returns the current track info string. Thread-safe.
    var getTrackInfo: (() -> String)? {
        get { lock.withLock { _getTrackInfo } }
        set { lock.withLock { _getTrackInfo = newValue } }
    }

    private var _isEnabled: (() -> Bool)?
    /// Closure that returns whether this command is enabled. Thread-safe.
    var isEnabled: (() -> Bool)? {
        get { lock.withLock { _isEnabled } }
        set { lock.withLock { _isEnabled = newValue } }
    }

    private let defaultMessage: String
    let globalCooldownKey: String?
    let userCooldownKey: String?

    init(
        triggers: [String],
        description: String,
        defaultMessage: String,
        globalCooldownKey: String? = nil,
        userCooldownKey: String? = nil
    ) {
        self.triggers = triggers
        self.description = description
        self.defaultMessage = defaultMessage
        self.globalCooldownKey = globalCooldownKey
        self.userCooldownKey = userCooldownKey
    }

    func execute(message: String) -> String? {
        let lowered = message.lowercased()

        for trigger in triggers {
            if lowered.hasPrefix(trigger) {
                // Snapshot closures under lock to avoid racing with setter
                let enabledCheck = isEnabled
                let trackInfoProvider = getTrackInfo

                if let enabledCheck, !enabledCheck() {
                    return nil
                }

                let result = trackInfoProvider?() ?? defaultMessage
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
