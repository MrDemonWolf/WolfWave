//
//  AsyncBotCommand.swift
//  WolfWave
//
//  Created by Nathanial Henniges on 2026-04-15.
//  Copyright © 2026 MrDemonWolf, Inc. All rights reserved.
//

import Foundation

/// A bot command whose work participates in the caller's task.
///
/// Implementations return their eventual chat reply instead of spawning an
/// untracked Task or retaining a reply closure. The production dispatcher
/// awaits this method, so cancellation propagates from the active Twitch
/// receive session through command execution.
protocol AsyncBotCommand: BotCommand {
    /// Executes the command and returns the reply, or nil to stay silent.
    func execute(message: String, context: BotCommandContext) async -> String?
}

// MARK: - Sync Compatibility

extension AsyncBotCommand {
    /// Satisfies BotCommand for legacy sync-only dispatch and focused tests.
    ///
    /// A synchronous caller cannot safely block on async work, so it receives
    /// nil. Production always routes this conformance through
    /// BotCommandDispatcher.processMessageAsync.
    func execute(message: String) -> String? {
        nil
    }
}
