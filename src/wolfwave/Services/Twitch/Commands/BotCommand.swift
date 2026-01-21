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

    /// Execute the command and return the response message.
    /// Keep response time under 100ms for responsive chat experience.
    func execute(message: String) -> String?
}
