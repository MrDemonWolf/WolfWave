//
//  AsyncBotCommand.swift
//  wolfwave
//
//  Created by MrDemonWolf, Inc. on 4/8/26.
//

import Foundation

/// A bot command that performs async work and replies via callback.
///
/// Unlike `BotCommand.execute(message:)` which returns synchronously,
/// async commands can perform network requests (e.g., searching Apple Music)
/// and call `reply` when done. The sync `execute(message:)` returns nil
/// for async commands — the dispatcher skips it.
///
/// Example:
/// ```swift
/// class SongRequestCommand: AsyncBotCommand {
///     func execute(message: String, context: BotCommandContext, reply: @escaping (String) -> Void) {
///         // Search Apple Music asynchronously...
///         reply("Added \"Bohemian Rhapsody\" by Queen — #3 in queue")
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

extension AsyncBotCommand {
    /// Sync execute returns nil — async commands use the reply callback instead.
    func execute(message: String) -> String? {
        nil
    }
}
