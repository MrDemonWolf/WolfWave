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
/// Thread-safe: all access to shared state is synchronized via `NSLock`.
final class BotCommandDispatcher {
    private var commands: [BotCommand] = []
    private let songCommand = SongCommand()
    private let lastSongCommand = LastSongCommand()
    private let lock = NSLock()

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

    func processMessage(_ message: String) -> String? {
        let trimmedMessage = message.trimmingCharacters(in: .whitespaces)

        guard !trimmedMessage.isEmpty, trimmedMessage.count <= 500 else {
            return nil
        }

        let snapshot = lock.withLock { commands }

        for command in snapshot {
            if let response = command.execute(message: trimmedMessage) {
                Log.debug("Command '\(trimmedMessage.prefix(50))' executed", category: "BotCommands")
                return response
            }
        }

        return nil
    }
}
