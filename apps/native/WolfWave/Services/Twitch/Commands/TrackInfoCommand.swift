//
//  TrackInfoCommand.swift
//  WolfWave
//
//  Created by Nathanial Henniges on 2026-03-27.
//  Copyright © 2026 MrDemonWolf, Inc. All rights reserved.
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

    // MARK: - BotCommand

    /// Chat triggers that invoke this command (e.g. `["!song"]` or `["!last"]`).
    let triggers: [String]

    /// Human-readable description shown in the `!commands` listing.
    let description: String

    /// UserDefaults key for the user-configurable global cooldown override.
    let globalCooldownKey: String?

    /// UserDefaults key for the user-configurable per-user cooldown override.
    let userCooldownKey: String?

    // MARK: - Thread-safe Closures

    private let lock = NSLock()

    private var _getTrackInfo: (() -> String)?

    /// Closure that returns the current track info string. Thread-safe (NSLock).
    ///
    /// - Important: Read on the EventSub message-handling thread; written by
    ///   the dispatcher on the main thread.
    var getTrackInfo: (() -> String)? {
        get { lock.withLock { _getTrackInfo } }
        set { lock.withLock { _getTrackInfo = newValue } }
    }

    private var _isEnabled: (() -> Bool)?

    /// Closure that returns whether this command is enabled. Thread-safe (NSLock).
    var isEnabled: (() -> Bool)? {
        get { lock.withLock { _isEnabled } }
        set { lock.withLock { _isEnabled = newValue } }
    }

    private var _getTrackInfoAsync: (@Sendable () async -> String)?

    /// Async provider preferred by `executeAsync`. Falls back to `getTrackInfo`
    /// when nil. Wired by production at `BotCommandDispatcher.setCurrentSongInfoAsync`
    /// so the chat-command path can reach MainActor-isolated app state without
    /// the deprecated sync semaphore bridge.
    var getTrackInfoAsync: (@Sendable () async -> String)? {
        get { lock.withLock { _getTrackInfoAsync } }
        set { lock.withLock { _getTrackInfoAsync = newValue } }
    }

    // MARK: - Private State

    private let defaultMessage: String

    // MARK: - Init

    /// Creates a parameterized track-info command.
    ///
    /// - Parameters:
    ///   - triggers: Chat trigger strings (e.g. `["!song", "!currentsong"]`).
    ///   - description: Human-readable description.
    ///   - defaultMessage: Reply used when `getTrackInfo` is unset or returns empty.
    ///   - globalCooldownKey: UserDefaults key for the global cooldown override.
    ///   - userCooldownKey: UserDefaults key for the per-user cooldown override.
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

    // MARK: - Execute

    /// Matches `message` against `triggers`, checks `isEnabled`, then returns
    /// the resolved track info string truncated to Twitch's 500-char limit.
    ///
    /// - Parameter message: Raw chat message.
    /// - Returns: Chat response, or `nil` if no trigger matched or the command
    ///   is disabled.
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

    /// Async variant used by production. Awaits `getTrackInfoAsync` when set so
    /// MainActor-isolated app state can be read without the deprecated
    /// `runSync` semaphore bridge that previously deadlocked MainActor on the
    /// first `!song`/`!last`/`!stats` chat command after Twitch auth.
    func executeAsync(message: String) async -> String? {
        let lowered = message.lowercased()

        for trigger in triggers {
            if lowered.hasPrefix(trigger) {
                let enabledCheck = isEnabled
                let asyncProvider = getTrackInfoAsync
                let syncProvider = getTrackInfo

                if let enabledCheck, !enabledCheck() {
                    return nil
                }

                let result: String
                if let asyncProvider {
                    result = await asyncProvider()
                } else if let syncProvider {
                    result = syncProvider()
                } else {
                    result = defaultMessage
                }
                return result.truncatedForChat()
            }
        }

        return nil
    }
}

// MARK: - String Truncation

nonisolated extension String {
    /// Truncates the string so it fits within Twitch chat's 500-character
    /// per-message limit, appending the configured truncation suffix
    /// (`AppConstants.Twitch.messageTruncationSuffix`) when shortened.
    ///
    /// - Returns: A version of `self` whose byte count does not exceed
    ///   `AppConstants.Twitch.maxMessageLength`.
    func truncatedForChat() -> String {
        let maxLen = AppConstants.Twitch.maxMessageLength
        let suffix = AppConstants.Twitch.messageTruncationSuffix
        guard count > maxLen else { return self }
        let prefixLen = max(maxLen - suffix.count, 0)
        return String(prefix(prefixLen)) + suffix
    }
}
