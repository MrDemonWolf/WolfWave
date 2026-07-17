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

        /// Version whose feature set the What's New window describes. Bump this
        /// ONLY on releases that add user-facing features, never on patch or
        /// bug-fix releases, so the window auto-opens only when there is
        /// something new worth showing. Keep it `<= shortVersion`.
        static let whatsNewVersion = "2.0.0"

        /// Build number string (`CFBundleVersion`) with a safe fallback for
        /// contexts where the Info.plist key is absent. Sparkle uses this as
        /// its primary version comparator.
        static let buildNumber = infoPlistString(
            "CFBundleVersion",
            fallback: "0"
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

    // `Notifications` string keys live in AppConstants+Notifications.swift

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

        /// Stable identifier for the "Twitch authentication expired" banner.
        /// Reused so a second re-auth prompt in the same session replaces the
        /// first rather than stacking a duplicate in Notification Center.
        static let twitchReauthIdentifier = "com.mrdemonwolf.wolfwave.notification.twitchReauth"
    }

    // MARK: - UserDefaults Keys

    // `UserDefaults` keys live in AppConstants+UserDefaults.swift

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
        /// Legacy release-build keychain service string. `KeychainService` derives
        /// its actual service from `Bundle.main.bundleIdentifier` (which equals this
        /// on release builds) and does not read this constant.
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
        /// Branded and explanatory so the playlist reads as WolfWave's, not a
        /// stray user playlist. (Apple builds the cover art from the songs;
        /// custom playlist artwork can't be set through the Apple Music API or
        /// Music's AppleScript, so the author name and description carry the
        /// branding instead.)
        static let requestsPlaylistDescription =
            "Live song requests from your Twitch chat, collected by WolfWave. Viewers add tracks with !sr and they play from here. Safe to clear anytime."

        /// Author shown on the WolfWave Requests playlist. The Apple Music API's
        /// create-playlist call accepts `authorDisplayName`, so the playlist's
        /// creator reads as "WolfWave" in Music. This is the one piece of real,
        /// API-supported branding available for the playlist.
        static let requestsPlaylistAuthor = "WolfWave"
    }

    // MARK: - Twitch Integration

    // `Twitch` constants live in AppConstants+Twitch.swift

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

    // `Discord` constants live in AppConstants+Discord.swift

    // MARK: - Sparkle Updater

    /// Sparkle automatic update configuration.
    enum Update {
        /// Interval between periodic update checks (24 hours in seconds)
        static let checkInterval: TimeInterval = 86400

        /// Appcast feed for the opt-in Nightly channel.
        ///
        /// Served from a single rolling GitHub prerelease (fixed tag `nightly`)
        /// whose `appcast-nightly.xml` asset is re-uploaded on every nightly CI
        /// run, so the URL is stable. Signed with the same Sparkle EdDSA key as
        /// the stable feed, so the installed app verifies either feed.
        static let nightlyFeedURL = "https://github.com/MrDemonWolf/wolfwave/releases/download/nightly/appcast-nightly.xml"
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

    // `URLs` live in AppConstants+URLs.swift

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
