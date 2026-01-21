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
/// Thread-safe for concurrent access from any thread.
final class BotCommandDispatcher {
    private var commands: [BotCommand] = []

    init() {
        registerDefaultCommands()
    }

    private func registerDefaultCommands() {
        let songCommand = SongCommand()
        let lastSongCommand = LastSongCommand()
        register(songCommand)
        register(lastSongCommand)
    }

    func register(_ command: BotCommand) {
        commands.append(command)
    }

    func setCurrentSongInfo(callback: @escaping () -> String) {
        for command in commands {
            if let songCmd = command as? SongCommand {
                songCmd.getCurrentSongInfo = callback
            }
        }
    }

    func setLastSongInfo(callback: @escaping () -> String) {
        for command in commands {
            if let lastSongCmd = command as? LastSongCommand {
                lastSongCmd.getLastSongInfo = callback
            }
        }
    }
    
    func setCurrentSongCommandEnabled(callback: @escaping () -> Bool) {
        for command in commands {
            if let songCmd = command as? SongCommand {
                songCmd.isEnabled = callback
            }
        }
    }
    
    func setLastSongCommandEnabled(callback: @escaping () -> Bool) {
        for command in commands {
            if let lastSongCmd = command as? LastSongCommand {
                lastSongCmd.isEnabled = callback
            }
        }
    }

    func processMessage(_ message: String) -> String? {
        let trimmedMessage = message.trimmingCharacters(in: .whitespaces)
        
        guard !trimmedMessage.isEmpty, trimmedMessage.count <= 500 else {
            return nil
        }

        for command in commands {
            if let response = command.execute(message: trimmedMessage) {
                Log.debug("Command '\(trimmedMessage.prefix(50))' executed", category: "BotCommands")
                return response
            }
        }

        return nil
    }
}
