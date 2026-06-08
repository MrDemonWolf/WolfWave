//
//  AppConstants.swift
//  WolfWave
//
//  Created by Nathanial Henniges on 2026-01-14.
//  Copyright © 2026 MrDemonWolf, Inc. All rights reserved.
//

/// Centralized configuration and constants for the WolfWave application.
///
/// Provides single source of truth for app identifiers, notification names, UserDefaults keys,
/// UI dimensions, timing values, and other configuration constants used throughout the app.
///
/// All values are static and immutable, organized into logical enum namespaces for clarity.
import Foundation
import AppKit
import SwiftUI

nonisolated enum AppConstants {
    // MARK: - Info.plist Helper

    /// Reads a string from Info.plist, trims whitespace, treats the literal
    /// `$(KEY)` placeholder as missing, then falls back to the environment
    /// variable of the same name, then to `fallback`.
    ///
    /// Used to source brand- and fork-configurable values from
    /// `Config.xcconfig` (expanded into Info.plist at build time) while
    /// keeping a sane default baked into the binary.
    static func infoPlistString(_ key: String, fallback: String) -> String {
        infoPlistString(
            key,
            fallback: fallback,
            plistLookup: { Bundle.main.object(forInfoDictionaryKey: $0) as? String },
            envLookup: { ProcessInfo.processInfo.environment[$0] }
        )
    }

    /// Testable variant: takes injectable Info.plist and environment lookups.
    static func infoPlistString(
        _ key: String,
        fallback: String,
        plistLookup: (String) -> String?,
        envLookup: (String) -> String?
    ) -> String {
        if let plistValue = plistLookup(key) {
            let trimmed = plistValue.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty, trimmed != "$(\(key))" {
                return trimmed
            }
        }
        if let env = envLookup(key) {
            let trimmed = env.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { return trimmed }
        }
        return fallback
    }

    // MARK: - App Identifiers

    /// Application bundle and display information.
    enum AppInfo {
        static let bundleIdentifier = "com.mrdemonwolf.wolfwave"

        /// User-facing app name. Reads `CFBundleDisplayName` (set in Info.plist
        /// and overridden per build configuration via `PRODUCT_NAME` /
        /// `Config.Debug.xcconfig`). Forks rename by editing those.
        static let displayName = infoPlistString(
            "CFBundleDisplayName",
            fallback: "WolfWave"
        )

        /// Legal entity shown in About + Monthly Wrap footers.
        /// Override via `COPYRIGHT_HOLDER` in `Config.xcconfig`.
        static let copyrightHolder = infoPlistString(
            "COPYRIGHT_HOLDER",
            fallback: "MrDemonWolf, Inc."
        )

        /// Marketing version string (`CFBundleShortVersionString`) with a safe
        /// fallback for contexts where the Info.plist key is absent (e.g. unit
        /// test hosts or a stripped bundle).
        static let shortVersion = infoPlistString(
            "CFBundleShortVersionString",
            fallback: "0.0.0"
        )

        /// Canonical public source repository URL. Casing matches the docs
        /// `repoUrl` constant (`apps/docs/lib/site.ts`).
        static let repositoryURL = "https://github.com/MrDemonWolf/WolfWave"

        /// Default outbound `User-Agent` for HTTP requests, honestly identifying
        /// the app and version: `WolfWave/<version> (+<repo URL>; macOS)`.
        ///
        /// Computed once from the bundle so every request carries the same
        /// string. Callers may still override `User-Agent` per request.
        static let userAgent = "WolfWave/\(shortVersion) (+\(repositoryURL); macOS)"
    }
    
    // MARK: - Notifications
    
    /// System notification names used throughout the application.
    ///
    /// These notifications are posted via NotificationCenter and observed by various components
    /// to maintain loose coupling between UI and service layers.
    enum Notifications {
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
            discordStateChanged,
            nowPlayingChanged,
            updateStateChanged,
            websocketServerChanged,
            websocketServerStateChanged,
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

    // MARK: - User Notifications

    /// Identifiers for macOS User Notifications posted via `NotificationService`.
    enum UserNotification {
        /// Stable identifier for the song-change notification. Reused on every
        /// track change so a new song replaces the previous notification in
        /// Notification Center rather than stacking.
        static let songChangeIdentifier = "com.mrdemonwolf.wolfwave.notification.songChange"

        /// Stable identifier for the skip-vote-started notification (chat tally or
        /// Twitch poll). Reused so a fresh vote-start replaces the previous one.
        static let skipVoteStartedIdentifier = "com.mrdemonwolf.wolfwave.notification.skipVoteStarted"

        /// Stable identifier for the skip-vote-passed notification.
        static let skipVotePassedIdentifier = "com.mrdemonwolf.wolfwave.notification.skipVotePassed"
    }

    // MARK: - UserDefaults Keys
    
    /// Keys for persisting user preferences in UserDefaults.
    ///
    /// Usage: `@AppStorage(AppConstants.UserDefaults.trackingEnabled)`
    enum UserDefaults {
        /// Whether Apple Music monitoring is enabled (Bool, default: true)
        static let trackingEnabled = "trackingEnabled"

        /// Last definitively-resolved Music automation permission ("granted"/"denied").
        /// Persisted so a closed Music.app (where the Apple Events probe returns
        /// `procNotFound` instead of the real TCC decision) falls back to the last
        /// known grant instead of masquerading as "unknown". (String, optional)
        static let lastResolvedMusicPermission = "lastResolvedMusicPermission"

        /// Set true at launch when `CrashReporter` finds a breadcrumb from the
        /// previous run, so the Advanced pane can surface a quiet "recovered from
        /// a crash" callout. Cleared when the user dismisses it or files a bug.
        /// Per-install runtime state, never exported. (Bool, default: false)
        static let lastLaunchCrashed = "lastLaunchCrashed"

        /// Dock visibility mode: "menuOnly", "dockOnly", or "both" (String, default: "both")
        static let dockVisibility = "dockVisibility"
        
        /// Whether Twitch re-authentication is required (Bool, default: false)
        static let twitchReauthNeeded = "twitchReauthNeeded"

        /// Connected Twitch channel/login name shown in the menu bar status line (String)
        static let twitchChannelName = "twitchChannelName"
        
        /// Settings section to open next time (String, "twitchIntegration", etc.)
        static let selectedSettingsSection = "selectedSettingsSection"
        
        /// Whether WebSocket integration is enabled (Bool, default: false)
        static let websocketEnabled = "websocketEnabled"

        /// Whether "current song" bot command is enabled (Bool, default: false)
        static let currentSongCommandEnabled = "currentSongCommandEnabled"

        /// Whether "last song" bot command is enabled (Bool, default: false)
        static let lastSongCommandEnabled = "lastSongCommandEnabled"

        /// Whether ALL chat commands reply only while the stream is live.
        /// When `true`, every bot command (incl. `!stats`) stays silent until a
        /// `stream.online` EventSub event (or Helix seed) marks the stream live.
        /// When `false`, commands respond regardless of live state (Bool, default: false).
        static let commandsLiveOnly = "commandsLiveOnly"

        /// Whether !song / !last replies include a song.link URL (Bool, default: false)
        static let songCommandSongLinkEnabled = "songCommandSongLinkEnabled"

        /// Whether the first-launch onboarding wizard has been completed (Bool, default: false)
        static let hasCompletedOnboarding = "hasCompletedOnboarding"

        /// Whether Discord Rich Presence is enabled (Bool, default: false)
        static let discordPresenceEnabled = "discordPresenceEnabled"

        /// Whether Discord presence button 1 (Apple Music link) is sent (Bool, default: true)
        static let discordButton1Enabled = "discordButton1Enabled"

        /// User-overridden label for Discord button 1. Empty string = use `AppConstants.Discord.defaultButton1Label`.
        static let discordButton1Label = "discordButton1Label"

        /// Whether Discord presence button 2 (song.link / cross-service) is sent (Bool, default: true)
        static let discordButton2Enabled = "discordButton2Enabled"

        /// User-overridden label for Discord button 2. Empty string = use `AppConstants.Discord.defaultButton2Label`.
        static let discordButton2Label = "discordButton2Label"

        /// Master switch: whether any profile buttons are shown on Discord (Bool, default: true)
        static let discordButtonsEnabled = "discordButtonsEnabled"

        /// Whether the current Apple Music playlist is shown in Discord presence (Bool, default: false)
        static let discordPlaylistEnabled = "discordPlaylistEnabled"

        /// Whether the playlist's actual name is revealed (Bool, default: true).
        /// When false, a generic label is shown instead so the name stays private.
        static let discordPlaylistShowName = "discordPlaylistShowName"

        /// How the playlist is displayed in Discord presence: `DiscordPlaylistStyle` raw value (String, default: "artistLine")
        static let discordPlaylistStyle = "discordPlaylistStyle"

        /// Whether WolfWave shows an "Idle" Discord activity when nothing is
        /// playing instead of clearing the profile (Bool, default: false).
        static let discordShowIdleStatus = "discordShowIdleStatus"

        /// Whether Discord presence is cleared while playback is paused, rather
        /// than keeping the loaded track on the profile (Bool, default: false).
        static let discordClearWhilePaused = "discordClearWhilePaused"

        /// Whether the app should launch at login (Bool, default: false)
        static let launchAtLogin = "launchAtLogin"

        /// WebSocket server port number (UInt16, default: 8765)
        static let websocketServerPort = "websocketServerPort"

        /// Whether automatic update checking is enabled via Sparkle (Bool, default: true)
        static let updateCheckEnabled = "updateCheckEnabled"

        /// Version string the user has chosen to skip (String)
        static let updateSkippedVersion = "updateSkippedVersion"

        /// Last app version the user has seen the What's New sheet for (String)
        static let lastSeenWhatsNewVersion = "lastSeenWhatsNewVersion"


        /// Global cooldown for !song command in seconds (Double, default: 15.0)
        static let songCommandGlobalCooldown = "songCommandGlobalCooldown"

        /// Per-user cooldown for !song command in seconds (Double, default: 15.0)
        static let songCommandUserCooldown = "songCommandUserCooldown"

        /// Global cooldown for !last command in seconds (Double, default: 15.0)
        static let lastSongCommandGlobalCooldown = "lastSongCommandGlobalCooldown"

        /// Per-user cooldown for !last command in seconds (Double, default: 15.0)
        static let lastSongCommandUserCooldown = "lastSongCommandUserCooldown"

        /// Custom aliases for !song command (String, comma-separated)
        static let songCommandAliases = "songCommandAliases"

        /// Custom aliases for !last command (String, comma-separated)
        static let lastSongCommandAliases = "lastSongCommandAliases"

        // MARK: WolfWave Command Keys

        /// Whether the !wolfwave info command is enabled (Bool, default: false)
        static let wolfwaveCommandEnabled = "wolfwaveCommandEnabled"

        /// Global cooldown for the !wolfwave command in seconds (Double, default: 15.0)
        static let wolfwaveCommandGlobalCooldown = "wolfwaveCommandGlobalCooldown"

        /// Per-user cooldown for the !wolfwave command in seconds (Double, default: 15.0)
        static let wolfwaveCommandUserCooldown = "wolfwaveCommandUserCooldown"

        /// Custom aliases for the !wolfwave command (String, comma-separated)
        static let wolfwaveCommandAliases = "wolfwaveCommandAliases"

        /// Selected !wolfwave reply style raw value (String, default: "credit").
        /// Maps to `WolfWaveReplyStyle`.
        static let wolfwaveCommandReplyStyle = "wolfwaveCommandReplyStyle"

        /// Widget theme name (String, default: "Default")
        static let widgetTheme = "widgetTheme"

        /// Widget layout style (String, default: "Horizontal")
        static let widgetLayout = "widgetLayout"

        /// Widget primary text color hex (String, default: "#FFFFFF")
        static let widgetTextColor = "widgetTextColor"

        /// Widget background color hex (String, default: "#1A1A2E")
        static let widgetBackgroundColor = "widgetBackgroundColor"

        /// Widget font family (String, default: "System")
        static let widgetFontFamily = "widgetFontFamily"

        /// Widget HTTP server port number (UInt16, default: 8766)
        static let widgetPort = "widgetPort"

        /// Whether the widget HTTP server is enabled (Bool, default: false)
        static let widgetHTTPEnabled = "widgetHTTPEnabled"

        // MARK: Song Request Keys

        /// Whether song requests are globally enabled (Bool, default: false)
        static let songRequestEnabled = "songRequestEnabled"

        /// Maximum queue size (Int, default: 10)
        static let songRequestMaxQueueSize = "songRequestMaxQueueSize"

        /// Per-user request limit (Int, default: 2)
        static let songRequestPerUserLimit = "songRequestPerUserLimit"

        /// Whether song requests require a subscriber badge (Bool, default: false)
        static let songRequestSubscriberOnly = "songRequestSubscriberOnly"

        /// Whether auto-advance is enabled (Bool, default: true)
        static let songRequestAutoAdvance = "songRequestAutoAdvance"

        /// Whether Apple Music autoplay resumes when queue empties (Bool, default: true)
        static let songRequestAutoplayWhenEmpty = "songRequestAutoplayWhenEmpty"

        /// Whether !sr command is enabled (Bool, default: true)
        static let srCommandEnabled = "srCommandEnabled"

        /// Whether !queue command is enabled (Bool, default: true)
        static let queueCommandEnabled = "queueCommandEnabled"

        /// Whether !myqueue command is enabled (Bool, default: true)
        static let myQueueCommandEnabled = "myQueueCommandEnabled"

        /// Whether !skip command is enabled (Bool, default: true)
        static let skipCommandEnabled = "skipCommandEnabled"

        /// Whether !clearqueue command is enabled (Bool, default: true)
        static let clearQueueCommandEnabled = "clearQueueCommandEnabled"

        /// Custom aliases for !sr command (String, comma-separated)
        static let srCommandAliases = "srCommandAliases"

        /// Custom aliases for !queue command (String, comma-separated)
        static let queueCommandAliases = "queueCommandAliases"

        /// Custom aliases for !myqueue command (String, comma-separated)
        static let myQueueCommandAliases = "myQueueCommandAliases"

        /// Custom aliases for !skip command (String, comma-separated)
        static let skipCommandAliases = "skipCommandAliases"

        /// Custom aliases for !clearqueue command (String, comma-separated)
        static let clearQueueCommandAliases = "clearQueueCommandAliases"

        /// Whether the !playlist link command is enabled (Bool, default: false)
        static let songListCommandEnabled = "songListCommandEnabled"

        /// Custom aliases for the !playlist command (String, comma-separated)
        static let songListCommandAliases = "songListCommandAliases"

        /// Public link to the song request playlist, posted by !playlist. macOS
        /// can't publish a library playlist or fetch its share URL via the API,
        /// so the streamer shares the `WolfWave Requests` playlist once and pastes
        /// the link here (String, default: "")
        static let songRequestSongListURL = "songRequestSongListURL"

        /// Global cooldown for song request commands in seconds (Double, default: 5.0)
        static let songRequestGlobalCooldown = "songRequestGlobalCooldown"

        /// Per-user cooldown for song request commands in seconds (Double, default: 30.0)
        static let songRequestUserCooldown = "songRequestUserCooldown"

        /// Name of the Apple Music playlist to play when the request queue is empty (String, default: "")
        static let songRequestFallbackPlaylist = "songRequestFallbackPlaylist"

        /// Whether song request auto-play is paused. Requests still queue but nothing plays (Bool, default: false)
        static let songRequestHoldEnabled = "songRequestHoldEnabled"

        /// Who may request via the !sr chat command: a `RequestAudience` raw value
        /// (String, default: "everyone"). Supersedes `songRequestSubscriberOnly`.
        static let songRequestChatAudience = "songRequestChatAudience"

        /// Whether channel-point song requests are enabled (Bool, default: false)
        static let songRequestChannelPointsEnabled = "songRequestChannelPointsEnabled"

        /// Channel-point cost of the WolfWave-managed "Request a Song" reward (Int, default: 500)
        static let songRequestChannelPointsCost = "songRequestChannelPointsCost"

        /// ID of the WolfWave-managed custom channel-point reward (String, default: "")
        static let songRequestChannelPointsRewardID = "songRequestChannelPointsRewardID"

        /// Whether bit-cheer song requests are enabled (Bool, default: false)
        static let songRequestBitsEnabled = "songRequestBitsEnabled"

        /// Minimum bits a cheer must include to trigger a song request (Int, default: 100)
        static let songRequestBitsMinimum = "songRequestBitsMinimum"

        /// Whether a bit cheer boosts the cheerer's already-queued song instead of
        /// adding a new one (Bool, default: false)
        static let songRequestBitsBoostEnabled = "songRequestBitsBoostEnabled"

        /// Health of the redemption integration: a `RedemptionStatus` raw value.
        /// Empty/"ok" when working; other values drive the settings re-auth banner
        /// (String, default: "ok").
        static let songRequestRedemptionStatus = "songRequestRedemptionStatus"

        /// Whether `!sr` replies "Song requests are off right now." when used while
        /// the feature is disabled. Off = stay silent (Bool, default: false).
        static let songRequestDisabledReplyEnabled = "songRequestDisabledReplyEnabled"

        /// Active request-policy preset: a `SongRequestPreset` raw value
        /// ("open", "subsOnly", "channelPointsOnly", "custom"). Drives the
        /// highlighted chip and whether the audience dropdown is revealed
        /// (String, default: "open").
        static let songRequestPolicyMode = "songRequestPolicyMode"

        /// How per-role queue limits combine: a `QueueLimitMode` raw value
        /// ("highest" = best tier the user holds; "stacked" = sum of all tiers
        /// they hold) (String, default: "highest").
        static let songRequestLimitStackMode = "songRequestLimitStackMode"

        /// Per-user queue limit contribution for subscribers (Int, default: 2).
        static let songRequestLimitSubscriber = "songRequestLimitSubscriber"

        /// Per-user queue limit contribution for VIPs (Int, default: 2).
        static let songRequestLimitVIP = "songRequestLimitVIP"

        /// Per-user queue limit contribution for moderators and the broadcaster
        /// (Int, default: 2).
        static let songRequestLimitModerator = "songRequestLimitModerator"

        // MARK: Chat Vote-Skip Keys

        /// Whether the chat vote-to-skip feature is enabled (Bool, default: false)
        static let voteSkipEnabled = "voteSkipEnabled"

        /// Minimum number of unique voters required to skip a song (Int, default: 3)
        static let voteSkipMinVotes = "voteSkipMinVotes"

        /// How long a vote session stays open before it fails, in seconds (Int, default: 60)
        static let voteSkipWindowSeconds = "voteSkipWindowSeconds"

        /// Cooldown between vote sessions, in seconds (Double, default: 30.0)
        static let voteSkipSessionCooldown = "voteSkipSessionCooldown"

        /// Whether only subscribers may cast vote-skip votes (Bool, default: false)
        static let voteSkipSubscriberOnly = "voteSkipSubscriberOnly"

        /// Whether the !voteskip command is enabled (Bool, default: true)
        static let voteSkipCommandEnabled = "voteSkipCommandEnabled"

        /// Custom aliases for the !voteskip command (String, comma-separated)
        static let voteSkipCommandAliases = "voteSkipCommandAliases"

        /// Whether vote-skip uses native Twitch Polls instead of a chat tally (Bool, default: false)
        static let voteSkipUsePolls = "voteSkipUsePolls"

        /// Duration of a Twitch poll created for vote-skip, in seconds (Int, default: 60; Twitch allows 15-1800)
        static let voteSkipPollDuration = "voteSkipPollDuration"

        /// Whether on-device MetricKit diagnostics collection is opted in (Bool, default: false)
        static let shareDiagnosticsEnabled = "shareDiagnosticsEnabled"

        /// Local count of app launches: anonymous, never transmitted (Int, default: 0)
        static let diagnosticsLaunchCount = "diagnosticsLaunchCount"

        /// Whether a macOS notification is posted when the song changes (Bool, default: false)
        static let songChangeNotificationsEnabled = "songChangeNotificationsEnabled"

        /// Whether a macOS notification is posted when a chat skip-vote starts (Bool, default: false)
        static let skipVoteStartedNotificationsEnabled = "skipVoteStartedNotificationsEnabled"

        /// Whether a macOS notification is posted when a chat skip-vote passes (Bool, default: false)
        static let skipVotePassedNotificationsEnabled = "skipVotePassedNotificationsEnabled"

        // MARK: Listening History & Stats Keys

        /// Whether the on-disk listening history log is being recorded (Bool, default: false, opt-in)
        static let listeningHistoryEnabled = "listeningHistoryEnabled"

        /// Whether the Stats & Charts UI is enabled. Requires `listeningHistoryEnabled` (Bool, default: false)
        static let statsEnabled = "statsEnabled"

        /// Whether the `!stats` Twitch command is enabled. Requires `statsEnabled` (Bool, default: false)
        static let statsCommandEnabled = "statsCommandEnabled"

        /// Global cooldown for the !stats command in seconds (Double, default: 15.0)
        static let statsCommandGlobalCooldown = "statsCommandGlobalCooldown"

        /// Per-user cooldown for the !stats command in seconds (Double, default: 15.0)
        static let statsCommandUserCooldown = "statsCommandUserCooldown"

        /// Custom aliases for the !stats command (String, comma-separated)
        static let statsCommandAliases = "statsCommandAliases"

        /// Which time window the `!stats` command reports. Maps to `StatsWindow`
        /// (String, default: "today")
        static let statsCommandWindow = "statsCommandWindow"

        /// Which facts the `!stats` command includes, comma-separated `StatsPart`
        /// raw values (String, default: "plays,topTrack")
        static let statsCommandParts = "statsCommandParts"

        /// Days of listening history to retain. 0 = keep everything (Int, default: 0)
        static let historyRetentionDays = "historyRetentionDays"

        /// Whether Streamer Mode is on: hides sensitive values (channel name, overlay URL,
        /// WebSocket URI, etc.) in the WolfWave UI so the app can be shown on stream.
        /// UI-only redaction; does not change broadcast/chat/Discord output (Bool, default: false).
        static let streamerModeEnabled = "streamerModeEnabled"

        /// Preferred app appearance: "system", "light", or "dark" (String, default: "system").
        /// Overrides `NSApplication.appearance` app-wide; "system" follows the OS setting.
        static let appearancePreference = "appearancePreference"

        /// Every UserDefaults key the app writes. Source of truth for reset operations
        /// and the DEBUG-only UserDefaults inspector.
        static let allKeys: [String] = [
            trackingEnabled,
            lastResolvedMusicPermission,
            lastLaunchCrashed,
            dockVisibility,
            twitchReauthNeeded,
            twitchChannelName,
            selectedSettingsSection,
            websocketEnabled,
            currentSongCommandEnabled,
            lastSongCommandEnabled,
            commandsLiveOnly,
            hasCompletedOnboarding,
            shareDiagnosticsEnabled,
            diagnosticsLaunchCount,
            discordPresenceEnabled,
            discordButton1Enabled,
            discordButton1Label,
            discordButton2Enabled,
            discordButton2Label,
            discordButtonsEnabled,
            discordPlaylistEnabled,
            discordPlaylistShowName,
            discordPlaylistStyle,
            discordShowIdleStatus,
            discordClearWhilePaused,
            launchAtLogin,
            websocketServerPort,
            updateCheckEnabled,
            updateSkippedVersion,
            lastSeenWhatsNewVersion,
            songCommandGlobalCooldown,
            songCommandUserCooldown,
            lastSongCommandGlobalCooldown,
            lastSongCommandUserCooldown,
            songCommandAliases,
            lastSongCommandAliases,
            wolfwaveCommandEnabled,
            wolfwaveCommandGlobalCooldown,
            wolfwaveCommandUserCooldown,
            wolfwaveCommandAliases,
            wolfwaveCommandReplyStyle,
            songCommandSongLinkEnabled,
            widgetTheme,
            widgetLayout,
            widgetTextColor,
            widgetBackgroundColor,
            widgetFontFamily,
            widgetPort,
            widgetHTTPEnabled,
            songRequestEnabled,
            songRequestMaxQueueSize,
            songRequestPerUserLimit,
            songRequestSubscriberOnly,
            songRequestAutoAdvance,
            songRequestAutoplayWhenEmpty,
            srCommandEnabled,
            queueCommandEnabled,
            myQueueCommandEnabled,
            skipCommandEnabled,
            clearQueueCommandEnabled,
            srCommandAliases,
            queueCommandAliases,
            myQueueCommandAliases,
            skipCommandAliases,
            clearQueueCommandAliases,
            songListCommandEnabled,
            songListCommandAliases,
            songRequestSongListURL,
            songRequestGlobalCooldown,
            songRequestUserCooldown,
            songRequestFallbackPlaylist,
            songRequestHoldEnabled,
            songRequestChatAudience,
            songRequestChannelPointsEnabled,
            songRequestChannelPointsCost,
            songRequestChannelPointsRewardID,
            songRequestBitsEnabled,
            songRequestBitsMinimum,
            songRequestBitsBoostEnabled,
            songRequestRedemptionStatus,
            songRequestDisabledReplyEnabled,
            songRequestPolicyMode,
            songRequestLimitStackMode,
            songRequestLimitSubscriber,
            songRequestLimitVIP,
            songRequestLimitModerator,
            voteSkipEnabled,
            voteSkipMinVotes,
            voteSkipWindowSeconds,
            voteSkipSessionCooldown,
            voteSkipSubscriberOnly,
            voteSkipCommandEnabled,
            voteSkipCommandAliases,
            voteSkipUsePolls,
            voteSkipPollDuration,
            songChangeNotificationsEnabled,
            skipVoteStartedNotificationsEnabled,
            skipVotePassedNotificationsEnabled,
            listeningHistoryEnabled,
            statsEnabled,
            statsCommandEnabled,
            statsCommandGlobalCooldown,
            statsCommandUserCooldown,
            statsCommandAliases,
            statsCommandWindow,
            statsCommandParts,
            historyRetentionDays,
            streamerModeEnabled,
            appearancePreference,
        ]

        // MARK: Export / Import Classification

        /// Keys safe to write to an exported settings backup and to restore on
        /// import. Portable preferences only. No secrets, no account identity,
        /// no per-install runtime state. Anything not listed here is deliberately
        /// excluded from backups.
        ///
        /// Invariant: every key in `allKeys` must appear in exactly one of
        /// `exportableKeys`, `accountLinkedKeys`, or `runtimeStateKeys`. Adding a
        /// new UserDefaults key forces a classification choice; the
        /// `SettingsBackupKeyCoverageTests` guard fails until it is placed.
        static let exportableKeys: [String] = [
            // General / appearance
            trackingEnabled,
            dockVisibility,
            launchAtLogin,
            appearancePreference,
            streamerModeEnabled,
            shareDiagnosticsEnabled,
            updateCheckEnabled,
            // Music monitor / song commands
            currentSongCommandEnabled,
            lastSongCommandEnabled,
            commandsLiveOnly,
            songCommandSongLinkEnabled,
            songCommandGlobalCooldown,
            songCommandUserCooldown,
            songCommandAliases,
            lastSongCommandGlobalCooldown,
            lastSongCommandUserCooldown,
            lastSongCommandAliases,
            // WolfWave info command
            wolfwaveCommandEnabled,
            wolfwaveCommandGlobalCooldown,
            wolfwaveCommandUserCooldown,
            wolfwaveCommandAliases,
            wolfwaveCommandReplyStyle,
            // Discord Rich Presence (local IPC, no account/login)
            discordPresenceEnabled,
            discordButton1Enabled,
            discordButton1Label,
            discordButton2Enabled,
            discordButton2Label,
            discordButtonsEnabled,
            discordPlaylistEnabled,
            discordPlaylistShowName,
            discordPlaylistStyle,
            discordShowIdleStatus,
            discordClearWhilePaused,
            // Stream widgets / WebSocket (local server; auth token auto-regenerates)
            websocketEnabled,
            websocketServerPort,
            widgetHTTPEnabled,
            widgetPort,
            widgetTheme,
            widgetLayout,
            widgetTextColor,
            widgetBackgroundColor,
            widgetFontFamily,
            // Song requests
            songRequestEnabled,
            songRequestMaxQueueSize,
            songRequestPerUserLimit,
            songRequestSubscriberOnly,
            songRequestAutoAdvance,
            songRequestAutoplayWhenEmpty,
            srCommandEnabled,
            queueCommandEnabled,
            myQueueCommandEnabled,
            skipCommandEnabled,
            clearQueueCommandEnabled,
            srCommandAliases,
            queueCommandAliases,
            myQueueCommandAliases,
            skipCommandAliases,
            clearQueueCommandAliases,
            songListCommandEnabled,
            songListCommandAliases,
            songRequestSongListURL,
            songRequestGlobalCooldown,
            songRequestUserCooldown,
            songRequestFallbackPlaylist,
            songRequestHoldEnabled,
            songRequestChatAudience,
            songRequestChannelPointsEnabled,
            songRequestChannelPointsCost,
            songRequestBitsEnabled,
            songRequestBitsMinimum,
            songRequestBitsBoostEnabled,
            songRequestDisabledReplyEnabled,
            songRequestPolicyMode,
            songRequestLimitStackMode,
            songRequestLimitSubscriber,
            songRequestLimitVIP,
            songRequestLimitModerator,
            // Vote skip
            voteSkipEnabled,
            voteSkipMinVotes,
            voteSkipWindowSeconds,
            voteSkipSessionCooldown,
            voteSkipSubscriberOnly,
            voteSkipCommandEnabled,
            voteSkipCommandAliases,
            voteSkipUsePolls,
            voteSkipPollDuration,
            // Notifications
            songChangeNotificationsEnabled,
            skipVoteStartedNotificationsEnabled,
            skipVotePassedNotificationsEnabled,
            // History & stats
            listeningHistoryEnabled,
            statsEnabled,
            statsCommandEnabled,
            statsCommandGlobalCooldown,
            statsCommandUserCooldown,
            statsCommandAliases,
            statsCommandWindow,
            statsCommandParts,
            historyRetentionDays,
        ]

        /// Keys tied to a connected account. Restored only when the user opts to
        /// reconnect that integration during import. The actual credentials
        /// (Twitch OAuth token + user/channel IDs) live in Keychain and never
        /// enter a backup file; these UserDefaults entries are account identity
        /// and re-auth state, not secrets.
        ///
        /// Twitch is the only OAuth account in WolfWave. Discord Rich Presence is
        /// a local IPC connection and the WebSocket/widget server is a local
        /// server with an auto-regenerated token, so neither is account-linked.
        static let accountLinkedKeys: [String] = [
            twitchChannelName,
            twitchReauthNeeded,
        ]

        /// Per-install runtime/UI state that must never travel in a backup:
        /// permission caches, last-seen markers, locally-derived status, and
        /// server-side resource IDs that belong to one specific account. These
        /// regenerate on the target machine.
        static let runtimeStateKeys: [String] = [
            lastResolvedMusicPermission,
            lastLaunchCrashed,
            selectedSettingsSection,
            hasCompletedOnboarding,
            diagnosticsLaunchCount,
            updateSkippedVersion,
            lastSeenWhatsNewVersion,
            songRequestChannelPointsRewardID,
            songRequestRedemptionStatus,
        ]
    }

    // MARK: - Appearance

    /// App appearance override modes. Map to `NSAppearance` in `AppearanceController`.
    enum Appearance {
        /// Follow the macOS system appearance (no override).
        static let system = "system"

        /// Force light (Aqua) regardless of system setting.
        static let light = "light"

        /// Force dark (Dark Aqua) regardless of system setting.
        static let dark = "dark"

        /// Default appearance mode.
        static let `default` = "system"
    }

    // MARK: - Dock Visibility Modes
    
    /// Application dock visibility modes.
    enum DockVisibility {
        /// Only show in menu bar, hide from dock
        static let menuOnly = "menuOnly"
        
        /// Only show in dock, hide menu bar icon
        static let dockOnly = "dockOnly"
        
        /// Show in both menu bar and dock (default)
        static let both = "both"
        
        /// Default visibility mode
        static let `default` = "both"
    }
    
    // MARK: - Keychain Service Identifier
    
    /// Keychain service identifiers for secure credential storage.
    enum Keychain {
        /// Primary keychain service for storing Twitch tokens and credentials
        static let service = "com.mrdemonwolf.wolfwave"

        /// Account identifier for the Twitch OAuth refresh token.
        static let twitchBotAccountRefreshToken = "twitchBotAccountRefreshToken"
    }
    
    // MARK: - Music App Integration
    
    /// Apple Music application identifiers and notification constants.
    enum Music {
        /// Bundle identifier for Apple Music app
        static let bundleIdentifier = "com.apple.Music"

        /// Base URL for the Apple Music API (library + catalog endpoints).
        /// Reached via `MusicDataRequest`, which auto-attaches the developer and
        /// music-user tokens MusicKit manages on the user's behalf.
        static let apiBaseURL = "https://api.music.apple.com/v1"

        /// Name of the library playlist WolfWave creates to hold viewer song
        /// requests.
        ///
        /// macOS 26 (Tahoe) broke AppleScript playback of catalog songs that are
        /// not in the user's library, and Music.app's AppleScript dictionary has
        /// no Up Next / queue command, so a requested song must be added to the
        /// library before it can play. Funnelling every add into one dedicated
        /// playlist keeps the streamer's curated library and Recently Added clean
        /// and gives them a single place to clear.
        static let requestsPlaylistName = "WolfWave Requests"

        /// Description set on the WolfWave Requests playlist when it is created.
        static let requestsPlaylistDescription =
            "Songs your viewers requested through WolfWave. Safe to clear anytime."
    }
    
    // MARK: - Twitch Integration
    
    /// Twitch API and integration constants.
    enum Twitch {
        /// Base URL for Twitch Helix API endpoints
        static let apiBaseURL = "https://api.twitch.tv/helix"

        /// Settings section identifier for Twitch configuration
        static let settingsSection = "twitchIntegration"

        /// Timeout in seconds for receiving the session_welcome WebSocket message
        static let sessionWelcomeTimeout: TimeInterval = 10.0

        /// Grace period added to Twitch's advertised `keepalive_timeout_seconds`
        /// before the keepalive watchdog fires. Twitch sends a `session_keepalive`
        /// (or any other frame) within the advertised window when the connection
        /// is healthy; the grace absorbs scheduling and network jitter so a single
        /// late frame doesn't trip a needless reconnect.
        static let keepaliveGraceSeconds: TimeInterval = 10.0

        /// Fallback keepalive timeout (seconds) used when the `session_welcome`
        /// payload omits or malforms `keepalive_timeout_seconds`. Twitch's default
        /// is 10s; this mirrors it so the watchdog still arms safely.
        static let keepaliveDefaultTimeoutSeconds: TimeInterval = 10.0

        /// Maximum length for bot chat messages (Twitch limit)
        static let maxMessageLength = 500

        /// Truncation suffix appended when a message exceeds `maxMessageLength`
        static let messageTruncationSuffix = "..."

        /// Connection confirmation message sent when the bot joins a channel
        static let connectionMessage = "WolfWave is connected! 🎵"

        /// Maximum reconnection attempts before giving up
        static let maxReconnectionAttempts = 5

        /// Maximum network-triggered reconnect cycles to prevent infinite loops
        static let maxNetworkReconnectCycles = 5

        /// Cooldown period in seconds before resetting network reconnect cycle counter
        nonisolated static let networkReconnectCooldown: TimeInterval = 60.0

        /// Maximum retry attempts for failed message sends
        static let maxMessageRetries = 3

        /// Maximum buffered messages in the per-message retry queue. Past this
        /// cap the oldest pending message is dropped (drop-oldest backpressure).
        static let maxPendingMessages = 64

        /// Bounded buffer for the `chatMessages` AsyncStream (drop-oldest). Chat
        /// can burst, so this is sized larger than the control streams.
        static let chatMessageStreamBuffer = 256

        /// Bounded buffer for the control AsyncStreams
        /// (`connectionStateChanges`, `skipPollResults`) using drop-oldest.
        static let controlStreamBuffer = 16

        /// Delay before sending connection message after subscribing (seconds)
        static let connectionMessageDelay: TimeInterval = 1.5

        // MARK: EventSub Subscription Types

        /// EventSub type for incoming chat messages.
        static let eventSubChatMessage = "channel.chat.message"

        /// EventSub type fired when a viewer redeems a custom channel-point reward.
        static let eventSubChannelPointsRedemption = "channel.channel_points_custom_reward_redemption.add"

        /// EventSub type fired when a viewer uses bits (cheers or Power-ups).
        static let eventSubBitsUse = "channel.bits.use"

        // MARK: OAuth Scopes

        /// OAuth scopes required for core chat functionality.
        static let chatScopes = ["user:read:chat", "user:write:chat"]

        /// OAuth scope for creating and managing custom channel-point rewards.
        static let channelPointsScope = "channel:manage:redemptions"

        /// OAuth scope for reading bit-usage events.
        static let bitsScope = "bits:read"

        /// OAuth scope for managing Twitch Polls (used by chat vote-skip in Polls mode).
        static let pollsScope = "channel:manage:polls"

        /// Every scope WolfWave ever needs, requested together at sign-in.
        ///
        /// Channel-point, bit, and poll features are off by default, but asking
        /// for their scopes up front means a streamer who turns one on later
        /// never has to disconnect and re-authorize. Twitch only prompts for the
        /// extra scopes once, at the initial grant.
        static let allScopes = chatScopes + [channelPointsScope, bitsScope, pollsScope]

        /// Title of the WolfWave-managed custom channel-point reward.
        static let songRequestRewardTitle = "Request a Song"
    }

    // MARK: - Widget

    /// Widget overlay configuration.
    enum Widget {
        /// Recommended browser source dimensions for OBS overlay
        static let recommendedWidth = 500
        static let recommendedHeight = 120
        static let recommendedDimensionsText = "\(recommendedWidth) x \(recommendedHeight)"

        /// Available widget themes
        static let themes = ["Default", "Dark", "Light", "Glass", "Neon"]

        /// Available widget layout styles
        static let layouts = ["Horizontal", "Vertical", "Compact"]
    }
    
    // MARK: - Discord Integration

    /// Discord Rich Presence constants.
    enum Discord {
        /// Settings section identifier for Discord configuration
        static let settingsSection = "discordPresence"

        /// IPC socket filename prefix (append 0-9 to find active socket)
        static let ipcSocketPrefix = "discord-ipc-"

        /// Number of IPC socket slots to try (0 through 9)
        static let ipcSocketSlots = 10

        /// Discord RPC protocol version
        static let rpcVersion = 1

        /// Activity type for "Listening" (shows "Listening to …" on profile)
        static let listeningActivityType = 2

        /// Title line (line 1) for the opt-in idle activity.
        static let idleDetails = "Apple Music is idle"

        /// Sub-line (line 2) for the opt-in idle activity.
        static let idleState = "Nothing playing right now"

        // MARK: Rich Presence art-asset keys
        //
        // Each value is a key that MUST be uploaded to the Discord developer
        // portal (Rich Presence > Art Assets) under this exact name, otherwise
        // Discord renders no image. Source PNGs live in `discord-assets/`.

        /// WolfWave logo. Large image on the idle activity so idle reads as a
        /// WolfWave state, visually distinct from active Apple Music playback.
        static let artAssetWolfWave = "wolfwave"

        /// Apple Music mark. Large image fallback + small source badge.
        static let artAssetAppleMusic = "apple_music"

        /// Pause badge swapped onto `small_image` while playback is paused.
        static let artAssetPause = "pause"

        /// Small-badge tooltip (`small_text`) shown on the idle activity.
        static let idleSmallText = "Apple Music"

        /// Reconnect base delay in seconds (doubled on each consecutive failure)
        static let reconnectBaseDelay: TimeInterval = 5.0

        /// Maximum reconnect delay cap in seconds
        static let reconnectMaxDelay: TimeInterval = 60.0

        /// Interval in seconds for polling Discord availability when not connected
        static let availabilityPollInterval: TimeInterval = 15.0

        /// Send/receive timeout (seconds) on the IPC socket. A stalled Discord
        /// peer can't block the service's actor executor longer than this — a
        /// timed-out blocking read/write fails fast into reconnect handling.
        static let socketTimeoutSeconds = 5

        /// Upper bound (exclusive) on an inbound IPC frame body, in bytes. A frame
        /// claiming a length at or above this is treated as malformed and dropped
        /// rather than allocated, bounding a hostile or garbled peer.
        static let maxIPCFrameBytes: UInt32 = 65536

        /// Default label for the first presence button (links to Apple Music track page).
        static let defaultButton1Label = "Listen on Apple Music"

        /// Default label for the second presence button (links to song.link cross-service page).
        static let defaultButton2Label = "Find on Other Services"

        /// Discord hard cap on button label length (characters).
        static let buttonLabelMaxLength = 32

        /// Discord hard cap on number of buttons per activity.
        static let maxButtons = 2

        /// Discord hard cap on activity `details` / `state` text length (characters).
        static let activityTextMaxLength = 128

        /// Separator between the artist and the playlist on the activity state line.
        static let playlistSeparator = " · "

        /// Generic state-line label shown when the playlist name is hidden.
        static let playlistAnonymousLabel = "From a playlist"

        /// Generic small-icon tooltip shown when the playlist name is hidden.
        static let playlistAnonymousTooltip = "Playing from a playlist"

        /// Prefix for the small-icon tooltip when the playlist name is shown.
        static let playlistTooltipPrefix = "Playlist"

        /// Playlist container names that are too generic to surface as a playlist.
        static let genericPlaylistNames: Set<String> = ["library", "music", "apple music"]
    }

    // MARK: - Sparkle Updater

    /// Sparkle automatic update configuration.
    enum Update {
        /// Interval between periodic update checks (24 hours in seconds)
        static let checkInterval: TimeInterval = 86400

    }

    // MARK: - Listening History

    /// Listening History & Stats configuration.
    ///
    /// The play log is an append-only NDJSON file in Application Support, one
    /// small line per recorded play. Stats are derived in memory, so they cost
    /// no extra disk writes.
    enum History {
        /// Leaf subdirectory under the `WolfWave/` Application Support container
        /// holding the play log. Resolved via ``AppContainer/directory(_:)``.
        static let directoryName = "History"

        /// Append-only NDJSON play log filename.
        static let logFileName = "plays.ndjson"

        /// Sidecar file holding the lifetime tally (totals + top-N per key)
        /// that survives rolling-window record trimming.
        static let lifetimeTallyFileName = "lifetime-tally.json"

        /// Minimum fraction of a track that must play before it counts as a play.
        static let scrobbleFraction: Double = 0.5

        /// Absolute play time (seconds) that always counts as a play, regardless
        /// of track length, mirrors Last.fm's 4-minute rule.
        static let scrobbleAbsoluteSeconds: TimeInterval = 240

        /// Initial number of recent plays shown in the History & Stats pane.
        /// The list lives in a fixed-height scroll box, so this is the count
        /// revealed before the first *Load more* tap, not a row cap.
        static let recentDisplayCount = 5

        /// How many additional plays the *Load more* button reveals per tap.
        static let recentPageStep = 5

        /// Maximum number of `PlayRecord`s retained on disk and in memory.
        /// Older plays are folded into the lifetime tally and dropped.
        static let maxRetainedRecords = 10_000

        /// Per-dimension (artist/track/album) cap on the number of entries the
        /// lifetime tally retains. When full, the lowest-count entry is evicted.
        static let lifetimeTopKeyCap = 2_000

        /// Logging category for history-related log lines.
        static let logCategory = "History"
    }

    // MARK: - External APIs

    /// Third-party API endpoints used by network services.
    ///
    /// Centralizing these URLs avoids hardcoded string duplication across
    /// service files and makes it easy to swap base URLs for testing.
    enum API {
        /// Twitch OAuth Device Code Grant endpoint (RFC 8628).
        static let twitchOAuthDevice = "https://id.twitch.tv/oauth2/device"

        /// Twitch OAuth token exchange endpoint.
        static let twitchOAuthToken = "https://id.twitch.tv/oauth2/token"

        /// Spotify public oEmbed endpoint (no auth required).
        static let spotifyOEmbed = "https://open.spotify.com/oembed"

        /// YouTube public oEmbed endpoint (no auth required).
        static let youtubeOEmbed = "https://www.youtube.com/oembed"

        /// iTunes Search API endpoint used for artwork + track metadata lookups.
        static let itunesSearch = "https://itunes.apple.com/search"

        /// song.link universal music link prefix; append a track id to form a full URL.
        static let songLinkTrackPrefix = "https://song.link/i/"

        /// How long a completed artwork lookup (including a miss) is trusted before
        /// a track is re-queried. The links cache is persisted to disk, so this TTL
        /// survives relaunches, a track is looked up roughly once a week instead of
        /// once per launch. Tracks absent from iTunes (e.g. indie releases) therefore
        /// stop re-hitting the network on every playback tick.
        static let artworkLookupTTL: TimeInterval = 7 * 24 * 3600
    }

    // MARK: - URLs

    /// Application URLs for documentation, legal, and GitHub.
    enum URLs {
        /// Documentation site URL. Override via `DOCS_URL` in `Config.xcconfig`.
        ///
        /// Guards against the xcconfig `//`-comment gotcha: if a misconfigured
        /// build truncates the value to something without a `://` scheme (e.g.
        /// `https:`), fall back to the upstream default so privacy/terms/
        /// acknowledgements links never ship broken.
        static let docs = validURL(
            infoPlistString("DOCS_URL", fallback: "https://mrdemonwolf.github.io/wolfwave"),
            fallback: "https://mrdemonwolf.github.io/wolfwave"
        )

        /// Privacy policy page URL (derived from `docs`).
        static let privacyPolicy = "\(docs)/docs/privacy-policy"

        /// Terms of service page URL (derived from `docs`).
        static let termsOfService = "\(docs)/docs/terms-of-service"

        /// Third-party acknowledgements + license notices page URL.
        static let acknowledgements = "\(docs)/docs/acknowledgements"

        /// Documentation changelog page URL (Fumadocs route).
        static let changelog = "\(docs)/docs/changelog"

        /// GitHub repository owner. Lookup: `GITHUB_REPO_OWNER` Info.plist key
        /// → env var → `"mrdemonwolf"`.
        static let repoOwner = infoPlistString(
            "GITHUB_REPO_OWNER",
            fallback: "mrdemonwolf"
        )

        /// GitHub repository name. Lookup: `GITHUB_REPO_NAME` Info.plist key
        /// → env var → `"wolfwave"`.
        static let repoName = infoPlistString(
            "GITHUB_REPO_NAME",
            fallback: "wolfwave"
        )

        /// GitHub repository URL (resolved from config)
        static let github = "https://github.com/\(repoOwner)/\(repoName)"

        /// GitHub Releases page URL (resolved from config)
        static let githubReleases = "https://github.com/\(repoOwner)/\(repoName)/releases"

        /// GitHub new-issue page URL (resolved from config)
        static let githubIssuesNew = "https://github.com/\(repoOwner)/\(repoName)/issues/new"

        /// GitHub Sponsors username.
        ///
        /// Auto-derived from `.github/FUNDING.yml` by `scripts/generate-sponsor-config.sh`
        /// and committed as `SponsorConfig.generated.swift`. Falls back to `repoOwner`
        /// if the generated value is empty.
        @MainActor
        static var sponsorUser: String {
            let generated = SponsorConfig.sponsorUser.trimmingCharacters(in: .whitespacesAndNewlines)
            return generated.isEmpty ? repoOwner : generated
        }

        /// GitHub Sponsors page URL (resolved from FUNDING.yml)
        @MainActor
        static var githubSponsors: String { "https://github.com/sponsors/\(sponsorUser)" }

        /// Community Discord invite: opened from the tray menu "Help ▸ Join Discord Community".
        /// Override via `COMMUNITY_DISCORD_URL` in `Config.xcconfig`.
        static let communityDiscord = validURL(
            infoPlistString("COMMUNITY_DISCORD_URL", fallback: "https://mrdwolf.net/discord"),
            fallback: "https://mrdwolf.net/discord"
        )

        /// System Settings deep link to Notifications (macOS 13+).
        /// Opened from onboarding and `NotificationService` so users can grant
        /// the notification permission outside the app.
        static let systemNotificationSettings =
            "x-apple.systempreferences:com.apple.Notifications-Settings.extension"

        /// System Settings deep link to Privacy & Security ▸ Automation (macOS 13+).
        /// Opened from the Apple Music permission flow.
        static let systemAutomationSettings =
            "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation"

        /// Returns `value` when it parses as an absolute URL with a scheme and
        /// host, otherwise `fallback`. Catches xcconfig `//`-truncated values
        /// like `https:` that would otherwise produce broken links.
        private static func validURL(_ value: String, fallback: String) -> String {
            guard let url = URL(string: value), url.scheme != nil, url.host != nil else {
                return fallback
            }
            return value
        }
    }

    // MARK: - WebSocket Server

    /// WebSocket server configuration constants.
    enum WebSocketServer {
        /// Default port for the local WebSocket server
        static let defaultPort: UInt16 = 8765

        /// Minimum allowed port number (below 1024 requires root)
        static let minPort: UInt16 = 1024

        /// Maximum allowed port number
        static let maxPort: UInt16 = 65535

        /// Interval in seconds between progress broadcasts during playback
        static let progressBroadcastInterval: TimeInterval = 1.0

        /// Delay before retrying after a listener failure
        static let retryDelay: TimeInterval = 5.0

        /// Default port for the local widget HTTP server
        static let widgetDefaultPort: UInt16 = 8766
    }

    // MARK: - Dispatch Queue Labels

    /// Dispatch queue identifiers for background operations.
    enum DispatchQueues {
        /// Queue for WebSocket server operations
        static let websocketServer = "com.mrdemonwolf.wolfwave.websocketserver"
    }

    // MARK: - Menu Item Labels

    /// Menu item text labels.
    enum MenuLabels {
        static let settings = "Settings\u{2026}"
        static let quit = "Quit WolfWave"
    }

    // MARK: - Recently Played

    /// Configuration for the tray menu's "Recently Played" submenu.
    enum RecentlyPlayed {
        /// Maximum number of recent tracks retained in the in-memory ring buffer.
        static let maxEntries = 5
    }

    // MARK: - Settings UI

    /// Settings window configuration.
    ///
    /// Dimension values are sourced from `DSDimension.Settings` (generated from
    /// `design-system/tokens.json`). These wrappers keep the existing call sites
    /// stable while the design system stays the single source of truth.
    enum SettingsUI {
        /// Default application name shown in UI
        static let defaultAppName = "WolfWave"

        /// Minimum width for settings window. Sized so sidebar + detail pane fit
        /// the integration dashboard rows (icon · text · status chip · Configure)
        /// without truncation, while still working on a 1280×720 display.
        static let minWidth: CGFloat = DSDimension.Settings.minWidth

        /// Minimum height for settings window. Fits the General tab's hero card
        /// plus the four-row integrations list on a 720p display with Dock visible.
        static let minHeight: CGFloat = DSDimension.Settings.minHeight

        /// Ideal width for settings window when first opened.
        static let idealWidth: CGFloat = DSDimension.Settings.idealWidth

        /// Ideal height for settings window when first opened.
        static let idealHeight: CGFloat = DSDimension.Settings.idealHeight

        /// Maximum content width for detail pane
        static let maxContentWidth: CGFloat = DSDimension.Settings.maxContentWidth

        /// Standard horizontal padding for content sections
        static let contentPaddingH: CGFloat = DSDimension.Settings.contentPaddingH

        /// Standard vertical padding for content sections
        static let contentPaddingV: CGFloat = DSDimension.Settings.contentPaddingV

        /// Standard spacing between sections
        static let sectionSpacing: CGFloat = DSDimension.Settings.sectionSpacing

        /// Standard card padding
        static let cardPadding: CGFloat = DSDimension.Settings.cardPadding

        /// Standard card corner radius (matches macOS 26 Liquid Glass card radius).
        static let cardCornerRadius: CGFloat = DSDimension.Settings.cardCornerRadius

        /// Max width for short inline trailing fields inside a settings row
        /// (e.g. the command "Custom aliases" text field and the !wolfwave reply
        /// picker). Keeps these compact so they sit at the trailing edge instead
        /// of stretching the full card width.
        static let inlineFieldMaxWidth: CGFloat = 200
    }

    // MARK: - Power Management

    /// Reduced-rate timing constants used when the system is in Low Power Mode
    /// or under serious/critical thermal pressure.
    enum PowerManagement {
        /// Music monitor fallback polling interval in reduced-power mode (15s vs normal 5s)
        static let reducedMusicCheckInterval: TimeInterval = 15.0

        /// Discord availability poll interval in reduced-power mode (60s vs normal 15s)
        static let reducedDiscordPollInterval: TimeInterval = 60.0

        /// WebSocket progress broadcast interval in reduced-power mode (3s vs normal 1s)
        static let reducedProgressBroadcastInterval: TimeInterval = 3.0
    }

    // MARK: - Onboarding UI

    /// Onboarding wizard window configuration.
    ///
    /// Dimension values are sourced from `DSDimension.Onboarding` (generated
    /// from `design-system/tokens.json`).
    enum OnboardingUI {
        /// Width of the onboarding window
        static let windowWidth: CGFloat = DSDimension.Onboarding.windowWidth

        /// Height of the onboarding window
        static let windowHeight: CGFloat = DSDimension.Onboarding.windowHeight

        /// Standard height for primary action buttons (e.g. Sign in with Twitch).
        static let primaryButtonHeight: CGFloat = DSDimension.Onboarding.primaryButtonHeight

        /// Minimum width for primary action buttons so labels can swap without resizing.
        static let primaryButtonMinWidth: CGFloat = DSDimension.Onboarding.primaryButtonMinWidth

        /// Minimum width for navigation bar buttons (Back, Skip, Next/Finish, Skip All).
        static let navButtonMinWidth: CGFloat = DSDimension.Onboarding.navButtonMinWidth

        /// Reserved vertical space for state-swapping content within a step
        /// (e.g. Twitch `notConnected` → `authorizing` → `connected`).
        static let stepContentMinHeight: CGFloat = DSDimension.Onboarding.stepContentMinHeight

        /// Side length of the brand tile used as the visual anchor for each integration step.
        static let brandTileSize: CGFloat = DSDimension.Onboarding.brandTileSize

        /// Corner radius of the brand tile (continuous-rounded square).
        static let brandTileRadius: CGFloat = DSDimension.Onboarding.brandTileRadius

        /// Corner radius for primary CTA buttons (continuous rounded rect, macOS-standard for 36pt height).
        static let primaryButtonRadius: CGFloat = DSDimension.Onboarding.primaryButtonRadius

        /// Side length of the small tinted SF Symbol tile in onboarding toggle rows.
        static let iconTileSize: CGFloat = DSDimension.Onboarding.iconTileSize

        /// Corner radius of the small icon tile (matches the brand tile's 25% ratio).
        static let iconTileRadius: CGFloat = DSDimension.Onboarding.iconTileRadius
    }

    // MARK: - Brand Colors

    /// Brand / partner colors. Backed by `DSColor` generated tokens.
    /// Source of truth: `design-system/tokens.json`.
    enum Brand {
        /// Twitch purple: `#9146FF`.
        static let twitch = DSColor.partnerTwitch

        /// Discord blurple: `#5865F2`.
        static let discord = DSColor.partnerDiscord

        /// Discord card surface: `#2B2D31`.
        static let discordSurface = DSColor.partnerDiscordSurface

        /// Discord secondary button surface: `#4E5058`.
        static let discordControl = DSColor.partnerDiscordControl

        /// Apple Music gradient stops: pink-to-red.
        static let appleMusicGradientStart = DSColor.partnerAppleMusicStart
        static let appleMusicGradientEnd = DSColor.partnerAppleMusicEnd

        /// Apple Music permission-denied icon gradient: softer than the main
        /// brand gradient; used for the rounded-rect Music app icon stack.
        static let appleMusicSurfaceStart = DSColor.partnerAppleMusicSurfaceStart
        static let appleMusicSurfaceEnd = DSColor.partnerAppleMusicSurfaceEnd

        /// Apple Music pulse gradient: used for the bottom-strip CTA accent
        /// on the permission-denied screen.
        static let appleMusicPulseStart = DSColor.partnerAppleMusicPulseStart
        static let appleMusicPulseEnd = DSColor.partnerAppleMusicPulseEnd

        /// OBS Studio gradient stops: neutral dark.
        static let obsGradientStart = DSColor.partnerObsStart
        static let obsGradientEnd = DSColor.partnerObsEnd

        /// WolfWave gradient stops: navy → royal blue. Used for branded share cards (Monthly Wrap export).
        static let wolfwaveGradientStart = DSColor.partnerWolfwaveGradientStart
        static let wolfwaveGradientEnd = DSColor.partnerWolfwaveGradientEnd
    }
}
