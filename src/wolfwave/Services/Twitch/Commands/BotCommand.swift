//
//  BotCommand.swift
//  wolfwave
//
//  Created by MrDemonWolf, Inc. on 1/8/26.
//

import Foundation

/// Protocol defining the interface for Twitch bot commands.
protocol BotCommand {
    /// The command trigger(s) that activate this command (e.g., ["!song", "!currentsong"])
    var triggers: [String] { get }

    /// Description of what the command does
    var description: String { get }

    /// Execute the command and return the response message
    func execute(message: String) -> String?
}
