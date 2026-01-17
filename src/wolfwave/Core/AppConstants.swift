import Foundation
import AppKit

enum AppConstants {
    // MARK: - App Identifiers
    
    enum AppInfo {
        static let bundleIdentifier = "com.mrdemonwolf.wolfwave"
        static let displayName = "WolfWave"
    }
    
    // MARK: - Notifications
    
    enum Notifications {
        static let trackingSettingChanged = "TrackingSettingChanged"
        static let dockVisibilityChanged = "DockVisibilityChanged"
        static let twitchReauthNeededChanged = "TwitchReauthNeededChanged"
    }
    
    // MARK: - UserDefaults Keys
    
    enum UserDefaults {
        static let trackingEnabled = "trackingEnabled"
        static let dockVisibility = "dockVisibility"
        static let twitchReauthNeeded = "twitchReauthNeeded"
        static let selectedSettingsSection = "selectedSettingsSection"
        static let websocketEnabled = "websocketEnabled"
        static let websocketURI = "websocketURI"
        static let currentSongCommandEnabled = "currentSongCommandEnabled"
        static let lastSongCommandEnabled = "lastSongCommandEnabled"
    }
    
    // MARK: - Dock Visibility Modes
    
    enum DockVisibility {
        static let menuOnly = "menuOnly"
        static let dockOnly = "dockOnly"
        static let both = "both"
        static let `default` = "both"
    }
    
    // MARK: - Keychain Service Identifier
    
    enum Keychain {
        static let service = "com.mrdemonwolf.wolfwave"
    }
    
    // MARK: - Music App Integration
    
    enum Music {
        static let bundleIdentifier = "com.apple.Music"
        static let playerInfoNotification = "com.apple.Music.playerInfo"
    }
    
    // MARK: - Twitch Integration
    
    enum Twitch {
        static let apiBaseURL = "https://api.twitch.tv/helix"
        static let settingsSection = "twitchIntegration"
    }
    
    // MARK: - Dispatch Queue Labels
    
    enum DispatchQueues {
        static let musicPlaybackMonitor = "com.mrdemonwolf.wolfwave.musicplaybackmonitor"
        static let twitchNetworkMonitor = "com.mrdemonwolf.wolfwave.networkmonitor"
    }
    
    // MARK: - UI Dimensions
    
    enum UI {
        static let settingsWindowWidth: CGFloat = 520
        static let settingsWindowHeight: CGFloat = 560
        static let settingsWidth: CGFloat = 520
        static let settingsHeight: CGFloat = 560
    }
    
    // MARK: - Animation & Timing
    
    enum Timing {
        static let windowCloseDelay: TimeInterval = 0.1
        static let notificationDelay: TimeInterval = 0.5
        static let twitchAutoJoinDelay: TimeInterval = 2.0
    }
    
    // MARK: - Menu Item Indices
    
    enum MenuItemIndex {
        static let header = 0
        static let song = 1
        static let artist = 2
        static let album = 3
    }
    
    // MARK: - Settings UI
    
    enum SettingsUI {
        static let defaultAppName = "WolfWave"
        static let minWidth: CGFloat = 700
        static let minHeight: CGFloat = 500
        static let sidebarWidth: CGFloat = 200
    }
}
