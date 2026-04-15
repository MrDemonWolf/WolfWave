//
//  BotCommandContext.swift
//  wolfwave
//
//  Created by MrDemonWolf, Inc. on 4/8/26.
//

import Foundation

/// Context about the Twitch chat user who triggered a bot command.
///
/// Passed to `AsyncBotCommand` implementations so they can make decisions
/// based on who sent the message (e.g., mod-only commands, per-user limits).
struct BotCommandContext {
    /// Twitch user ID of the sender.
    let userID: String

    /// Twitch display name of the sender.
    let username: String

    /// Whether the sender has a moderator badge.
    let isModerator: Bool

    /// Whether the sender is the channel broadcaster.
    let isBroadcaster: Bool

    /// Whether the sender has a subscriber badge.
    let isSubscriber: Bool

    /// The Twitch message ID (used for reply threading).
    let messageID: String

    /// Whether this user has elevated privileges (mod or broadcaster).
    var isPrivileged: Bool {
        isModerator || isBroadcaster
    }
}
