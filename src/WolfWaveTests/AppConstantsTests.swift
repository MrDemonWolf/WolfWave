//
//  AppConstantsTests.swift
//  wolfwave
//
//  Created by MrDemonWolf, Inc. on 1/17/26.
//

import Testing
import Foundation
@testable import WolfWave

/// Test suite verifying AppConstants are defined correctly
@Suite("App Constants Tests")
struct AppConstantsTests {
    
    // MARK: - App Info Tests
    
    @Test("App info constants are defined")
    func testAppInfoConstants() async throws {
        #expect(!AppConstants.AppInfo.bundleIdentifier.isEmpty)
        #expect(!AppConstants.AppInfo.displayName.isEmpty)
        #expect(AppConstants.AppInfo.bundleIdentifier == "com.mrdemonwolf.wolfwave")
        #expect(AppConstants.AppInfo.displayName == "WolfWave")
    }
    
    // MARK: - Notification Names Tests
    
    @Test("Notification names are defined")
    func testNotificationNames() async throws {
        #expect(!AppConstants.Notifications.trackingSettingChanged.isEmpty)
        #expect(!AppConstants.Notifications.dockVisibilityChanged.isEmpty)
        #expect(!AppConstants.Notifications.twitchReauthNeededChanged.isEmpty)
        #expect(!AppConstants.Notifications.discordPresenceChanged.isEmpty)
        #expect(!AppConstants.Notifications.discordStateChanged.isEmpty)
        #expect(!AppConstants.Notifications.nowPlayingChanged.isEmpty)
        #expect(!AppConstants.Notifications.updateStateChanged.isEmpty)
        #expect(!AppConstants.Notifications.websocketServerChanged.isEmpty)
        #expect(!AppConstants.Notifications.websocketServerStateChanged.isEmpty)
        #expect(!AppConstants.Notifications.powerStateChanged.isEmpty)
        #expect(!AppConstants.Notifications.twitchConnectionStateChanged.isEmpty)
    }
    
    // MARK: - UserDefaults Keys Tests
    
    @Test("UserDefaults keys are defined")
    func testUserDefaultsKeys() async throws {
        #expect(!AppConstants.UserDefaults.trackingEnabled.isEmpty)
        #expect(!AppConstants.UserDefaults.dockVisibility.isEmpty)
        #expect(!AppConstants.UserDefaults.twitchReauthNeeded.isEmpty)
        #expect(!AppConstants.UserDefaults.selectedSettingsSection.isEmpty)
        #expect(!AppConstants.UserDefaults.websocketEnabled.isEmpty)
        #expect(!AppConstants.UserDefaults.currentSongCommandEnabled.isEmpty)
        #expect(!AppConstants.UserDefaults.lastSongCommandEnabled.isEmpty)
        #expect(!AppConstants.UserDefaults.broadcasterBypassCooldowns.isEmpty)
    }
    
    // MARK: - Dock Visibility Tests
    
    @Test("Dock visibility modes are defined")
    func testDockVisibilityModes() async throws {
        #expect(AppConstants.DockVisibility.menuOnly == "menuOnly")
        #expect(AppConstants.DockVisibility.dockOnly == "dockOnly")
        #expect(AppConstants.DockVisibility.both == "both")
        #expect(AppConstants.DockVisibility.default == "both")
    }
    
    // MARK: - Keychain Tests
    
    @Test("Keychain service identifier is defined")
    func testKeychainService() async throws {
        #expect(!AppConstants.Keychain.service.isEmpty)
        #expect(AppConstants.Keychain.service == "com.mrdemonwolf.wolfwave")
    }
    
    // MARK: - Music App Tests
    
    @Test("Music app constants are defined")
    func testMusicAppConstants() async throws {
        #expect(AppConstants.Music.bundleIdentifier == "com.apple.Music")
        #expect(!AppConstants.Music.playerInfoNotification.isEmpty)
    }
    
    // MARK: - Twitch Tests
    
    @Test("Twitch constants are defined")
    func testTwitchConstants() async throws {
        #expect(AppConstants.Twitch.apiBaseURL == "https://api.twitch.tv/helix")
        #expect(AppConstants.Twitch.settingsSection == "twitchIntegration")
        #expect(AppConstants.Twitch.sessionWelcomeTimeout == 10.0)
        #expect(AppConstants.Twitch.maxMessageLength == 500)
        #expect(AppConstants.Twitch.messageTruncationSuffix == "...")
        #expect(!AppConstants.Twitch.connectionMessage.isEmpty)
        #expect(AppConstants.Twitch.maxReconnectionAttempts == 5)
        #expect(AppConstants.Twitch.maxNetworkReconnectCycles == 5)
        #expect(AppConstants.Twitch.networkReconnectCooldown == 60.0)
        #expect(AppConstants.Twitch.maxMessageRetries == 3)
        #expect(AppConstants.Twitch.connectionMessageDelay == 1.5)
    }
    
    // MARK: - Widget Tests
    
    @Test("Widget constants are defined")
    func testWidgetConstants() async throws {
        #expect(AppConstants.Widget.recommendedWidth == 500)
        #expect(AppConstants.Widget.recommendedHeight == 120)
        #expect(!AppConstants.Widget.themes.isEmpty)
        #expect(!AppConstants.Widget.layouts.isEmpty)
        #expect(!AppConstants.Widget.builtInFonts.isEmpty)
        #expect(!AppConstants.Widget.googleFonts.isEmpty)
    }
    
    // MARK: - Discord Tests
    
    @Test("Discord constants are defined")
    func testDiscordConstants() async throws {
        #expect(AppConstants.Discord.settingsSection == "discordPresence")
        #expect(AppConstants.Discord.ipcSocketPrefix == "discord-ipc-")
        #expect(AppConstants.Discord.ipcSocketSlots == 10)
        #expect(AppConstants.Discord.rpcVersion == 1)
        #expect(AppConstants.Discord.listeningActivityType == 2)
        #expect(AppConstants.Discord.reconnectBaseDelay == 5.0)
        #expect(AppConstants.Discord.reconnectMaxDelay == 60.0)
        #expect(AppConstants.Discord.availabilityPollInterval == 15.0)
    }
    
    // MARK: - Update Checker Tests
    
    @Test("Update checker constants are defined")
    func testUpdateCheckerConstants() async throws {
        #expect(AppConstants.Update.checkInterval == 86400) // 24 hours
        #expect(AppConstants.Update.requestTimeout == 15.0)
        #expect(AppConstants.Update.launchCheckDelay == 10.0)
    }
    
    // MARK: - URLs Tests
    
    @Test("URLs are defined and valid")
    func testURLs() async throws {
        // Verify URLs are defined
        #expect(!AppConstants.URLs.docs.isEmpty)
        #expect(!AppConstants.URLs.privacyPolicy.isEmpty)
        #expect(!AppConstants.URLs.termsOfService.isEmpty)
        #expect(!AppConstants.URLs.github.isEmpty)
        #expect(!AppConstants.URLs.githubReleasesAPI.isEmpty)
        #expect(!AppConstants.URLs.githubReleases.isEmpty)
        
        // Verify URLs are valid
        #expect(URL(string: AppConstants.URLs.docs) != nil)
        #expect(URL(string: AppConstants.URLs.privacyPolicy) != nil)
        #expect(URL(string: AppConstants.URLs.termsOfService) != nil)
        #expect(URL(string: AppConstants.URLs.github) != nil)
        #expect(URL(string: AppConstants.URLs.githubReleasesAPI) != nil)
        #expect(URL(string: AppConstants.URLs.githubReleases) != nil)
    }
    
    // MARK: - WebSocket Server Tests
    
    @Test("WebSocket server constants are defined")
    func testWebSocketServerConstants() async throws {
        #expect(AppConstants.WebSocketServer.defaultPort == 8765)
        #expect(AppConstants.WebSocketServer.minPort == 1024)
        #expect(AppConstants.WebSocketServer.maxPort == 65535)
        #expect(AppConstants.WebSocketServer.progressBroadcastInterval == 1.0)
        #expect(AppConstants.WebSocketServer.retryDelay == 5.0)
        #expect(AppConstants.WebSocketServer.widgetDefaultPort == 8766)
    }
    
    // MARK: - Dispatch Queues Tests
    
    @Test("Dispatch queue labels are defined")
    func testDispatchQueueLabels() async throws {
        #expect(!AppConstants.DispatchQueues.musicPlaybackMonitor.isEmpty)
        #expect(!AppConstants.DispatchQueues.twitchNetworkMonitor.isEmpty)
        #expect(!AppConstants.DispatchQueues.discordIPC.isEmpty)
        #expect(!AppConstants.DispatchQueues.websocketServer.isEmpty)
    }
    
    // MARK: - UI Dimensions Tests
    
    @Test("UI dimensions are reasonable")
    func testUIDimensions() async throws {
        #expect(AppConstants.UI.settingsWidth > 0)
        #expect(AppConstants.UI.settingsHeight > 0)
        #expect(AppConstants.UI.settingsWidth == 520)
        #expect(AppConstants.UI.settingsHeight == 560)
    }
    
    // MARK: - Settings UI Tests
    
    @Test("Settings UI constants are defined")
    func testSettingsUIConstants() async throws {
        #expect(!AppConstants.SettingsUI.defaultAppName.isEmpty)
        #expect(AppConstants.SettingsUI.minWidth > 0)
        #expect(AppConstants.SettingsUI.minHeight > 0)
        #expect(AppConstants.SettingsUI.maxWidth > AppConstants.SettingsUI.minWidth)
        #expect(AppConstants.SettingsUI.maxHeight > AppConstants.SettingsUI.minHeight)
    }
    
    // MARK: - Power Management Tests
    
    @Test("Power management constants are defined")
    func testPowerManagementConstants() async throws {
        #expect(AppConstants.PowerManagement.reducedMusicCheckInterval > 0)
        #expect(AppConstants.PowerManagement.reducedDiscordPollInterval > 0)
        #expect(AppConstants.PowerManagement.reducedProgressBroadcastInterval > 0)
        
        // Reduced intervals should be longer than normal
        #expect(AppConstants.PowerManagement.reducedMusicCheckInterval == 15.0)
        #expect(AppConstants.PowerManagement.reducedDiscordPollInterval == 60.0)
        #expect(AppConstants.PowerManagement.reducedProgressBroadcastInterval == 3.0)
    }
    
    // MARK: - Onboarding UI Tests
    
    @Test("Onboarding UI constants are defined")
    func testOnboardingUIConstants() async throws {
        #expect(AppConstants.OnboardingUI.windowWidth > 0)
        #expect(AppConstants.OnboardingUI.windowHeight > 0)
        #expect(AppConstants.OnboardingUI.windowWidth == 520)
        #expect(AppConstants.OnboardingUI.windowHeight == 540)
    }
    
    // MARK: - Menu Labels Tests
    
    @Test("Menu labels are defined")
    func testMenuLabels() async throws {
        #expect(!AppConstants.MenuLabels.settings.isEmpty)
        #expect(!AppConstants.MenuLabels.quit.isEmpty)
        #expect(AppConstants.MenuLabels.settings == "Settings...")
        #expect(AppConstants.MenuLabels.quit == "Quit")
    }
}
