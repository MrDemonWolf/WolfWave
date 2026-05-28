//
//  BotCommandContext.swift
//  WolfWave
//
//  Created by Nathanial Henniges on 2026-04-15.
//  Copyright © 2026 MrDemonWolf, Inc. All rights reserved.
//

import Foundation

/// Context about the Twitch chat user who triggered a bot command.
///
/// Passed to `AsyncBotCommand` implementations so they can make decisions
/// based on who sent the message (e.g., mod-only commands, per-user limits).
///
/// Declared `nonisolated` so non-MainActor consumers (e.g. the `SkipVoteManager`
/// actor) can read the fields without crossing into MainActor.
nonisolated struct BotCommandContext: Sendable {

    // MARK: - Properties

    /// Twitch user ID of the sender (numeric string, immutable).
    ///
    /// - Note: Redacted in logs via `Logger`. Do not include in chat replies.
    let userID: String

    /// Twitch display name of the sender (may include localized capitalization).
    let username: String

    /// Whether the sender has a moderator badge in this channel.
    let isModerator: Bool

    /// Whether the sender is the channel broadcaster.
    let isBroadcaster: Bool

    /// Whether the sender has a subscriber badge in this channel.
    let isSubscriber: Bool

    /// Whether the sender has a VIP badge in this channel.
    let isVIP: Bool

    /// The Twitch chat message ID. Used to send threaded replies via the
    /// Helix Send Chat Message endpoint.
    let messageID: String

    // MARK: - Computed

    /// Whether this sender has elevated privileges — moderator or broadcaster.
    ///
    /// Used by commands like `!skip` and `!clearqueue` that gate on mod status.
    var isPrivileged: Bool {
        isModerator || isBroadcaster
    }
}
