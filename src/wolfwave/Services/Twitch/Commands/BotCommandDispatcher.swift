//
//  BotCommandDispatcher.swift
//  wolfwave
//
//  Created by MrDemonWolf, Inc. on 1/13/26.
//

import Foundation

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
        let lastSongCommand = LastSongCommand()
        register(songCommand)
        register(lastSongCommand)
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

    /// Set the last song info callback for last song commands
    func setLastSongInfo(callback: @escaping () -> String) {
        for command in commands {
            if let lastSongCmd = command as? LastSongCommand {
                lastSongCmd.getLastSongInfo = callback
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
