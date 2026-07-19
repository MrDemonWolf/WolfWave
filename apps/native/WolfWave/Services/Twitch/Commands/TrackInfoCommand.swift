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
/// MainActor-isolated (project default isolation). The `getTrackInfo`,
/// `getTrackInfoAsync`, and `isEnabled` closure properties keep an `NSLock` as a
/// defense-in-depth guard around their backing storage; the lock is retained,
/// not relied on for cross-thread access.
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

    /// UserDefaults key for user-configured alias triggers (comma-separated).
    let aliasesKey: String?

    // MARK: - Thread-safe Closures

    private let lock = NSLock()

    private var _getTrackInfo: (() -> String)?

    /// Closure that returns the current track info string. Backed by a lock-
    /// guarded property (defense-in-depth on the MainActor-isolated type).
    var getTrackInfo: (() -> String)? {
        get { lock.withLock { _getTrackInfo } }
        set { lock.withLock { _getTrackInfo = newValue } }
    }

    private var _isEnabled: (() -> Bool)?

    /// Closure that returns whether this command is enabled. Backed by a lock-
    /// guarded property (defense-in-depth on the MainActor-isolated type).
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
        userCooldownKey: String? = nil,
        aliasesKey: String? = nil
    ) {
        self.triggers = triggers
        self.description = description
        self.defaultMessage = defaultMessage
        self.globalCooldownKey = globalCooldownKey
        self.userCooldownKey = userCooldownKey
        self.aliasesKey = aliasesKey
    }

    // MARK: - Execute

    /// Matches `message` against `triggers`, checks `isEnabled`, then returns
    /// the resolved track info string truncated to Twitch's 500-char limit.
    ///
    /// - Parameter message: Raw chat message.
    /// - Returns: Chat response, or `nil` if no trigger matched or the command
    ///   is disabled.
    func execute(message: String) -> String? {
        let token = commandToken(in: message)

        for trigger in allTriggers {
            if token == trigger.lowercased() {
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
        let token = commandToken(in: message)

        for trigger in allTriggers {
            if token == trigger.lowercased() {
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
