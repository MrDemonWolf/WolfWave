//
//  BotCommandDispatcher.swift
//  WolfWave
//
//  Created by Nathanial Henniges on 2026-01-08.
//  Copyright © 2026 MrDemonWolf, Inc. All rights reserved.
//

import Foundation

/// Routes chat messages to appropriate bot command handlers.
///
/// Default commands (!song, !last, !lastsong) are registered automatically.
/// Includes cooldown enforcement with moderator bypass.
/// MainActor-isolated (project default isolation); the `NSLock` is retained as a
/// defense-in-depth guard around the command table.
final class BotCommandDispatcher {
    private let lock = NSLock()
    private var commands: [BotCommand] = []
    private let songCommand = TrackInfoCommand(
        triggers: ["!song", "!currentsong", "!nowplaying"],
        description: "Displays the currently playing track",
        defaultMessage: "No track currently playing",
        globalCooldownKey: AppConstants.UserDefaults.songCommandGlobalCooldown,
        userCooldownKey: AppConstants.UserDefaults.songCommandUserCooldown,
        aliasesKey: AppConstants.UserDefaults.songCommandAliases
    )
    private let lastSongCommand = TrackInfoCommand(
        triggers: ["!last", "!lastsong", "!prevsong"],
        description: "Displays the last played track",
        defaultMessage: "No previous track available",
        globalCooldownKey: AppConstants.UserDefaults.lastSongCommandGlobalCooldown,
        userCooldownKey: AppConstants.UserDefaults.lastSongCommandUserCooldown,
        aliasesKey: AppConstants.UserDefaults.lastSongCommandAliases
    )
    private let statsCommand = TrackInfoCommand(
        triggers: ["!stats", "!musicstats"],
        description: "Displays today's listening stats (live streams only)",
        defaultMessage: "No listening stats yet",
        globalCooldownKey: AppConstants.UserDefaults.statsCommandGlobalCooldown,
        userCooldownKey: AppConstants.UserDefaults.statsCommandUserCooldown,
        aliasesKey: AppConstants.UserDefaults.statsCommandAliases
    )
    private let cooldownManager = CooldownManager()

    // Song request commands
    let srCommand = SongRequestCommand()
    let queueCommand = QueueCommand()
    let myQueueCommand = MyQueueCommand()
    let skipCommand = SkipCommand()
    let clearQueueCommand = ClearQueueCommand()
    let holdCommand = HoldCommand()
    let voteSkipCommand = VoteSkipCommand()

    /// Creates a dispatcher pre-loaded with every built-in command.
    init() {
        registerDefaultCommands()
    }

    /// Registers the built-in command suite (`!song`, `!last`, `!sr`, `!queue`,
    /// `!myqueue`, `!skip`, `!clearqueue`, `!hold`, `!voteskip`). Called once from `init`.
    private func registerDefaultCommands() {
        register(songCommand)
        register(lastSongCommand)
        register(statsCommand)
        register(srCommand)
        register(queueCommand)
        register(myQueueCommand)
        register(skipCommand)
        register(clearQueueCommand)
        register(holdCommand)
        register(voteSkipCommand)
    }

    /// Adds a `BotCommand` to the dispatch table. Thread-safe.
    ///
    /// - Parameter command: Command instance. Duplicate triggers are not
    ///   detected — last-registered wins.
    func register(_ command: BotCommand) {
        lock.withLock {
            commands.append(command)
        }
    }

    /// Wires the now-playing string provider into the `!song` command.
    ///
    /// - Parameter callback: Closure returning the current track info.
    func setCurrentSongInfo(callback: @escaping () -> String) {
        lock.withLock {
            songCommand.getTrackInfo = callback
        }
    }

    /// Wires the previously-played-track provider into the `!last` command.
    ///
    /// - Parameter callback: Closure returning the previous track info.
    func setLastSongInfo(callback: @escaping () -> String) {
        lock.withLock {
            lastSongCommand.getTrackInfo = callback
        }
    }

    /// Wires the enabled-state provider for the `!song` command.
    ///
    /// - Parameter callback: Closure returning `true` if `!song` should respond.
    func setCurrentSongCommandEnabled(callback: @escaping () -> Bool) {
        lock.withLock {
            songCommand.isEnabled = callback
        }
    }

    /// Wires the enabled-state provider for the `!last` command.
    ///
    /// - Parameter callback: Closure returning `true` if `!last` should respond.
    func setLastSongCommandEnabled(callback: @escaping () -> Bool) {
        lock.withLock {
            lastSongCommand.isEnabled = callback
        }
    }

    /// Wires the listening-stats provider into the `!stats` command.
    ///
    /// - Parameter callback: Closure returning the current stats string.
    func setStatsInfo(callback: @escaping () -> String) {
        lock.withLock {
            statsCommand.getTrackInfo = callback
        }
    }

    // MARK: - Async Provider Wiring (Production Path)

    /// Wires the async `!song` provider. Preferred by `processMessageAsync`
    /// — bridges MainActor-isolated AppDelegate state without the deprecated
    /// `runSync` semaphore that previously deadlocked MainActor.
    func setCurrentSongInfoAsync(callback: @Sendable @escaping () async -> String) {
        lock.withLock {
            songCommand.getTrackInfoAsync = callback
        }
    }

    /// Wires the async `!last` provider. See `setCurrentSongInfoAsync` for the
    /// deadlock rationale.
    func setLastSongInfoAsync(callback: @Sendable @escaping () async -> String) {
        lock.withLock {
            lastSongCommand.getTrackInfoAsync = callback
        }
    }

    /// Wires the async `!stats` provider. See `setCurrentSongInfoAsync` for the
    /// deadlock rationale.
    func setStatsInfoAsync(callback: @Sendable @escaping () async -> String) {
        lock.withLock {
            statsCommand.getTrackInfoAsync = callback
        }
    }

    /// Wires the enabled-state provider for the `!stats` command.
    ///
    /// - Parameter callback: Closure returning `true` if `!stats` should respond
    ///   (Stats feature on, command on, and the stream is live).
    func setStatsCommandEnabled(callback: @escaping () -> Bool) {
        lock.withLock {
            statsCommand.isEnabled = callback
        }
    }

    // MARK: - Song Request Command Wiring

    /// Injects the live `SongRequestService` reference into every command
    /// that mutates the queue (`!sr`, `!skip`, `!clearqueue`, `!hold`).
    func setSongRequestService(callback: @escaping () -> SongRequestService?) {
        lock.withLock {
            srCommand.songRequestService = callback
            skipCommand.songRequestService = callback
            clearQueueCommand.songRequestService = callback
            holdCommand.songRequestService = callback
        }
    }

    /// Injects the live `SongRequestQueue` reference into every read-only
    /// queue command (`!queue`, `!myqueue`).
    func setSongRequestQueue(callback: @escaping () -> SongRequestQueue?) {
        lock.withLock {
            queueCommand.getQueue = callback
            myQueueCommand.getQueue = callback
        }
    }

    /// Injects the live `SkipVoteManager` reference into the `!voteskip` command.
    func setSkipVoteManager(callback: @escaping () -> SkipVoteManager?) {
        lock.withLock {
            voteSkipCommand.skipVoteManager = callback
        }
    }

    /// Processes a chat message and returns a command response if matched.
    ///
    /// - Parameters:
    ///   - message: The chat message text.
    ///   - userID: The Twitch user ID of the sender (for per-user cooldowns).
    ///   - isModerator: Whether the user has a moderator badge (bypasses cooldowns).
    /// - Returns: The command response string, or nil if no command matched or on cooldown.
    func processMessage(_ message: String, userID: String = "", isModerator: Bool = false) -> String? {
        return processMessage(message, userID: userID, isModerator: isModerator, context: nil, asyncReply: nil)
    }

    /// Processes a chat message with full context, supporting both sync and async commands.
    ///
    /// - Parameters:
    ///   - message: The chat message text.
    ///   - userID: The Twitch user ID of the sender (for per-user cooldowns).
    ///   - isModerator: Whether the user has a moderator badge (bypasses cooldowns).
    ///   - context: Full user context for async commands (nil for legacy callers).
    ///   - asyncReply: Callback for async command responses (nil for sync-only callers).
    /// - Returns: The command response string for sync commands, or nil if async/no match/on cooldown.
    func processMessage(
        _ message: String,
        userID: String = "",
        isModerator: Bool = false,
        context: BotCommandContext?,
        asyncReply: ((String) -> Void)?
    ) -> String? {
        let trimmedMessage = message.trimmingCharacters(in: .whitespaces)

        guard !trimmedMessage.isEmpty, trimmedMessage.count <= AppConstants.Twitch.maxMessageLength else {
            return nil
        }

        let lowered = trimmedMessage.lowercased()
        // Match on the first whitespace-delimited token, not a prefix. Prefix
        // matching let a short alias (e.g. "!s") capture longer commands
        // ("!skip") and let "!song" swallow "!songrequest". Exact first-token
        // equality routes each message to exactly one command.
        let commandToken = lowered.split(whereSeparator: \.isWhitespace).first.map(String.init) ?? lowered

        let snapshot = lock.withLock { commands }
        for command in snapshot {
            // Use allTriggers (includes user-configured aliases)
            let triggers = command.allTriggers
            for trigger in triggers {
                let triggerLowered = trigger.lowercased()
                if commandToken == triggerLowered {
                    // Check if command is enabled
                    guard command.isCommandEnabled else {
                        return nil
                    }

                    let canonical = command.triggers.first ?? trigger
                    // Load cooldown overrides from UserDefaults
                    let (globalCD, userCD) = cooldownValues(for: trigger, command: command)

                    // Check cooldown using canonical key (mods bypass)
                    if cooldownManager.isOnCooldown(
                        trigger: canonical,
                        userID: userID,
                        isModerator: isModerator,
                        globalCooldown: globalCD,
                        userCooldown: userCD
                    ) {
                        let remaining = cooldownManager.remainingCooldown(
                            trigger: canonical,
                            userID: userID,
                            globalCooldown: globalCD,
                            userCooldown: userCD
                        )
                        Log.debug(
                            "BotCommandDispatcher: Command '\(trigger)' (group: \(canonical)) on cooldown for user \(userID) — global: \(String(format: "%.1f", remaining.global))s remaining, per-user: \(String(format: "%.1f", remaining.perUser))s remaining",
                            category: "Twitch")
                        return nil
                    }

                    // Try async command first if context is available
                    if let asyncCommand = command as? AsyncBotCommand, let ctx = context, let reply = asyncReply {
                        cooldownManager.recordUse(trigger: canonical, userID: userID)
                        asyncCommand.execute(message: trimmedMessage, context: ctx, reply: reply)
                        Log.debug(
                            "BotCommandDispatcher: Async command '\(trigger)' (group: \(canonical)) dispatched",
                            category: "Twitch")
                        return nil // Response will come via asyncReply callback
                    }

                    // Sync command
                    if let response = command.execute(message: trimmedMessage) {
                        cooldownManager.recordUse(trigger: canonical, userID: userID)
                        Log.debug(
                            "BotCommandDispatcher: Command '\(trigger)' (group: \(canonical)) executed — cooldown set: global=\(String(format: "%.1f", globalCD))s, per-user=\(String(format: "%.1f", userCD))s",
                            category: "Twitch")
                        return response
                    }
                    break
                }
            }
        }

        return nil
    }

    /// Async variant of `processMessage` for the production chat-message path.
    ///
    /// Mirrors `processMessage` but awaits `TrackInfoCommand.executeAsync`,
    /// so async providers (`setCurrentSongInfoAsync`, etc.) can reach
    /// MainActor-isolated app state without the deprecated `runSync`
    /// semaphore bridge.
    func processMessageAsync(
        _ message: String,
        userID: String = "",
        isModerator: Bool = false,
        context: BotCommandContext?,
        asyncReply: ((String) -> Void)?
    ) async -> String? {
        Log.debug("BotCommandDispatcher: processMessageAsync enter msg=\(message.prefix(40))", category: "Twitch")
        let trimmedMessage = message.trimmingCharacters(in: .whitespaces)

        guard !trimmedMessage.isEmpty, trimmedMessage.count <= AppConstants.Twitch.maxMessageLength else {
            Log.debug("BotCommandDispatcher: processMessageAsync — empty/too-long, bail", category: "Twitch")
            return nil
        }

        let lowered = trimmedMessage.lowercased()
        // First-token equality (see processMessage) — avoids alias/prefix collisions.
        let commandToken = lowered.split(whereSeparator: \.isWhitespace).first.map(String.init) ?? lowered

        let snapshot = lock.withLock { commands }
        for command in snapshot {
            let triggers = command.allTriggers
            for trigger in triggers {
                let triggerLowered = trigger.lowercased()
                if commandToken == triggerLowered {
                    Log.debug("BotCommandDispatcher: matched trigger \(trigger)", category: "Twitch")
                    guard command.isCommandEnabled else {
                        Log.debug("BotCommandDispatcher: command \(trigger) disabled, bail", category: "Twitch")
                        return nil
                    }

                    let canonical = command.triggers.first ?? trigger
                    let (globalCD, userCD) = cooldownValues(for: trigger, command: command)

                    if cooldownManager.isOnCooldown(
                        trigger: canonical,
                        userID: userID,
                        isModerator: isModerator,
                        globalCooldown: globalCD,
                        userCooldown: userCD
                    ) {
                        let remaining = cooldownManager.remainingCooldown(
                            trigger: canonical,
                            userID: userID,
                            globalCooldown: globalCD,
                            userCooldown: userCD
                        )
                        Log.debug(
                            "BotCommandDispatcher: Command '\(trigger)' (group: \(canonical)) on cooldown for user \(userID) — global: \(String(format: "%.1f", remaining.global))s remaining, per-user: \(String(format: "%.1f", remaining.perUser))s remaining",
                            category: "Twitch")
                        return nil
                    }

                    if let asyncCommand = command as? AsyncBotCommand, let ctx = context, let reply = asyncReply {
                        cooldownManager.recordUse(trigger: canonical, userID: userID)
                        asyncCommand.execute(message: trimmedMessage, context: ctx, reply: reply)
                        Log.debug(
                            "BotCommandDispatcher: Async command '\(trigger)' (group: \(canonical)) dispatched",
                            category: "Twitch")
                        return nil
                    }

                    let response: String?
                    if let track = command as? TrackInfoCommand {
                        Log.debug("BotCommandDispatcher: TrackInfoCommand.executeAsync start \(trigger)", category: "Twitch")
                        response = await track.executeAsync(message: trimmedMessage)
                        Log.debug("BotCommandDispatcher: TrackInfoCommand.executeAsync done \(trigger) → \(response?.prefix(40) ?? "nil")", category: "Twitch")
                    } else {
                        response = command.execute(message: trimmedMessage)
                    }

                    if let response {
                        cooldownManager.recordUse(trigger: canonical, userID: userID)
                        Log.debug(
                            "BotCommandDispatcher: Command '\(trigger)' (group: \(canonical)) executed — cooldown set: global=\(String(format: "%.1f", globalCD))s, per-user=\(String(format: "%.1f", userCD))s",
                            category: "Twitch")
                        return response
                    }
                    break
                }
            }
        }

        return nil
    }

    /// Resets all cooldown state (e.g., on disconnect).
    func resetCooldowns() {
        cooldownManager.reset()
    }

    // MARK: - Private Helpers

    /// Returns the effective cooldown values for a command, checking UserDefaults overrides.
    ///
    /// Commands declare their own UserDefaults keys via `globalCooldownKey`/`userCooldownKey`.
    /// If a key is nil or the stored value is absent, the command's default is used.
    private func cooldownValues(for trigger: String, command: BotCommand) -> (TimeInterval, TimeInterval) {
        let defaults = Foundation.UserDefaults.standard
        let globalCD = command.globalCooldownKey
            .flatMap { defaults.object(forKey: $0) as? TimeInterval }
            ?? command.globalCooldown
        let userCD = command.userCooldownKey
            .flatMap { defaults.object(forKey: $0) as? TimeInterval }
            ?? command.userCooldown
        return (globalCD, userCD)
    }
}
