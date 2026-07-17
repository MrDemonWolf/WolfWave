//
//  AppConstants+UserDefaults.swift
//  WolfWave
//
//  Created by Nathanial Henniges on 2026-07-15.
//  Copyright © 2026 MrDemonWolf, Inc. All rights reserved.
//

import Foundation

extension AppConstants {
    /// Keys for persisting user preferences in UserDefaults.
    ///
    /// Usage: `@AppStorage(AppConstants.UserDefaults.trackingEnabled)`
    nonisolated enum UserDefaults {
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

        /// User-defined custom chat commands, stored as JSON-encoded
        /// `[CustomCommand]`. Managed by `CustomCommandStore`. (Data, default: empty)
        static let customCommands = "customCommands"

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
        /// playing instead of clearing the profile (Bool, default: true).
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

        /// Selected Sparkle update channel: `"stable"` (default) or `"nightly"`.
        /// Stored as the `UpdateChannel` raw value. Nightly points Sparkle at the
        /// rolling nightly appcast via `SparkleUpdaterService.feedURLString(for:)`.
        static let updateChannel = "updateChannel"

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

        /// Whether requests wait for streamer approval before queueing (Bool, default: false)
        static let songRequestApprovalRequired = "songRequestApprovalRequired"

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

        /// Whether the streamer has finished the guided Song Requests setup. The
        /// master toggle stays locked behind a "Set up" call to action until this
        /// is true; the setup sheet sets it on finish, and a one-time migration
        /// grandfathers anyone who already had the feature on (Bool, default: false).
        static let songRequestSetupComplete = "songRequestSetupComplete"

        /// Health of the song-request playlist: a `PlaylistSetupStatus` raw value
        /// ("ok", "playlistMissing", "linkUnshared", "musicAccessLost"). Drives the
        /// top-of-pane "needs setup again" banner and the fallback policy
        /// (String, default: "ok").
        static let songRequestPlaylistStatus = "songRequestPlaylistStatus"

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
            customCommands,
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
            updateChannel,
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
            songRequestApprovalRequired,
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
            songRequestSetupComplete,
            songRequestPlaylistStatus,
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
            updateChannel,
            // Music monitor / song commands
            currentSongCommandEnabled,
            lastSongCommandEnabled,
            commandsLiveOnly,
            customCommands,
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
            songRequestApprovalRequired,
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
            songRequestSetupComplete,
            songRequestPlaylistStatus,
        ]
    }
}
