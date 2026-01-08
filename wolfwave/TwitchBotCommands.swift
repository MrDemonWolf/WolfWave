//
//  TwitchBotCommands.swift
//  wolfwave
//
//  Created by Nathanial Henniges on 1/8/26.
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

/// Command that responds with the currently playing song.
///
/// Triggers: !song, !currentsong, !nowplaying
final class SongCommand: BotCommand {
    let triggers = ["!song", "!currentsong", "!nowplaying"]
    let description = "Displays the currently playing track"
    
    /// Callback to get the current song information
    var getCurrentSongInfo: (() -> String)?
    
    func execute(message: String) -> String? {
        let trimmedMessage = message.trimmingCharacters(in: .whitespaces).lowercased()
        
        // Check if message starts with any of our triggers
        for trigger in triggers {
            if trimmedMessage.hasPrefix(trigger) {
                return getCurrentSongInfo?()
            }
        }
        
        return nil
    }
}

/// Dispatcher for routing messages to appropriate bot commands.
///
/// Manages a collection of bot commands and routes incoming chat messages
/// to the correct command handler based on the message content.
final class BotCommandDispatcher {
    private var commands: [BotCommand] = []
    
    init() {
        registerDefaultCommands()
    }
    
    /// Registers the default set of bot commands.
    private func registerDefaultCommands() {
        let songCommand = SongCommand()
        register(songCommand)
    }
    
    /// Register a new bot command
    func register(_ command: BotCommand) {
        commands.append(command)
    }
    
    /// Set the current song info callback for song-related commands
    func setCurrentSongInfo(callback: @escaping () -> String) {
        for command in commands {
            if let songCmd = command as? SongCommand {
                songCmd.getCurrentSongInfo = callback
            }
        }
    }
    
    /// Process a message and return a response if a command matches.
    ///
    /// - Parameter message: The incoming chat message
    /// - Returns: The command response, or nil if no command matched
    func processMessage(_ message: String) -> String? {
        let trimmedMessage = message.trimmingCharacters(in: .whitespaces)
        
        for command in commands {
            if let response = command.execute(message: trimmedMessage) {
                Log.debug("Twitch: Command executed", category: "BotCommands")
                return response
            }
        }
        
        return nil
    }
}
