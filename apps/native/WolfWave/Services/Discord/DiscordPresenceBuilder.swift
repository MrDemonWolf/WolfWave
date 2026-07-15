//
//  DiscordPresenceBuilder.swift
//  WolfWave
//
//  Created by Nathanial Henniges on 2026-02-07.
//  Copyright © 2026 MrDemonWolf, Inc. All rights reserved.
//

import Foundation

// MARK: - Discord Presence Builder

/// Pure, side-effect-free builders for the Discord Rich Presence `activity`
/// payloads. Extracted from ``DiscordRPCService`` so the socket actor stays
/// focused on I/O while these deterministic helpers can be unit-tested directly.
///
/// The type is `nonisolated` (matching ``DiscordPlaylistStyle``) so its statics
/// stay callable synchronously from the ``DiscordRPCService`` actor executor,
/// not the MainActor default.
nonisolated enum DiscordPresenceBuilder {

    // MARK: - Payload Builder (internal for testing)

    /// Builds the Discord `activity` payload dictionary from track metadata + user settings.
    ///
    /// Pure function. No socket I/O, no instance state. Exposed `internal` so unit
    /// tests can drive it directly with isolated `UserDefaults` suites.
    ///
    /// - Parameters:
    ///   - playlist: Current Apple Music playlist name (empty if none / unknown).
    ///   - now: Injected clock for deterministic timestamps in tests.
    static func buildActivity(
        track: String,
        artist: String,
        album: String,
        playlist: String = "",
        artworkURL: String?,
        duration: TimeInterval,
        elapsed: TimeInterval,
        appleMusicURL: String?,
        songLinkURL: String?,
        isPaused: Bool = false,
        defaults: UserDefaults,
        now: Date
    ) -> [String: Any] {
        let playlistDisplay = resolvePlaylistDisplay(
            playlist: playlist, album: album, defaults: defaults
        )
        let style = DiscordPlaylistStyle.resolved(
            from: defaults.string(forKey: AppConstants.UserDefaults.discordPlaylistStyle)
        )

        var activity: [String: Any] = [
            "type": AppConstants.Discord.listeningActivityType,
            "details": track,
            "state": stateLine(artist: artist, playlist: playlistDisplay, style: style),
        ]

        let largeImage = artworkURL ?? AppConstants.Discord.artAssetAppleMusic
        // When paused: swap the small badge to the "pause" art asset (uploaded
        // to the Discord developer portal under Rich Presence > Art Assets) and
        // override the tooltip. Source-of-truth keeps `large_image` intact so
        // album art still shows.
        let smallImageKey = isPaused ? AppConstants.Discord.artAssetPause : AppConstants.Discord.artAssetAppleMusic
        let smallTextValue = isPaused ? "Paused" : smallText(playlist: playlistDisplay, style: style)
        activity["assets"] = [
            "large_image": largeImage,
            "large_text": album,
            "small_image": smallImageKey,
            "small_text": smallTextValue,
        ]

        // Discord has no native paused flag. Omitting `timestamps` stops the
        // live ticker on the client so it doesn't keep counting up past the
        // real elapsed value while the user is paused. Resumes will rebuild
        // the timestamps from the next non-paused update.
        if duration > 0 && !isPaused {
            let nowEpoch = now.timeIntervalSince1970
            let start = nowEpoch - elapsed
            let end = start + duration
            activity["timestamps"] = [
                "start": Int(start * 1000),
                "end": Int(end * 1000),
            ]
        }

        var buttons: [[String: String]] = []
        if let btn = resolveButton(index: 1, url: appleMusicURL, defaults: defaults) {
            buttons.append(btn)
        }
        if let btn = resolveButton(index: 2, url: songLinkURL, defaults: defaults) {
            buttons.append(btn)
        }
        if !buttons.isEmpty {
            activity["buttons"] = buttons
        }

        return activity
    }

    /// Builds the minimal opt-in "Idle" activity payload (no track, timestamps,
    /// or buttons). Pure function. No socket I/O, no instance state. Exposed
    /// `internal` so unit tests can assert its shape.
    static func buildIdleActivity() -> [String: Any] {
        // Large image is the WolfWave logo (not the Apple Music note) so the
        // idle marker is visually distinct from active playback, with Apple
        // Music demoted to the small source badge. Requires the `wolfwave` art
        // asset to be uploaded to the Discord portal.
        [
            "type": AppConstants.Discord.listeningActivityType,
            "details": AppConstants.Discord.idleDetails,
            "state": AppConstants.Discord.idleState,
            "assets": [
                "large_image": AppConstants.Discord.artAssetWolfWave,
                "large_text": "WolfWave",
                "small_image": AppConstants.Discord.artAssetAppleMusic,
                "small_text": AppConstants.Discord.idleSmallText,
            ],
        ]
    }

    /// Resolves a button payload from settings + a candidate URL.
    ///
    /// Returns nil when the user disabled the button, the URL is missing, or the
    /// label resolves to empty after trimming. Custom labels override defaults;
    /// empty stored label means "use the default". Labels are trimmed and
    /// truncated to `buttonLabelMaxLength` defensively.
    ///
    /// - Parameter index: 1 or 2.
    static func resolveButton(
        index: Int,
        url: String?,
        defaults: UserDefaults
    ) -> [String: String]? {
        guard let url, !url.isEmpty else { return nil }
        guard let keys = buttonKeys(for: index) else { return nil }

        // Missing key defaults to enabled (true).
        let enabled = (defaults.object(forKey: keys.enabled) as? Bool) ?? true
        guard enabled else { return nil }

        let stored = (defaults.string(forKey: keys.label) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let resolved = stored.isEmpty ? keys.defaultLabel : stored
        let truncated = String(resolved.prefix(AppConstants.Discord.buttonLabelMaxLength))
        guard !truncated.isEmpty else { return nil }

        return ["label": truncated, "url": url]
    }

    /// Maps a button index to its enabled/label `UserDefaults` keys and default
    /// label. Returns nil for any index other than 1 or 2.
    private static func buttonKeys(
        for index: Int
    ) -> (enabled: String, label: String, defaultLabel: String)? {
        switch index {
        case 1:
            return (
                AppConstants.UserDefaults.discordButton1Enabled,
                AppConstants.UserDefaults.discordButton1Label,
                AppConstants.Discord.defaultButton1Label
            )
        case 2:
            return (
                AppConstants.UserDefaults.discordButton2Enabled,
                AppConstants.UserDefaults.discordButton2Label,
                AppConstants.Discord.defaultButton2Label
            )
        default:
            return nil
        }
    }

    // MARK: - Playlist Resolution

    /// The outcome of resolving the current playlist for presence display.
    enum PlaylistDisplay: Equatable, Sendable {
        /// Show the playlist's real name.
        case named(String)
        /// A playlist is active but the user opted not to reveal its name.
        case anonymous
    }

    /// Resolves how the current playlist should be displayed, or `nil` to hide it.
    ///
    /// Returns `nil` when the playlist feature is disabled, the name is empty, a
    /// generic container (`Library` / `Music` / `Apple Music`), or identical to
    /// the album, so the card never surfaces a non-playlist as a playlist.
    /// When `discordPlaylistShowName` is off, returns `.anonymous` so the
    /// listening context survives without leaking the playlist's name.
    static func resolvePlaylistDisplay(
        playlist: String,
        album: String,
        defaults: UserDefaults
    ) -> PlaylistDisplay? {
        guard defaults.bool(forKey: AppConstants.UserDefaults.discordPlaylistEnabled) else {
            return nil
        }

        let name = playlist.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return nil }

        let folded = name.lowercased()
        guard !AppConstants.Discord.genericPlaylistNames.contains(folded) else { return nil }
        guard folded != album.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() else {
            return nil
        }

        // Missing key defaults to revealing the name (true).
        let showName = (defaults.object(forKey: AppConstants.UserDefaults.discordPlaylistShowName) as? Bool) ?? true
        return showName ? .named(name) : .anonymous
    }

    /// Builds the activity `state` line, appending the playlist for `.artistLine` style.
    static func stateLine(
        artist: String,
        playlist: PlaylistDisplay?,
        style: DiscordPlaylistStyle
    ) -> String {
        let cap = AppConstants.Discord.activityTextMaxLength
        guard style == .artistLine, let playlist else {
            return String(artist.prefix(cap))
        }
        let label: String
        switch playlist {
        case .named(let name): label = name
        case .anonymous:       label = AppConstants.Discord.playlistAnonymousLabel
        }
        let joined = artist.isEmpty
            ? label
            : artist + AppConstants.Discord.playlistSeparator + label
        return String(joined.prefix(cap))
    }

    /// Builds the small-icon tooltip text, describing the playlist for `.iconTooltip` style.
    static func smallText(
        playlist: PlaylistDisplay?,
        style: DiscordPlaylistStyle
    ) -> String {
        guard style == .iconTooltip, let playlist else { return "Apple Music" }
        switch playlist {
        case .named(let name):
            let text = AppConstants.Discord.playlistTooltipPrefix
                + AppConstants.Discord.playlistSeparator + name
            return String(text.prefix(AppConstants.Discord.activityTextMaxLength))
        case .anonymous:
            return AppConstants.Discord.playlistAnonymousTooltip
        }
    }
}
