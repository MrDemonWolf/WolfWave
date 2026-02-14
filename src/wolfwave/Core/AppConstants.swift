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

enum AppConstants {
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

        /// Posted when the currently playing track changes.
        /// UserInfo contains optional "track", "artist", "album" Strings. Nil values mean no track is playing.
        static let nowPlayingChanged = "NowPlayingChanged"

        /// Posted when the update checker state changes (new version found or check completed).
        static let updateStateChanged = "UpdateStateChanged"
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
        
        /// Whether "current song" bot command is enabled (Bool, default: true)
        static let currentSongCommandEnabled = "currentSongCommandEnabled"
        
        /// Whether "last song" bot command is enabled (Bool, default: true)
        static let lastSongCommandEnabled = "lastSongCommandEnabled"

        /// Whether the first-launch onboarding wizard has been completed (Bool, default: false)
        static let hasCompletedOnboarding = "hasCompletedOnboarding"

        /// Whether Discord Rich Presence is enabled (Bool, default: false)
        static let discordPresenceEnabled = "discordPresenceEnabled"

        /// Date of last update check (Date stored as TimeInterval)
        static let updateLastCheckDate = "updateLastCheckDate"

        /// Version string the user has chosen to skip (e.g. "1.1.0")
        static let updateSkippedVersion = "updateSkippedVersion"

        /// Whether automatic update checking is enabled (Bool, default: true)
        static let updateCheckEnabled = "updateCheckEnabled"
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
    }
    
    // MARK: - UI Dimensions
    
    /// Settings window dimensions in points.
    enum UI {
        static let settingsWidth: CGFloat = 520
        static let settingsHeight: CGFloat = 560
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
        static let settings = "Settings..."
        static let quit = "Quit"
    }

    // MARK: - External URLs

    /// URLs for documentation, legal pages, and external resources.
    enum URLs {
        /// Base URL for the WolfWave documentation site
        static let docs = "https://mrdemonwolf.github.io/wolfwave/docs"

        /// Privacy Policy page URL
        static let privacyPolicy = "https://mrdemonwolf.github.io/wolfwave/docs/privacy-policy"

        /// Terms of Service page URL
        static let termsOfService = "https://mrdemonwolf.github.io/wolfwave/docs/terms-of-service"

        /// GitHub repository URL
        static let github = "https://github.com/MrDemonWolf/WolfWave"

        /// GitHub Releases API endpoint for latest release
        static let githubReleasesAPI = "https://api.github.com/repos/MrDemonWolf/WolfWave/releases/latest"

        /// GitHub Releases page for latest release (browser URL)
        static let githubReleases = "https://github.com/MrDemonWolf/WolfWave/releases/latest"
    }
    
    // MARK: - Update Checker

    /// Timing constants for the automatic update checker.
    enum Update {
        /// Delay after launch before first update check (seconds)
        static let launchCheckDelay: TimeInterval = 10.0

        /// Interval between periodic update checks (24 hours)
        static let checkInterval: TimeInterval = 86400

        /// HTTP request timeout for GitHub API calls (seconds)
        static let requestTimeout: TimeInterval = 15.0
    }

    // MARK: - Settings UI

    /// Settings window configuration.
    enum SettingsUI {
        /// Default application name shown in UI
        static let defaultAppName = "WolfWave"

        /// Minimum width for settings window
        static let minWidth: CGFloat = 640

        /// Minimum height for settings window
        static let minHeight: CGFloat = 480

        /// Maximum width for settings window
        static let maxWidth: CGFloat = 900

        /// Maximum height for settings window
        static let maxHeight: CGFloat = 700

        /// Ideal width for settings window
        static let idealWidth: CGFloat = 720

        /// Ideal height for settings window
        static let idealHeight: CGFloat = 540

        /// Maximum content width for detail pane
        static let maxContentWidth: CGFloat = 560

        /// Standard horizontal padding for content sections
        static let contentPaddingH: CGFloat = 24

        /// Standard vertical padding for content sections
        static let contentPaddingV: CGFloat = 20

        /// Standard spacing between sections
        static let sectionSpacing: CGFloat = 24

        /// Standard card padding
        static let cardPadding: CGFloat = 14

        /// Standard card corner radius
        static let cardCornerRadius: CGFloat = 10
    }

    // MARK: - Onboarding UI

    /// Onboarding wizard window configuration.
    enum OnboardingUI {
        /// Width of the onboarding window
        static let windowWidth: CGFloat = 520

        /// Height of the onboarding window
        static let windowHeight: CGFloat = 500
    }
}
