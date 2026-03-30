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
            pruneExpiredCooldownsIfNeeded()
        }
    }

    // MARK: - Private Helpers

    /// Prunes expired per-user cooldown entries to prevent unbounded memory growth.
    ///
    /// Only runs when the dictionary exceeds 100 entries. Removes entries older
    /// than the maximum cooldown duration (5 minutes).
    /// Must be called while holding `lock`.
    private func pruneExpiredCooldownsIfNeeded() {
        guard userCooldowns.count > 100 else { return }
        let maxAge: TimeInterval = 300  // 5 minutes
        let cutoff = Date().addingTimeInterval(-maxAge)
        userCooldowns = userCooldowns.filter { $0.value > cutoff }
        globalCooldowns = globalCooldowns.filter { $0.value > cutoff }
    }

    /// Returns remaining cooldown times for debug logging.
    ///
    /// - Parameters:
    ///   - trigger: The command trigger string (canonical key).
    ///   - userID: The Twitch user ID of the caller.
    ///   - globalCooldown: Global cooldown duration in seconds.
    ///   - userCooldown: Per-user cooldown duration in seconds.
    /// - Returns: Tuple of remaining global and per-user cooldown seconds.
    func remainingCooldown(
        trigger: String,
        userID: String,
        globalCooldown: TimeInterval,
        userCooldown: TimeInterval
    ) -> (global: TimeInterval, perUser: TimeInterval) {
        let now = Date()
        return lock.withLock {
            let globalRemaining: TimeInterval
            if globalCooldown > 0, let lastGlobal = globalCooldowns[trigger] {
                globalRemaining = max(0, globalCooldown - now.timeIntervalSince(lastGlobal))
            } else {
                globalRemaining = 0
            }

            let perUserRemaining: TimeInterval
            if userCooldown > 0, let lastUser = userCooldowns["\(userID):\(trigger)"] {
                perUserRemaining = max(0, userCooldown - now.timeIntervalSince(lastUser))
            } else {
                perUserRemaining = 0
            }

            return (globalRemaining, perUserRemaining)
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
