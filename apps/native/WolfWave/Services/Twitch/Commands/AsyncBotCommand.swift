//
//  AsyncBotCommand.swift
//  WolfWave
//
//  Created by Nathanial Henniges on 2026-04-15.
//  Copyright © 2026 MrDemonWolf, Inc. All rights reserved.
//

import Foundation

/// A bot command that performs async work and replies via callback.
///
/// Unlike `BotCommand.execute(message:)` which returns synchronously,
/// async commands can perform network requests (e.g., searching Apple Music)
/// and call `reply` when done. The sync `execute(message:)` returns nil
/// for async commands. The dispatcher skips it.
///
/// Example:
/// ```swift
/// class SongRequestCommand: AsyncBotCommand {
///     func execute(message: String, context: BotCommandContext, reply: @escaping (String) -> Void) {
///         // Search Apple Music asynchronously...
///         reply("Added \"Bohemian Rhapsody\" by Queen, #3 in queue")
///     }
/// }
/// ```
protocol AsyncBotCommand: BotCommand {
    /// Execute the command with user context, replying asynchronously.
    ///
    /// - Parameters:
    ///   - message: The full chat message text.
    ///   - context: Information about the sender (username, badges, etc.).
    ///   - reply: Callback to send the response message back to chat.
    func execute(message: String, context: BotCommandContext, reply: @escaping (String) -> Void)
}

// MARK: - Default Sync Execute

extension AsyncBotCommand {
    /// Default implementation of the sync `execute(message:)` from `BotCommand`.
    ///
    /// Async commands deliver their reply through the `reply` callback instead
    /// of a return value, so this overload always returns `nil`. The dispatcher
    /// recognizes `AsyncBotCommand` conformance and routes through the async
    /// overload.
    ///
    /// - Parameter message: Raw chat message (unused).
    /// - Returns: Always `nil`.
    func execute(message: String) -> String? {
        nil
    }
}
