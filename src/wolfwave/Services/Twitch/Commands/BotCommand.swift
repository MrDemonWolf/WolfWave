//
//  BotCommand.swift
//  wolfwave
//
//  Created by MrDemonWolf, Inc. on 1/17/26.
//

import Foundation

/// Protocol for Twitch bot command implementations.
///
/// Implementations must be thread-safe and validate input.
/// Maximum message response is 500 characters (enforced at dispatcher level).
protocol BotCommand {
    /// The command triggers that activate this command (e.g., ["!song", "!currentsong"]).
    /// Triggers are case-insensitive.
    var triggers: [String] { get }

    /// Description of what the command does.
    var description: String { get }

    /// Global cooldown in seconds between any uses of this command (0 = disabled).
    var globalCooldown: TimeInterval { get }

    /// Per-user cooldown in seconds between uses by the same user (0 = disabled).
    var userCooldown: TimeInterval { get }

    /// Execute the command and return the response message.
    /// Keep response time under 100ms for responsive chat experience.
    func execute(message: String) -> String?
}

// MARK: - Default Cooldown Values

extension BotCommand {
    /// Default global cooldown: 3 seconds between any uses.
    var globalCooldown: TimeInterval { 3.0 }

    /// Default per-user cooldown: 10 seconds between uses by the same user.
    var userCooldown: TimeInterval { 10.0 }
}
