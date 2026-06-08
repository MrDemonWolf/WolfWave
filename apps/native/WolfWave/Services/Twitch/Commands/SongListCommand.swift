//
//  SongListCommand.swift
//  WolfWave
//
//  Created by Nathanial Henniges on 2026-06-08.
//  Copyright © 2026 MrDemonWolf, Inc. All rights reserved.
//

import Foundation

/// Handles `!playlist`: posts a link to the streamer's song request playlist.
///
/// WolfWave adds requested songs to a `WolfWave Requests` library playlist, but
/// macOS can't publish a library playlist or fetch its public share URL via the
/// Apple Music API. So the streamer shares that playlist once (Music.app →
/// right-click → Share → Copy Link) and pastes the link into Settings
/// (`songRequestSongListURL`); this command echoes it to chat.
///
/// Opt-in and gated internally on `songListCommandEnabled` (default `false`),
/// mirroring `InfoCommand`: the protocol's `enabledKey` is left `nil` (which the
/// dispatcher treats as always-on) so the real gate lives here and an unset key
/// reads as *off*. Stays silent when no link is configured.
///
/// `!songlist` is intentionally not a trigger here: it already belongs to
/// `QueueCommand` (the in-chat text queue). The default trigger is `!playlist`;
/// streamers can add their own via the alias field.
final class SongListCommand: BotCommand {

    // MARK: - BotCommand

    var triggers: [String] { ["!playlist"] }

    var description: String { "Links the song request playlist" }

    var aliasesKey: String? { AppConstants.UserDefaults.songListCommandAliases }

    // MARK: - Execute

    /// Matches `message` against `allTriggers`, checks the enabled toggle, then
    /// returns the configured playlist link truncated to Twitch's 500-character
    /// limit.
    ///
    /// - Parameter message: Raw chat message.
    /// - Returns: The chat response, or `nil` when no trigger matched, the command
    ///   is disabled, or no link has been configured yet.
    func execute(message: String) -> String? {
        let lowered = message.lowercased()
        let commandToken = lowered.split(whereSeparator: \.isWhitespace).first.map(String.init) ?? lowered

        guard allTriggers.contains(where: { commandToken == $0.lowercased() }) else {
            return nil
        }
        guard Preferences.bool(AppConstants.UserDefaults.songListCommandEnabled, default: false) else {
            return nil
        }
        let link = Foundation.UserDefaults.standard
            .string(forKey: AppConstants.UserDefaults.songRequestSongListURL)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !link.isEmpty else {
            return nil
        }
        return "Song list: \(link)".truncatedForChat()
    }
}
