//
//  AppConstants+Notifications.swift
//  WolfWave
//
//  Created by Nathanial Henniges on 2026-04-15.
//  Copyright © 2026 MrDemonWolf, Inc. All rights reserved.
//

import Foundation

/// Typed `NSNotification.Name` constants for all WolfWave notifications.
///
/// Use these instead of `NSNotification.Name(AppConstants.Notifications.xxx)` to eliminate
/// the verbose string-wrapping boilerplate at every call site.
///
/// Example:
/// ```swift
/// // Before
/// NotificationCenter.default.publisher(for: NSNotification.Name(AppConstants.Notifications.nowPlayingChanged))
/// // After
/// NotificationCenter.default.publisher(for: .nowPlayingChanged)
/// ```
extension NSNotification.Name {
    nonisolated static let trackingSettingChanged = NSNotification.Name(AppConstants.Notifications.trackingSettingChanged)
    nonisolated static let dockVisibilityChanged = NSNotification.Name(AppConstants.Notifications.dockVisibilityChanged)
    nonisolated static let twitchReauthNeededChanged = NSNotification.Name(AppConstants.Notifications.twitchReauthNeededChanged)
    nonisolated static let discordPresenceChanged = NSNotification.Name(AppConstants.Notifications.discordPresenceChanged)
    nonisolated static let discordStateChanged = NSNotification.Name(AppConstants.Notifications.discordStateChanged)
    nonisolated static let discordPresenceSettingsChanged = NSNotification.Name(AppConstants.Notifications.discordPresenceSettingsChanged)
    nonisolated static let nowPlayingChanged = NSNotification.Name(AppConstants.Notifications.nowPlayingChanged)
    nonisolated static let updateStateChanged = NSNotification.Name(AppConstants.Notifications.updateStateChanged)
    nonisolated static let websocketServerChanged = NSNotification.Name(AppConstants.Notifications.websocketServerChanged)
    nonisolated static let websocketServerStateChanged = NSNotification.Name(AppConstants.Notifications.websocketServerStateChanged)
    nonisolated static let websocketAuthTokenChanged = NSNotification.Name(AppConstants.Notifications.websocketAuthTokenChanged)
    nonisolated static let widgetHTTPServerChanged = NSNotification.Name(AppConstants.Notifications.widgetHTTPServerChanged)
    nonisolated static let powerStateChanged = NSNotification.Name(AppConstants.Notifications.powerStateChanged)
    nonisolated static let twitchConnectionStateChanged = NSNotification.Name(AppConstants.Notifications.twitchConnectionStateChanged)
    nonisolated static let songRequestSettingChanged = NSNotification.Name(AppConstants.Notifications.songRequestSettingChanged)
    nonisolated static let songRequestQueueChanged = NSNotification.Name(AppConstants.Notifications.songRequestQueueChanged)
    nonisolated static let songRequestHoldChanged = NSNotification.Name(AppConstants.Notifications.songRequestHoldChanged)
    nonisolated static let voteSkipStateChanged = NSNotification.Name(AppConstants.Notifications.voteSkipStateChanged)
    nonisolated static let musicPermissionDenied = NSNotification.Name(AppConstants.Notifications.musicPermissionDenied)
    nonisolated static let openSettingsSection = NSNotification.Name(AppConstants.Notifications.openSettingsSection)
    nonisolated static let openSettingsRequested = NSNotification.Name(AppConstants.Notifications.openSettingsRequested)
    nonisolated static let listeningHistorySettingChanged = NSNotification.Name(AppConstants.Notifications.listeningHistorySettingChanged)
    nonisolated static let streamerModeChanged = NSNotification.Name(AppConstants.Notifications.streamerModeChanged)
}

extension AppConstants {
    /// System notification names used throughout the application.
    ///
    /// These notifications are posted via NotificationCenter and observed by various components
    /// to maintain loose coupling between UI and service layers.
    nonisolated enum Notifications {
        /// Posted when the user toggles music tracking setting. UserInfo contains "enabled" Bool.
        static let trackingSettingChanged = "TrackingSettingChanged"

        /// Posted when the user changes dock visibility mode. UserInfo contains "mode" String.
        static let dockVisibilityChanged = "DockVisibilityChanged"

        /// Posted when Twitch re-authentication is needed (token expired or revoked).
        static let twitchReauthNeededChanged = "TwitchReauthNeededChanged"

        /// Posted when the user toggles Discord Rich Presence setting. UserInfo contains "enabled" Bool.
        static let discordPresenceChanged = "DiscordPresenceChanged"

        /// Posted when the Discord RPC connection state changes. UserInfo contains "state" String.
        static let discordStateChanged = "DiscordStateChanged"

        /// Posted when Discord Rich Presence display settings change (button labels, toggles, state format).
        /// Triggers an immediate re-send of the cached presence so changes appear without waiting for the next track.
        static let discordPresenceSettingsChanged = "DiscordPresenceSettingsChanged"

        /// Posted when now-playing track information changes. UserInfo contains track, artist, album.
        static let nowPlayingChanged = "NowPlayingChanged"

        /// Posted when Sparkle finds or completes an update check. UserInfo contains "isUpdateAvailable" Bool, "latestVersion" String.
        static let updateStateChanged = "UpdateStateChanged"

        /// Posted when the user toggles the WebSocket server or changes its port.
        static let websocketServerChanged = "WebSocketServerChanged"

        /// Posted when the WebSocket server connection state changes.
        static let websocketServerStateChanged = "WebSocketServerStateChanged"

        /// Posted after the overlay auth token is saved or regenerated, so every
        /// view holding a copy (e.g. the Browser Source URL card) re-reads it.
        static let websocketAuthTokenChanged = "WebSocketAuthTokenChanged"

        /// Posted when the widget HTTP server enabled state changes.
        static let widgetHTTPServerChanged = "WidgetHTTPServerChanged"

        /// Posted when system power state changes (Low Power Mode or thermal pressure).
        static let powerStateChanged = "PowerStateChanged"

        /// Posted when Twitch chat connection state changes. UserInfo contains "isConnected" Bool.
        static let twitchConnectionStateChanged = "TwitchChatConnectionStateChanged"

        /// Posted when song request enabled state changes. UserInfo contains "enabled" Bool.
        static let songRequestSettingChanged = "SongRequestSettingChanged"

        /// Posted when the song request queue changes (add, remove, skip, clear).
        static let songRequestQueueChanged = "SongRequestQueueChanged"

        /// Posted when the song request hold state toggles.
        static let songRequestHoldChanged = "SongRequestHoldChanged"

        /// Posted when the chat vote-skip session state changes (vote cast, session opened/closed).
        /// UserInfo contains "count" Int and "needed" Int when a session is active.
        static let voteSkipStateChanged = "VoteSkipStateChanged"

        /// Posted when the user toggles Listening History. UserInfo contains "enabled" Bool.
        static let listeningHistorySettingChanged = "ListeningHistorySettingChanged"

        /// Posted when the user toggles Streamer Mode from the tray menu. UserInfo contains "enabled" Bool.
        static let streamerModeChanged = "StreamerModeChanged"

        /// Posted when the playback data path detects Apple Music Automation is denied
        /// (e.g., Music is running but ScriptingBridge reads return nil). Lets the
        /// Music Monitor settings view flip to the denied banner without waiting for
        /// the next `AEDeterminePermissionToAutomateTarget` poll.
        static let musicPermissionDenied = "MusicPermissionDenied"

        /// Posted to request that the Settings window switch to a specific sidebar
        /// section. UserInfo contains "section" String matching `SettingsView.SettingsSection.rawValue`.
        static let openSettingsSection = "OpenSettingsSection"

        /// Posted by AppKit entry points (tray menu, Dock menu, Dock reopen, Twitch
        /// re-auth) to ask the live SwiftUI scene tree (`SettingsSceneBridge`) to
        /// open the `Settings` scene via `@Environment(\.openSettings)`. Replaces the
        /// private `showSettingsWindow:` selector path that logged "Please use
        /// SettingsLink for opening the Settings scene" on macOS 14+.
        static let openSettingsRequested = "OpenSettingsRequested"

        /// All notification names, used by the DEBUG-only notification firehose.
        static let allNames: [String] = [
            trackingSettingChanged,
            dockVisibilityChanged,
            twitchReauthNeededChanged,
            discordPresenceChanged,
            discordPresenceSettingsChanged,
            discordStateChanged,
            nowPlayingChanged,
            updateStateChanged,
            websocketServerChanged,
            websocketServerStateChanged,
            websocketAuthTokenChanged,
            widgetHTTPServerChanged,
            powerStateChanged,
            twitchConnectionStateChanged,
            songRequestSettingChanged,
            songRequestQueueChanged,
            songRequestHoldChanged,
            voteSkipStateChanged,
            listeningHistorySettingChanged,
            musicPermissionDenied,
            streamerModeChanged,
            openSettingsSection,
            openSettingsRequested,
        ]
    }
}
