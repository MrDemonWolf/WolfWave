//
//  CooldownManager.swift
//  wolfwave
//
//  Created by MrDemonWolf, Inc. on 2/17/26.
//

import Foundation

// MARK: - Cooldown Manager

/// Manages global and per-user cooldowns for bot commands.
///
/// Tracks last-use timestamps per command (global) and per user+command to prevent
/// command spam in Twitch chat. Moderators can bypass cooldowns.
///
/// Thread Safety: All operations are protected by NSLock.
final class CooldownManager {

    // MARK: - Properties

    /// Global cooldowns: key = command trigger, value = last use timestamp.
    private var globalCooldowns: [String: Date] = [:]

    /// Per-user cooldowns: key = "userID:trigger", value = last use timestamp.
    private var userCooldowns: [String: Date] = [:]

    /// Lock protecting all cooldown state.
    private let lock = NSLock()

    // MARK: - Public API

    /// Checks whether a command is on cooldown for the given context.
    ///
    /// - Parameters:
    ///   - trigger: The command trigger string (e.g., "!song").
    ///   - userID: The Twitch user ID of the caller.
    ///   - isModerator: Whether the user has moderator badge (bypasses cooldowns).
    ///   - globalCooldown: Global cooldown duration in seconds (0 = disabled).
    ///   - userCooldown: Per-user cooldown duration in seconds (0 = disabled).
    /// - Returns: `true` if the command is on cooldown and should be skipped.
    func isOnCooldown(
        trigger: String,
        userID: String,
        isModerator: Bool,
        globalCooldown: TimeInterval,
        userCooldown: TimeInterval
    ) -> Bool {
        // Moderators bypass all cooldowns
        if isModerator { return false }

        let now = Date()

        return lock.withLock {
            // Check global cooldown
            if globalCooldown > 0, let lastGlobal = globalCooldowns[trigger] {
                if now.timeIntervalSince(lastGlobal) < globalCooldown {
                    return true
                }
            }

            // Check per-user cooldown
            if userCooldown > 0 {
                let userKey = "\(userID):\(trigger)"
                if let lastUser = userCooldowns[userKey] {
                    if now.timeIntervalSince(lastUser) < userCooldown {
                        return true
                    }
                }
            }

            return false
        }
    }

    /// Records a command use for cooldown tracking.
    ///
    /// - Parameters:
    ///   - trigger: The command trigger string.
    ///   - userID: The Twitch user ID of the caller.
    func recordUse(trigger: String, userID: String) {
        let now = Date()
        let userKey = "\(userID):\(trigger)"

        lock.withLock {
            globalCooldowns[trigger] = now
            userCooldowns[userKey] = now
        }
    }

    /// Clears all cooldown state (e.g., on disconnect).
    func reset() {
        lock.withLock {
            globalCooldowns.removeAll()
            userCooldowns.removeAll()
        }
    }
}
