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
/// The full built-in command suite is registered automatically at init (see
/// `registerDefaultCommands`). Includes cooldown enforcement with moderator bypass.
/// MainActor-isolated (project default isolation); the `NSLock` is retained as a
/// defense-in-depth guard around the command table.
final class BotCommandDispatcher {
    private let lock = NSLock()
    private var commands: [BotCommand] = []

    /// Global pre-flight gate evaluated before any command runs. Returns `true`
    /// when commands are allowed to respond. Wired by `TwitchChatService` to the
    /// "commands only while live" setting folded with stream-live state. Default
    /// `{ true }` so a bare dispatcher (and unit tests) respond unconditionally.
    private var globalGate: () -> Bool = { true }

    /// Fetches live substitution values for custom-command variables (`$song`,
    /// `$lastsong`). Wired by `TwitchChatService`; defaults to empty strings so a
    /// bare dispatcher still renders custom commands (just without live values).
    private var customCommandVariables: @Sendable () async -> CustomCommandVariables = { .empty }
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
    private let wolfwaveCommand = InfoCommand(
        triggers: ["!wolfwave"],
        description: "Shows what WolfWave is and where to get it",
        enabledDefaultsKey: AppConstants.UserDefaults.wolfwaveCommandEnabled,
        globalCooldownKey: AppConstants.UserDefaults.wolfwaveCommandGlobalCooldown,
        userCooldownKey: AppConstants.UserDefaults.wolfwaveCommandUserCooldown,
        aliasesKey: AppConstants.UserDefaults.wolfwaveCommandAliases,
        messageProvider: { WolfWaveReplyStyle.current().message }
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
    let songListCommand = SongListCommand()

    /// Creates a dispatcher pre-loaded with every built-in command.
    init() {
        registerDefaultCommands()
    }

    /// Registers the built-in command suite (`!song`, `!last`, `!stats`,
    /// `!wolfwave`, `!sr`, `!queue`, `!myqueue`, `!skip`, `!clearqueue`,
    /// `!hold`, `!voteskip`, `!playlist`). Called once from `init`.
    private func registerDefaultCommands() {
        register(songCommand)
        register(lastSongCommand)
        register(statsCommand)
        register(wolfwaveCommand)
        register(srCommand)
        register(queueCommand)
        register(myQueueCommand)
        register(skipCommand)
        register(clearQueueCommand)
        register(holdCommand)
        register(voteSkipCommand)
        register(songListCommand)
    }

    /// Adds a `BotCommand` to the dispatch table. Thread-safe.
    ///
    /// - Parameter command: Command instance. Duplicate triggers are not
    ///   detected. Last-registered wins.
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

    /// Wires the async `!song` provider. Preferred by `processMessageAsync`,
    /// bridges MainActor-isolated AppDelegate state without the deprecated
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

    /// Wires the global pre-flight gate (the "commands only while live" switch).
    ///
    /// - Parameter callback: Closure returning `true` when commands may respond.
    ///   Evaluated once per message before trigger matching, so toggling the
    ///   setting or going live/offline takes effect on the next message.
    func setGlobalGate(callback: @escaping () -> Bool) {
        lock.withLock {
            globalGate = callback
        }
    }

    /// Wires the live-value provider for custom-command variables.
    ///
    /// - Parameter provider: Async closure returning the current/last song used
    ///   to interpolate `$song` / `$lastsong` in custom command replies.
    func setCustomCommandVariablesProvider(
        _ provider: @escaping @Sendable () async -> CustomCommandVariables
    ) {
        lock.withLock {
            customCommandVariables = provider
        }
    }

    /// The full command table for a message: the user's enabled custom commands
    /// first, then the built-in commands. Rebuilt each message so edits in
    /// Settings apply on the next chat line without re-registration.
    ///
    /// Custom commands come first so an enabled custom command that reuses a
    /// built-in trigger (e.g. a custom `!song`) can override it. When that custom
    /// command is disabled or denies the viewer, the dispatch loop `break`s to the
    /// next match, falling back to the shadowed built-in.
    private func commandSnapshot() -> [BotCommand] {
        let builtins = lock.withLock { commands }
        let vars = lock.withLock { customCommandVariables }
        let custom = CustomCommandStore.shared.enabledCommands.map {
            CustomBotCommand(definition: $0, variables: vars)
        }
        return custom + builtins
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

        // Global pre-flight gate ("commands only while live"). Closed → every
        // command stays silent regardless of its own enable state.
        let gate = lock.withLock { globalGate }
        guard gate() else {
            return nil
        }

        let lowered = trimmedMessage.lowercased()
        // Match on the first whitespace-delimited token, not a prefix. Prefix
        // matching let a short alias (e.g. "!s") capture longer commands
        // ("!skip") and let "!song" swallow "!songrequest". Exact first-token
        // equality routes each message to exactly one command.
        let commandToken = lowered.split(whereSeparator: \.isWhitespace).first.map(String.init) ?? lowered

        // Every trigger (built-in, alias, and custom) is normalized to a leading
        // "!", so a token without one can't match. Bail before the snapshot copy
        // and the per-command alias reads for the common non-command chat line.
        guard commandToken.hasPrefix("!") else { return nil }

        let snapshot = commandSnapshot()
        for command in snapshot {
            // Use allTriggers (includes user-configured aliases)
            let triggers = command.allTriggers
            for trigger in triggers {
                let triggerLowered = trigger.lowercased()
                if commandToken == triggerLowered {
                    // Check if command is enabled. `break` (not `return nil`) so a
                    // disabled command falls through to another match on the same
                    // trigger (e.g. a disabled custom command → its built-in).
                    guard command.isCommandEnabled else {
                        break
                    }

                    // Permission gate (custom commands), before cooldown so a
                    // denied viewer can't warm the shared cooldown. `break` lets a
                    // shadowed built-in with the same trigger still run.
                    if let context, !command.isAllowed(context: context) {
                        break
                    }

                    let canonical = command.triggers.first ?? trigger
                    // Load cooldown overrides from UserDefaults
                    let (globalCD, userCD) = cooldownValues(for: trigger, command: command)

                    // Check cooldown using canonical key (mods bypass)
                    if cooldownManager.isOnCooldown(
                        trigger: canonical,
                        userID: userID,
                        isModerator: isModerator,
                        bypassesCooldown: command.bypassesCooldown(context: context),
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
                            "BotCommandDispatcher: Command '\(trigger)' (group: \(canonical)) on cooldown for user \(userID), global: \(String(format: "%.1f", remaining.global))s remaining, per-user: \(String(format: "%.1f", remaining.perUser))s remaining",
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
                            "BotCommandDispatcher: Command '\(trigger)' (group: \(canonical)) executed, cooldown set: global=\(String(format: "%.1f", globalCD))s, per-user=\(String(format: "%.1f", userCD))s",
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
            Log.debug("BotCommandDispatcher: processMessageAsync: empty/too-long, bail", category: "Twitch")
            return nil
        }

        // Global pre-flight gate ("commands only while live"). Closed → every
        // command stays silent regardless of its own enable state.
        let gate = lock.withLock { globalGate }
        guard gate() else {
            Log.debug("BotCommandDispatcher: global gate closed (live-only, stream offline), bail", category: "Twitch")
            return nil
        }

        let lowered = trimmedMessage.lowercased()
        // First-token equality (see processMessage), avoids alias/prefix collisions.
        let commandToken = lowered.split(whereSeparator: \.isWhitespace).first.map(String.init) ?? lowered

        // See processMessage: triggers are all "!"-prefixed, so skip the snapshot
        // copy + alias reads for non-command lines (the vast majority of chat).
        guard commandToken.hasPrefix("!") else { return nil }

        let snapshot = commandSnapshot()
        for command in snapshot {
            let triggers = command.allTriggers
            for trigger in triggers {
                let triggerLowered = trigger.lowercased()
                if commandToken == triggerLowered {
                    Log.debug("BotCommandDispatcher: matched trigger \(trigger)", category: "Twitch")
                    // `break` (not `return nil`) so a disabled/denied command
                    // falls through to another match on the same trigger (e.g. a
                    // disabled custom command → its shadowed built-in).
                    guard command.isCommandEnabled else {
                        Log.debug("BotCommandDispatcher: command \(trigger) disabled, try next match", category: "Twitch")
                        break
                    }

                    if let context, !command.isAllowed(context: context) {
                        Log.debug("BotCommandDispatcher: command \(trigger) denied by permission, try next match", category: "Twitch")
                        break
                    }

                    let canonical = command.triggers.first ?? trigger
                    let (globalCD, userCD) = cooldownValues(for: trigger, command: command)

                    if cooldownManager.isOnCooldown(
                        trigger: canonical,
                        userID: userID,
                        isModerator: isModerator,
                        bypassesCooldown: command.bypassesCooldown(context: context),
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
                            "BotCommandDispatcher: Command '\(trigger)' (group: \(canonical)) on cooldown for user \(userID), global: \(String(format: "%.1f", remaining.global))s remaining, per-user: \(String(format: "%.1f", remaining.perUser))s remaining",
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
                            "BotCommandDispatcher: Command '\(trigger)' (group: \(canonical)) executed, cooldown set: global=\(String(format: "%.1f", globalCD))s, per-user=\(String(format: "%.1f", userCD))s",
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
