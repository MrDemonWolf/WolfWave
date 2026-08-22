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

        /// One-line summary of that crash (signal/exception, time, build), shown in
        /// the Advanced pane callout. Runtime state, not exported.
        static let lastCrashSummary = "lastCrashSummary"

        /// Dock visibility mode: "menuOnly", "dockOnly", or "both" (String, default: "both")
        static let dockVisibility = "dockVisibility"

        /// Whether Twitch re-authentication is required (Bool, default: false)
        static let twitchReauthNeeded = "twitchReauthNeeded"

        /// Connected Twitch channel/login name shown in the menu bar status line (String)
        static let twitchChannelName = "twitchChannelName"

        /// Channel restored from a backup but not yet paired with a newly
        /// authenticated account. Never used for connection decisions.
        static let twitchPendingImportedChannelName = "twitchPendingImportedChannelName"

        /// Settings section to open next time (String, "twitchIntegration", etc.)
        static let selectedSettingsSection = "selectedSettingsSection"

        /// Whether WebSocket integration is enabled (Bool, default: false)
        static let websocketEnabled = "websocketEnabled"

        /// Whether the Stream Deck plugin may run commands (Bool, default: true).
        ///
        /// Separate from ``websocketEnabled`` on purpose: the two share one server
        /// and one port but not one threat model. The overlay credential is
        /// read-only and reachable across the LAN; the control credential runs
        /// commands and is loopback-only. This gate lets a user disarm the
        /// command half without taking their overlay off the air.
        ///
        /// Defaults to `true` because the capability already shipped, gated by the
        /// control token. Defaulting it off would silently break every Stream Deck
        /// already in use on the next launch.
        static let streamDeckControlEnabled = "streamDeckControlEnabled"

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

        /// Widget font family (String, default: "System Default")
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

        /// Fair-share (round-robin) queue ordering vs classic FIFO (Bool, default: true)
        static let songRequestFairShare = "songRequestFairShare"

        /// Sub/VIP request priority: off / cooldownSkip / queueJump (String, default: off)
        static let songRequestPriorityMode = "songRequestPriorityMode"

        /// Whether song requests require a subscriber badge (Bool, default: false)
        static let songRequestSubscriberOnly = "songRequestSubscriberOnly"

        /// Whether auto-advance is enabled (Bool, default: true)
        static let songRequestAutoAdvance = "songRequestAutoAdvance"

        /// Whether Apple Music autoplay resumes when queue empties (Bool, default: true)
        static let songRequestAutoplayWhenEmpty = "songRequestAutoplayWhenEmpty"

        /// Whether requests wait for streamer approval before queueing (Bool, default: false)
        static let songRequestApprovalRequired = "songRequestApprovalRequired"

        /// Song and artist entries blocked from song requests, stored as JSON.
        static let songRequestBlocklist = "songRequestBlocklist"

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

        /// Atomic encoded {rewardID, broadcasterID} identity for the managed reward.
        static let songRequestChannelPointsRewardIdentity =
            "songRequestChannelPointsRewardIdentity"

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

        /// Health of custom-command announcements: an `AnnounceStatus` raw value.
        /// Set by the last announcement send attempt; non-"ok" values drive the
        /// Custom Commands card banner (String, default: "ok").
        static let customCommandAnnounceStatus = "customCommandAnnounceStatus"

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

        /// Verified Apple Music library ID of WolfWave's owned requests playlist.
        /// Runtime state: account-specific and revalidated before use.
        static let songRequestPlaylistID = "songRequestPlaylistID"

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

        /// Whether sponsorship links are shown (Bool, default: true).
        ///
        /// Covers the menu bar item, the app menu command, and the About pane's
        /// Sponsor action. The About pane keeps the toggle itself so turning it
        /// back on is always possible. Nothing about this changes what the app
        /// does, only whether it asks.
        static let sponsorLinksEnabled = "sponsorLinksEnabled"

        #if DEBUG
        static let debugTreatAllChattersAsViewers = "debugTreatAllChattersAsViewers"
        static let debugViewerUsernames = "debugViewerUsernames"
        private static let debugKeys = [
            debugTreatAllChattersAsViewers,
            debugViewerUsernames,
        ]
        #else
        private static let debugKeys: [String] = []
        #endif

        /// Every UserDefaults key the app writes. Source of truth for reset operations
        /// and the DEBUG-only UserDefaults inspector.
        static let allKeys: [String] = [
            trackingEnabled,
            lastResolvedMusicPermission,
            lastLaunchCrashed,
            lastCrashSummary,
            dockVisibility,
            twitchReauthNeeded,
            twitchChannelName,
            twitchPendingImportedChannelName,
            selectedSettingsSection,
            websocketEnabled,
            streamDeckControlEnabled,
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
            songRequestFairShare,
            songRequestPriorityMode,
            songRequestSubscriberOnly,
            songRequestAutoAdvance,
            songRequestAutoplayWhenEmpty,
            songRequestApprovalRequired,
            songRequestBlocklist,
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
            songRequestChannelPointsRewardIdentity,
            songRequestBitsEnabled,
            songRequestBitsMinimum,
            songRequestBitsBoostEnabled,
            songRequestRedemptionStatus,
            customCommandAnnounceStatus,
            songRequestSetupComplete,
            songRequestPlaylistStatus,
            songRequestPlaylistID,
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
            sponsorLinksEnabled,
            appearancePreference,
        ] + debugKeys

        // MARK: Export / Import Classification

        /// The on-disk value shape and optional validation rule for one portable
        /// preference. This stays independent of `BackupValue` so the key
        /// catalog remains the source of truth while the backup coder performs
        /// the concrete tagged-value match.
        nonisolated enum ExportedIntegerDomain: Equatable, Sendable {
            case values(Set<Int>)
            case zeroOrRange(ClosedRange<Int>)
        }

        nonisolated struct ExportedDoubleDomain: Equatable, Sendable {
            let range: ClosedRange<Double>
            let step: Double
        }

        nonisolated enum ExportedDataFormat: Equatable, Sendable {
            case customCommands, songRequestBlocklist
        }

        nonisolated enum ExportedValueRule: Equatable, Sendable {
            case bool
            case int(ExportedIntegerDomain)
            case double(ExportedDoubleDomain)
            case string(Set<String>?)
            case stringList(Set<String>)
            case data(ExportedDataFormat)
        }

        /// One portable preference and the exact value shape an import accepts.
        nonisolated struct ExportablePreference: Equatable, Sendable {
            let key: String
            let rule: ExportedValueRule
        }

        private static func portableBool(_ key: String) -> ExportablePreference {
            ExportablePreference(key: key, rule: .bool)
        }

        private static func portableInt(
            _ key: String,
            allowedValues: [Int]
        ) -> ExportablePreference {
            ExportablePreference(key: key, rule: .int(.values(Set(allowedValues))))
        }

        private static func portablePort(_ key: String) -> ExportablePreference {
            ExportablePreference(
                key: key,
                rule: .int(.zeroOrRange(
                    Int(AppConstants.WebSocketServer.minPort)...Int(AppConstants.WebSocketServer.maxPort)
                ))
            )
        }

        private static func portableDouble(
            _ key: String,
            in range: ClosedRange<Double>,
            step: Double
        ) -> ExportablePreference {
            ExportablePreference(
                key: key,
                rule: .double(ExportedDoubleDomain(range: range, step: step))
            )
        }

        private static func portableString(
            _ key: String,
            allowedValues: [String]? = nil
        ) -> ExportablePreference {
            ExportablePreference(key: key, rule: .string(allowedValues.map { Set($0) }))
        }

        private static func portableStringList(
            _ key: String,
            allowedValues: [String]
        ) -> ExportablePreference {
            ExportablePreference(key: key, rule: .stringList(Set(allowedValues)))
        }

        private static func portableData(
            _ key: String,
            format: ExportedDataFormat
        ) -> ExportablePreference {
            ExportablePreference(key: key, rule: .data(format))
        }

        /// Portable preferences safe to export and restore, paired with their
        /// complete validation schema. No secrets, account identity, or
        /// per-install runtime state appears here. Anything not listed is
        /// deliberately excluded from backups.
        ///
        /// Invariant: every key in `allKeys` must appear in exactly one of
        /// `exportableKeys`, `accountLinkedKeys`, or `runtimeStateKeys`. Adding a
        /// new UserDefaults key forces a classification choice; the
        /// `SettingsBackupKeyCoverageTests` guard fails until it is placed.
        static let exportablePreferences: [ExportablePreference] = [
            // General / appearance
            portableBool(trackingEnabled),
            portableString(dockVisibility, allowedValues: [
                AppConstants.DockVisibility.menuOnly,
                AppConstants.DockVisibility.dockOnly,
                AppConstants.DockVisibility.both,
            ]),
            portableBool(launchAtLogin),
            portableString(appearancePreference, allowedValues: [
                AppConstants.Appearance.system,
                AppConstants.Appearance.light,
                AppConstants.Appearance.dark,
            ]),
            portableBool(streamerModeEnabled),
            portableBool(sponsorLinksEnabled),
            portableBool(shareDiagnosticsEnabled),
            portableBool(updateCheckEnabled),
            portableString(updateChannel, allowedValues: ["stable", "nightly"]),
            // Music monitor / song commands
            portableBool(currentSongCommandEnabled),
            portableBool(lastSongCommandEnabled),
            portableBool(commandsLiveOnly),
            portableData(customCommands, format: .customCommands),
            portableBool(songCommandSongLinkEnabled),
            portableDouble(songCommandGlobalCooldown, in: 0...30, step: 5),
            portableDouble(songCommandUserCooldown, in: 0...60, step: 5),
            portableString(songCommandAliases),
            portableDouble(lastSongCommandGlobalCooldown, in: 0...30, step: 5),
            portableDouble(lastSongCommandUserCooldown, in: 0...60, step: 5),
            portableString(lastSongCommandAliases),
            // WolfWave info command
            portableBool(wolfwaveCommandEnabled),
            portableDouble(wolfwaveCommandGlobalCooldown, in: 0...30, step: 5),
            portableDouble(wolfwaveCommandUserCooldown, in: 0...60, step: 5),
            portableString(wolfwaveCommandAliases),
            portableString(wolfwaveCommandReplyStyle, allowedValues: [
                "credit", "howto", "pitch", "short",
            ]),
            // Discord Rich Presence (local IPC, no account/login)
            portableBool(discordPresenceEnabled),
            portableBool(discordButton1Enabled),
            portableString(discordButton1Label),
            portableBool(discordButton2Enabled),
            portableString(discordButton2Label),
            portableBool(discordButtonsEnabled),
            portableBool(discordPlaylistEnabled),
            portableBool(discordPlaylistShowName),
            portableString(discordPlaylistStyle, allowedValues: ["artistLine", "iconTooltip"]),
            portableBool(discordShowIdleStatus),
            portableBool(discordClearWhilePaused),
            // Stream widgets / WebSocket (local server; auth token auto-regenerates)
            portableBool(websocketEnabled),
            portableBool(streamDeckControlEnabled),
            portablePort(websocketServerPort),
            portableBool(widgetHTTPEnabled),
            portablePort(widgetPort),
            portableString(widgetTheme, allowedValues: AppConstants.Widget.themes),
            portableString(widgetLayout, allowedValues: AppConstants.Widget.layouts),
            portableString(widgetTextColor),
            portableString(widgetBackgroundColor),
            portableString(widgetFontFamily),
            // Song requests
            portableBool(songRequestEnabled),
            portableInt(songRequestMaxQueueSize, allowedValues: [5, 10, 15, 20, 25, 50]),
            portableInt(songRequestPerUserLimit, allowedValues: [1, 2, 3, 5, 10, 15, 20]),
            portableBool(songRequestFairShare),
            portableString(songRequestPriorityMode, allowedValues: ["off", "cooldownSkip", "queueJump"]),
            portableBool(songRequestSubscriberOnly),
            portableBool(songRequestAutoAdvance),
            portableBool(songRequestAutoplayWhenEmpty),
            portableBool(songRequestApprovalRequired),
            portableData(songRequestBlocklist, format: .songRequestBlocklist),
            portableBool(srCommandEnabled),
            portableBool(queueCommandEnabled),
            portableBool(myQueueCommandEnabled),
            portableBool(skipCommandEnabled),
            portableBool(clearQueueCommandEnabled),
            portableString(srCommandAliases),
            portableString(queueCommandAliases),
            portableString(myQueueCommandAliases),
            portableString(skipCommandAliases),
            portableString(clearQueueCommandAliases),
            portableBool(songListCommandEnabled),
            portableString(songListCommandAliases),
            portableString(songRequestSongListURL),
            portableDouble(songRequestGlobalCooldown, in: 0...30, step: 5),
            portableDouble(songRequestUserCooldown, in: 0...60, step: 5),
            portableString(songRequestFallbackPlaylist),
            portableBool(songRequestHoldEnabled),
            portableString(songRequestChatAudience, allowedValues: [
                "everyone", "subscribers", "vipsAndSubs", "modsOnly",
            ]),
            portableBool(songRequestChannelPointsEnabled),
            portableInt(
                songRequestChannelPointsCost,
                allowedValues: [100, 250, 500, 1_000, 2_500, 5_000]
            ),
            portableBool(songRequestBitsEnabled),
            portableInt(songRequestBitsMinimum, allowedValues: [1, 50, 100, 200, 500, 1_000]),
            portableBool(songRequestBitsBoostEnabled),
            portableBool(songRequestDisabledReplyEnabled),
            portableString(songRequestPolicyMode, allowedValues: [
                "open", "subsOnly", "channelPointsOnly", "custom",
            ]),
            portableString(songRequestLimitStackMode, allowedValues: ["highest", "stacked"]),
            portableInt(songRequestLimitSubscriber, allowedValues: [1, 2, 3, 5, 10, 15, 20]),
            portableInt(songRequestLimitVIP, allowedValues: [1, 2, 3, 5, 10, 15, 20]),
            portableInt(songRequestLimitModerator, allowedValues: [1, 2, 3, 5, 10, 15, 20]),
            // Vote skip
            portableBool(voteSkipEnabled),
            portableInt(voteSkipMinVotes, allowedValues: [2, 3, 5, 7, 10]),
            portableInt(voteSkipWindowSeconds, allowedValues: [30, 60, 90, 120]),
            portableDouble(voteSkipSessionCooldown, in: 0...120, step: 15),
            portableBool(voteSkipSubscriberOnly),
            portableBool(voteSkipCommandEnabled),
            portableString(voteSkipCommandAliases),
            portableBool(voteSkipUsePolls),
            portableInt(voteSkipPollDuration, allowedValues: [30, 60, 90, 120, 180, 300]),
            // Notifications
            portableBool(songChangeNotificationsEnabled),
            portableBool(skipVoteStartedNotificationsEnabled),
            portableBool(skipVotePassedNotificationsEnabled),
            // History & stats
            portableBool(listeningHistoryEnabled),
            portableBool(statsEnabled),
            portableBool(statsCommandEnabled),
            portableDouble(statsCommandGlobalCooldown, in: 0...60, step: 5),
            portableDouble(statsCommandUserCooldown, in: 0...60, step: 5),
            portableString(statsCommandAliases),
            portableString(statsCommandWindow, allowedValues: ["today", "session", "week", "allTime"]),
            portableStringList(statsCommandParts, allowedValues: [
                "plays", "listeningTime", "topTrack", "topArtist",
            ]),
            portableInt(historyRetentionDays, allowedValues: [0, 7, 30, 90, 180, 365]),
        ]

        /// Keys safe to write to a backup, derived from the validation schema so
        /// classification and validation cannot drift into separate lists.
        static let exportableKeys: [String] = exportablePreferences.map(\.key)

        /// `exportablePreferences` keyed for lookup.
        private static let exportableRulesByKey: [String: ExportedValueRule] =
            Dictionary(uniqueKeysWithValues: exportablePreferences.map { ($0.key, $0.rule) })

        /// The declared value domain for `key`, or nil when the key is not
        /// portable (and so has no schema).
        ///
        /// Import validation is not the only consumer. `Preferences.resolvedInt`
        /// and `Preferences.resolvedDouble` clamp live reads against the same
        /// domains, so the allowed values for a setting are declared exactly
        /// once. A picker's tag list and the rule here disagreeing is precisely
        /// the bug class this exists to prevent.
        static func exportRule(for key: String) -> ExportedValueRule? {
            exportableRulesByKey[key]
        }

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
            twitchPendingImportedChannelName,
            twitchReauthNeeded,
        ]

        /// Per-install runtime/UI state that must never travel in a backup:
        /// permission caches, last-seen markers, locally-derived status, and
        /// server-side resource IDs that belong to one specific account. These
        /// regenerate on the target machine.
        static let runtimeStateKeys: [String] = [
            lastResolvedMusicPermission,
            lastLaunchCrashed,
            lastCrashSummary,
            selectedSettingsSection,
            hasCompletedOnboarding,
            diagnosticsLaunchCount,
            updateSkippedVersion,
            lastSeenWhatsNewVersion,
            songRequestChannelPointsRewardID,
            songRequestChannelPointsRewardIdentity,
            songRequestRedemptionStatus,
            customCommandAnnounceStatus,
            songRequestSetupComplete,
            songRequestPlaylistStatus,
            songRequestPlaylistID,
        ] + debugKeys

        /// Canonical default values for settings whose default was otherwise
        /// typed twice: once as an `@AppStorage` seed in a settings view and
        /// again as the `default:` argument to a `Preferences.*` read in the
        /// owning service. Referencing these from both sides keeps the two in
        /// lockstep. Only keys whose two copies already agreed are listed here.
        enum Defaults {
            static let updateCheckEnabled = true
            static let sponsorLinksEnabled = true
            static let voteSkipMinVotes = 3
            static let voteSkipWindowSeconds = 60
            static let voteSkipSessionCooldown: Double = 30
            static let voteSkipPollDuration = 60
            static let songRequestMaxQueueSize = 10
            static let songRequestPerUserLimit = 2
            static let songRequestFairShare = true
            static let songRequestChannelPointsCost = 500
            static let songRequestBitsMinimum = 100
            static let streamDeckControlEnabled = true
        }
    }
}
