//
//  AppConstants.swift
//  wolfwave
//
//  Created by MrDemonWolf, Inc. on 1/17/26.
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
    // MARK: - App Identifiers
    
    /// Application bundle and display information.
    enum AppInfo {
        static let bundleIdentifier = "com.mrdemonwolf.wolfwave"
        static let displayName = "WolfWave"
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

        /// All notification names — used by the DEBUG-only notification firehose.
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
        ]
    }

    // MARK: - User Notifications

    /// Identifiers for macOS User Notifications posted via `NotificationService`.
    enum UserNotification {
        /// Stable identifier for the song-change notification. Reused on every
        /// track change so a new song replaces the previous notification in
        /// Notification Center rather than stacking.
        static let songChangeIdentifier = "com.mrdemonwolf.wolfwave.notification.songChange"
    }

    // MARK: - UserDefaults Keys
    
    /// Keys for persisting user preferences in UserDefaults.
    ///
    /// Usage: `@AppStorage(AppConstants.UserDefaults.trackingEnabled)`
    enum UserDefaults {
        /// Whether Apple Music monitoring is enabled (Bool, default: true)
        static let trackingEnabled = "trackingEnabled"
        
        /// Dock visibility mode: "menuOnly", "dockOnly", or "both" (String, default: "both")
        static let dockVisibility = "dockVisibility"
        
        /// Whether Twitch re-authentication is required (Bool, default: false)
        static let twitchReauthNeeded = "twitchReauthNeeded"
        
        /// Settings section to open next time (String, "twitchIntegration", etc.)
        static let selectedSettingsSection = "selectedSettingsSection"
        
        /// Whether WebSocket integration is enabled (Bool, default: false)
        static let websocketEnabled = "websocketEnabled"
        
        /// WebSocket endpoint URI (String)
        static let websocketURI = "websocketURI"
        
        /// Whether "current song" bot command is enabled (Bool, default: false)
        static let currentSongCommandEnabled = "currentSongCommandEnabled"

        /// Whether "last song" bot command is enabled (Bool, default: false)
        static let lastSongCommandEnabled = "lastSongCommandEnabled"

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

        /// Whether the current Apple Music playlist is shown in Discord presence (Bool, default: false)
        static let discordPlaylistEnabled = "discordPlaylistEnabled"

        /// Whether the playlist's actual name is revealed (Bool, default: true).
        /// When false, a generic label is shown instead so the name stays private.
        static let discordPlaylistShowName = "discordPlaylistShowName"

        /// How the playlist is displayed in Discord presence — `DiscordPlaylistStyle` raw value (String, default: "artistLine")
        static let discordPlaylistStyle = "discordPlaylistStyle"

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

        /// Global cooldown for song request commands in seconds (Double, default: 5.0)
        static let songRequestGlobalCooldown = "songRequestGlobalCooldown"

        /// Per-user cooldown for song request commands in seconds (Double, default: 30.0)
        static let songRequestUserCooldown = "songRequestUserCooldown"

        /// Name of the Apple Music playlist to play when the request queue is empty (String, default: "")
        static let songRequestFallbackPlaylist = "songRequestFallbackPlaylist"

        /// Whether song request auto-play is paused — requests still queue but nothing plays (Bool, default: false)
        static let songRequestHoldEnabled = "songRequestHoldEnabled"

        /// Who may request via the !sr chat command — a `RequestAudience` raw value
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

        /// Health of the redemption integration — a `RedemptionStatus` raw value.
        /// Empty/"ok" when working; other values drive the settings re-auth banner
        /// (String, default: "ok").
        static let songRequestRedemptionStatus = "songRequestRedemptionStatus"

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

        /// Duration of a Twitch poll created for vote-skip, in seconds (Int, default: 60; Twitch allows 15–1800)
        static let voteSkipPollDuration = "voteSkipPollDuration"

        /// Whether on-device MetricKit diagnostics collection is opted in (Bool, default: false)
        static let shareDiagnosticsEnabled = "shareDiagnosticsEnabled"

        /// Local count of app launches — anonymous, never transmitted (Int, default: 0)
        static let diagnosticsLaunchCount = "diagnosticsLaunchCount"

        /// Whether a macOS notification is posted when the song changes (Bool, default: false)
        static let songChangeNotificationsEnabled = "songChangeNotificationsEnabled"

        // MARK: Listening History & Stats Keys

        /// Whether the on-disk listening history log is being recorded (Bool, default: false — opt-in)
        static let listeningHistoryEnabled = "listeningHistoryEnabled"

        /// Whether the Stats & Charts UI is enabled. Requires `listeningHistoryEnabled` (Bool, default: false)
        static let statsEnabled = "statsEnabled"

        /// Whether the `!stats` Twitch command is enabled. Requires `statsEnabled` (Bool, default: false)
        static let statsCommandEnabled = "statsCommandEnabled"

        /// Global cooldown for the !stats command in seconds (Double, default: 15.0)
        static let statsCommandGlobalCooldown = "statsCommandGlobalCooldown"

        /// Per-user cooldown for the !stats command in seconds (Double, default: 15.0)
        static let statsCommandUserCooldown = "statsCommandUserCooldown"

        /// Days of listening history to retain. 0 = keep everything (Int, default: 0)
        static let historyRetentionDays = "historyRetentionDays"

        /// Every UserDefaults key the app writes. Source of truth for reset operations
        /// and the DEBUG-only UserDefaults inspector.
        static let allKeys: [String] = [
            trackingEnabled,
            dockVisibility,
            twitchReauthNeeded,
            selectedSettingsSection,
            websocketEnabled,
            websocketURI,
            currentSongCommandEnabled,
            lastSongCommandEnabled,
            hasCompletedOnboarding,
            shareDiagnosticsEnabled,
            diagnosticsLaunchCount,
            discordPresenceEnabled,
            discordPlaylistEnabled,
            discordPlaylistShowName,
            discordPlaylistStyle,
            launchAtLogin,
            websocketServerPort,
            updateCheckEnabled,
            updateSkippedVersion,
            lastSeenWhatsNewVersion,
            songCommandGlobalCooldown,
            songCommandUserCooldown,
            lastSongCommandGlobalCooldown,
            lastSongCommandUserCooldown,
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
            listeningHistoryEnabled,
            statsEnabled,
            statsCommandEnabled,
            statsCommandGlobalCooldown,
            statsCommandUserCooldown,
            historyRetentionDays,
        ]
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
    }
    
    // MARK: - Music App Integration
    
    /// Apple Music application identifiers and notification constants.
    enum Music {
        /// Bundle identifier for Apple Music app
        static let bundleIdentifier = "com.apple.Music"
        
        /// Notification name posted by Music app when playback info changes
        static let playerInfoNotification = "com.apple.Music.playerInfo"
    }
    
    // MARK: - Twitch Integration
    
    /// Twitch API and integration constants.
    enum Twitch {
        /// Base URL for Twitch Helix API endpoints
        static let apiBaseURL = "https://api.twitch.tv/helix"

        /// Settings section identifier for Twitch configuration
        static let settingsSection = "twitchIntegration"

        /// Default setting for sending connection message on subscribe
        static let defaultSendConnectionMessage = true

        /// Timeout in seconds for receiving the session_welcome WebSocket message
        static let sessionWelcomeTimeout: TimeInterval = 10.0

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

        /// IPC socket filename prefix (append 0–9 to find active socket)
        static let ipcSocketPrefix = "discord-ipc-"

        /// Number of IPC socket slots to try (0 through 9)
        static let ipcSocketSlots = 10

        /// Discord RPC protocol version
        static let rpcVersion = 1

        /// Activity type for "Listening" (shows "Listening to …" on profile)
        static let listeningActivityType = 2

        /// Reconnect base delay in seconds (doubled on each consecutive failure)
        static let reconnectBaseDelay: TimeInterval = 5.0

        /// Maximum reconnect delay cap in seconds
        static let reconnectMaxDelay: TimeInterval = 60.0

        /// Interval in seconds for polling Discord availability when not connected
        static let availabilityPollInterval: TimeInterval = 15.0

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
    /// The play log is an append-only NDJSON file in Application Support — one
    /// small line per recorded play. Stats are derived in memory, so they cost
    /// no extra disk writes.
    enum History {
        /// Subdirectory of Application Support holding the play log.
        static let directoryName = "WolfWave/History"

        /// Append-only NDJSON play log filename.
        static let logFileName = "plays.ndjson"

        /// Minimum fraction of a track that must play before it counts as a play.
        static let scrobbleFraction: Double = 0.5

        /// Absolute play time (seconds) that always counts as a play, regardless
        /// of track length — mirrors Last.fm's 4-minute rule.
        static let scrobbleAbsoluteSeconds: TimeInterval = 240

        /// Number of recent plays surfaced in the History & Stats settings pane.
        static let recentDisplayCount = 8

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

        /// Twitch Helix API base URL.
        static let twitchHelix = "https://api.twitch.tv/helix"

        /// Spotify public oEmbed endpoint (no auth required).
        static let spotifyOEmbed = "https://open.spotify.com/oembed"

        /// YouTube public oEmbed endpoint (no auth required).
        static let youtubeOEmbed = "https://www.youtube.com/oembed"

        /// iTunes Search API endpoint used for artwork + track metadata lookups.
        static let itunesSearch = "https://itunes.apple.com/search"

        /// song.link universal music link prefix; append a track id to form a full URL.
        static let songLinkTrackPrefix = "https://song.link/i/"
    }

    // MARK: - URLs

    /// Application URLs for documentation, legal, and GitHub.
    enum URLs {
        /// Documentation site URL
        static let docs = "https://mrdemonwolf.github.io/wolfwave"

        /// Privacy policy page URL
        static let privacyPolicy = "https://mrdemonwolf.github.io/wolfwave/docs/privacy-policy"

        /// Terms of service page URL
        static let termsOfService = "https://mrdemonwolf.github.io/wolfwave/docs/terms-of-service"

        /// GitHub repository owner (cached at first access).
        ///
        /// Lookup order:
        /// 1. `GITHUB_REPO_OWNER` key in Info.plist (expanded from Config.xcconfig at build time)
        /// 2. `GITHUB_REPO_OWNER` environment variable (for dev/CI overrides)
        /// 3. Fallback to "mrdemonwolf"
        static let repoOwner: String = {
            if let plistValue = Bundle.main.object(forInfoDictionaryKey: "GITHUB_REPO_OWNER") as? String {
                let trimmed = plistValue.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty, trimmed != "$(GITHUB_REPO_OWNER)" {
                    return trimmed
                }
            }
            if let env = ProcessInfo.processInfo.environment["GITHUB_REPO_OWNER"] {
                let trimmed = env.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty { return trimmed }
            }
            return "mrdemonwolf"
        }()

        /// GitHub repository name (cached at first access).
        ///
        /// Lookup order:
        /// 1. `GITHUB_REPO_NAME` key in Info.plist (expanded from Config.xcconfig at build time)
        /// 2. `GITHUB_REPO_NAME` environment variable (for dev/CI overrides)
        /// 3. Fallback to "wolfwave"
        static let repoName: String = {
            if let plistValue = Bundle.main.object(forInfoDictionaryKey: "GITHUB_REPO_NAME") as? String {
                let trimmed = plistValue.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty, trimmed != "$(GITHUB_REPO_NAME)" {
                    return trimmed
                }
            }
            if let env = ProcessInfo.processInfo.environment["GITHUB_REPO_NAME"] {
                let trimmed = env.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty { return trimmed }
            }
            return "wolfwave"
        }()

        /// GitHub repository URL (resolved from config)
        static let github = "https://github.com/\(repoOwner)/\(repoName)"

        /// GitHub Releases API endpoint (resolved from config)
        static let githubReleasesAPI = "https://api.github.com/repos/\(repoOwner)/\(repoName)/releases/latest"

        /// GitHub Releases page URL (resolved from config)
        static let githubReleases = "https://github.com/\(repoOwner)/\(repoName)/releases"

        /// GitHub new-issue page URL (resolved from config)
        static let githubIssuesNew = "https://github.com/\(repoOwner)/\(repoName)/issues/new"

        /// Community Discord invite — opened from the tray menu "Help ▸ Join Discord Community".
        static let communityDiscord = "https://mrdwolf.net/discord"
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
    ///
    /// These are used to create dedicated background threads for specific tasks
    /// to avoid blocking the main UI thread.
    enum DispatchQueues {
        /// Queue for music playback monitoring callbacks
        static let musicPlaybackMonitor = "com.mrdemonwolf.wolfwave.musicplaybackmonitor"
        
        /// Queue for Twitch network operations
        static let twitchNetworkMonitor = "com.mrdemonwolf.wolfwave.networkmonitor"

        /// Queue for Discord IPC operations
        static let discordIPC = "com.mrdemonwolf.wolfwave.discordipc"

        /// Queue for WebSocket server operations
        static let websocketServer = "com.mrdemonwolf.wolfwave.websocketserver"

        static let systemNowPlaying = "com.mrdemonwolf.wolfwave.systemnowplaying"

        /// Queue for song request operations
        static let songRequest = "com.mrdemonwolf.wolfwave.songrequest"
    }
    
    // MARK: - Animation & Timing
    
    /// Animation durations and timing constants.
    enum Timing {
        /// Delay before restoring menu-only mode after window closes
        static let windowCloseDelay: TimeInterval = 0.1
        
        /// Delay before showing notifications after auth events
        static let notificationDelay: TimeInterval = 0.5
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
    enum SettingsUI {
        /// Default application name shown in UI
        static let defaultAppName = "WolfWave"

        /// Minimum width for settings window. Sized so the sidebar + detail pane
        /// remain usable on a 1280×720 display.
        static let minWidth: CGFloat = 720

        /// Minimum height for settings window. Sized to fit a 720p display with
        /// the Dock visible (~626pt usable vertical space).
        static let minHeight: CGFloat = 520

        /// Ideal width for settings window when first opened.
        static let idealWidth: CGFloat = 900

        /// Ideal height for settings window when first opened. Fits 720p w/ Dock.
        static let idealHeight: CGFloat = 600

        /// Maximum content width for detail pane
        static let maxContentWidth: CGFloat = 720

        /// Standard horizontal padding for content sections
        static let contentPaddingH: CGFloat = 28

        /// Standard vertical padding for content sections
        static let contentPaddingV: CGFloat = 22

        /// Standard spacing between sections
        static let sectionSpacing: CGFloat = 24

        /// Standard card padding
        static let cardPadding: CGFloat = 16

        /// Standard card corner radius (matches macOS 26 Liquid Glass card radius).
        static let cardCornerRadius: CGFloat = 14
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
    enum OnboardingUI {
        /// Width of the onboarding window
        static let windowWidth: CGFloat = 600

        /// Height of the onboarding window
        static let windowHeight: CGFloat = 480

        /// Standard height for primary action buttons (e.g. Sign in with Twitch).
        static let primaryButtonHeight: CGFloat = 32

        /// Minimum width for primary action buttons so labels can swap without resizing.
        static let primaryButtonMinWidth: CGFloat = 200

        /// Minimum width for navigation bar buttons (Back, Skip, Next/Finish, Skip All).
        static let navButtonMinWidth: CGFloat = 80

        /// Reserved vertical space for state-swapping content within a step
        /// (e.g. Twitch `notConnected` → `authorizing` → `connected`).
        static let stepContentMinHeight: CGFloat = 220

        /// Side length of the brand tile used as the visual anchor for each integration step.
        static let brandTileSize: CGFloat = 56

        /// Corner radius of the brand tile (continuous-rounded square).
        static let brandTileRadius: CGFloat = 14

        /// Corner radius for primary CTA buttons (continuous rounded rect, macOS-standard for 36pt height).
        static let primaryButtonRadius: CGFloat = 8
    }

    // MARK: - Brand Colors

    /// Brand / partner colors. Backed by `DSColor` generated tokens.
    /// Source of truth: `design-system/tokens.json`.
    enum Brand {
        /// Twitch purple — `#9146FF`.
        static let twitch = DSColor.partnerTwitch

        /// Discord blurple — `#5865F2`.
        static let discord = DSColor.partnerDiscord

        /// Apple Music gradient stops — pink-to-red.
        static let appleMusicGradientStart = DSColor.partnerAppleMusicStart
        static let appleMusicGradientEnd = DSColor.partnerAppleMusicEnd

        /// OBS Studio gradient stops — neutral dark.
        static let obsGradientStart = DSColor.partnerObsStart
        static let obsGradientEnd = DSColor.partnerObsEnd
    }
}
