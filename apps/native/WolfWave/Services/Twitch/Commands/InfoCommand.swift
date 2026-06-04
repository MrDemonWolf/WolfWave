//
//  InfoCommand.swift
//  WolfWave
//
//  Created by Nathanial Henniges on 2026-06-03.
//  Copyright © 2026 MrDemonWolf, Inc. All rights reserved.
//

import Foundation

/// A bot command that replies with a fixed informational message.
///
/// Unlike `TrackInfoCommand`, the reply does not depend on playback state, so
/// there is no provider to wire from `AppDelegate`/`TwitchChatService`. The
/// message is resolved lazily via `messageProvider` at send time, letting the
/// reply reflect a user-selected style stored in UserDefaults (see
/// `WolfWaveReplyStyle`).
///
/// Enable state is read from `enabledDefaultsKey` via `Preferences.bool` with a
/// default of `false`, so the command is opt-in just like `!song` and `!last`.
/// The protocol's `enabledKey` (the gate the dispatcher checks) is intentionally
/// left at its `nil` default; the real gate lives in ``execute(message:)`` so an
/// unset key reads as *off* rather than the protocol's default-*on* behavior.
///
/// MainActor-isolated (project default). Every stored property is immutable and
/// set once at init, so no lock is needed.
final class InfoCommand: BotCommand {

    // MARK: - BotCommand

    let triggers: [String]
    let description: String
    let globalCooldownKey: String?
    let userCooldownKey: String?
    let aliasesKey: String?

    // MARK: - Private State

    /// UserDefaults key gating whether the command responds (default `false`).
    private let enabledDefaultsKey: String

    /// Resolves the reply text at send time.
    private let messageProvider: () -> String

    // MARK: - Init

    /// Creates a static-reply info command.
    ///
    /// - Parameters:
    ///   - triggers: Chat trigger strings (e.g. `["!wolfwave"]`).
    ///   - description: Human-readable description.
    ///   - enabledDefaultsKey: UserDefaults key gating the command; unset = off.
    ///   - globalCooldownKey: UserDefaults key for the global cooldown override.
    ///   - userCooldownKey: UserDefaults key for the per-user cooldown override.
    ///   - aliasesKey: UserDefaults key for comma-separated custom aliases.
    ///   - messageProvider: Resolves the reply text each time the command fires.
    init(
        triggers: [String],
        description: String,
        enabledDefaultsKey: String,
        globalCooldownKey: String? = nil,
        userCooldownKey: String? = nil,
        aliasesKey: String? = nil,
        messageProvider: @escaping () -> String
    ) {
        self.triggers = triggers
        self.description = description
        self.enabledDefaultsKey = enabledDefaultsKey
        self.globalCooldownKey = globalCooldownKey
        self.userCooldownKey = userCooldownKey
        self.aliasesKey = aliasesKey
        self.messageProvider = messageProvider
    }

    // MARK: - Execute

    /// Matches `message` against `allTriggers`, checks the enabled toggle, then
    /// returns the resolved reply truncated to Twitch's 500-character limit.
    ///
    /// - Parameter message: Raw chat message.
    /// - Returns: Chat response, or `nil` if no trigger matched or the command
    ///   is disabled.
    func execute(message: String) -> String? {
        let lowered = message.lowercased()
        let commandToken = lowered.split(whereSeparator: \.isWhitespace).first.map(String.init) ?? lowered

        guard allTriggers.contains(where: { commandToken == $0.lowercased() }) else {
            return nil
        }
        guard Preferences.bool(enabledDefaultsKey, default: false) else {
            return nil
        }
        return messageProvider().truncatedForChat()
    }
}
