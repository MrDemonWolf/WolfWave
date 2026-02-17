//
//  BotCommandDispatcher.swift
//  wolfwave
//
//  Created by MrDemonWolf, Inc. on 1/17/26.
//

import Foundation

/// Routes chat messages to appropriate bot command handlers.
///
/// Default commands (!song, !last, !lastsong) are registered automatically.
/// Includes cooldown enforcement with moderator bypass.
/// Thread-safe for concurrent access from any thread.
final class BotCommandDispatcher {
    private var commands: [BotCommand] = []
    private let songCommand = SongCommand()
    private let lastSongCommand = LastSongCommand()
    private let cooldownManager = CooldownManager()

    init() {
        registerDefaultCommands()
    }

    private func registerDefaultCommands() {
        register(songCommand)
        register(lastSongCommand)
    }

    func register(_ command: BotCommand) {
        lock.withLock {
            commands.append(command)
        }
    }

    func setCurrentSongInfo(callback: @escaping () -> String) {
        lock.withLock {
            songCommand.getCurrentSongInfo = callback
        }
    }

    func setLastSongInfo(callback: @escaping () -> String) {
        lock.withLock {
            lastSongCommand.getLastSongInfo = callback
        }
    }

    func setCurrentSongCommandEnabled(callback: @escaping () -> Bool) {
        lock.withLock {
            songCommand.isEnabled = callback
        }
    }

    func setLastSongCommandEnabled(callback: @escaping () -> Bool) {
        lock.withLock {
            lastSongCommand.isEnabled = callback
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
        let trimmedMessage = message.trimmingCharacters(in: .whitespaces)

        guard !trimmedMessage.isEmpty, trimmedMessage.count <= AppConstants.Twitch.maxMessageLength else {
            return nil
        }

        let lowered = trimmedMessage.lowercased()

        for command in commands {
            for trigger in command.triggers {
                if lowered.hasPrefix(trigger) {
                    // Load cooldown overrides from UserDefaults
                    let (globalCD, userCD) = cooldownValues(for: trigger, command: command)

                    // Check cooldown (mods bypass)
                    if cooldownManager.isOnCooldown(
                        trigger: trigger,
                        userID: userID,
                        isModerator: isModerator,
                        globalCooldown: globalCD,
                        userCooldown: userCD
                    ) {
                        Log.debug(
                            "Command '\(trigger)' on cooldown for user \(userID)",
                            category: "BotCommands")
                        return nil
                    }

                    if let response = command.execute(message: trimmedMessage) {
                        cooldownManager.recordUse(trigger: trigger, userID: userID)
                        Log.debug(
                            "Command '\(trimmedMessage.prefix(50))' executed",
                            category: "BotCommands")
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

    /// Returns the effective cooldown values for a trigger, checking UserDefaults overrides.
    private func cooldownValues(for trigger: String, command: BotCommand) -> (TimeInterval, TimeInterval) {
        let defaults = Foundation.UserDefaults.standard

        // Map known triggers to UserDefaults keys
        switch trigger {
        case "!song", "!currentsong", "!nowplaying":
            let globalCD = defaults.object(forKey: AppConstants.UserDefaults.songCommandGlobalCooldown) as? TimeInterval
                ?? command.globalCooldown
            let userCD = defaults.object(forKey: AppConstants.UserDefaults.songCommandUserCooldown) as? TimeInterval
                ?? command.userCooldown
            return (globalCD, userCD)

        case "!last", "!lastsong", "!prevsong":
            let globalCD = defaults.object(forKey: AppConstants.UserDefaults.lastSongCommandGlobalCooldown) as? TimeInterval
                ?? command.globalCooldown
            let userCD = defaults.object(forKey: AppConstants.UserDefaults.lastSongCommandUserCooldown) as? TimeInterval
                ?? command.userCooldown
            return (globalCD, userCD)

        default:
            return (command.globalCooldown, command.userCooldown)
        }
    }
}
