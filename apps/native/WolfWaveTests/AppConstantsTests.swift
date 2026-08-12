//
//  AppConstantsTests.swift
//  WolfWave
//
//  Created by Nathanial Henniges on 2026-02-13.
//  Copyright © 2026 MrDemonWolf, Inc. All rights reserved.
//

import Testing
import Foundation
@testable import WolfWave

/// Test suite verifying AppConstants are defined correctly
@MainActor
@Suite("App Constants Tests")
struct AppConstantsTests {
    
    // MARK: - App Info Tests
    
    @Test("App info constants are defined")
    func testAppInfoConstants() async throws {
        #expect(!AppConstants.AppInfo.bundleIdentifier.isEmpty)
        #expect(!AppConstants.AppInfo.displayName.isEmpty)
        // AppInfo identifies the release product; runtime isolation uses Bundle.main.bundleIdentifier.
        #expect(AppConstants.AppInfo.bundleIdentifier == "com.mrdemonwolf.wolfwave")
        #if DEBUG
        #expect(AppConstants.AppInfo.displayName == "WolfWave Dev")
        #else
        #expect(AppConstants.AppInfo.displayName == "WolfWave")
        #endif
    }

    @Test("Version and build number constants are defined")
    func testVersionAndBuildNumber() async throws {
        // Hosted tests run inside the app product, so the real Info.plist values
        // are present; the "0.0.0"/"0" fallbacks only apply to stripped bundles.
        #expect(!AppConstants.AppInfo.shortVersion.isEmpty)
        #expect(!AppConstants.AppInfo.buildNumber.isEmpty)
        // The build number is Sparkle's primary comparator; it must be numeric.
        #expect(Int(AppConstants.AppInfo.buildNumber) != nil)
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
        #expect(!AppConstants.Notifications.musicPermissionDenied.isEmpty)
        #expect(AppConstants.Notifications.allNames.contains(AppConstants.Notifications.musicPermissionDenied))
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
    }

    @Test("New command alias keys are registered in allKeys")
    func testAliasKeysRegistered() async throws {
        #expect(AppConstants.UserDefaults.allKeys.contains(AppConstants.UserDefaults.songCommandAliases))
        #expect(AppConstants.UserDefaults.allKeys.contains(AppConstants.UserDefaults.lastSongCommandAliases))
        #expect(AppConstants.UserDefaults.allKeys.contains(AppConstants.UserDefaults.statsCommandAliases))
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
        #expect(AppConstants.Widget.recommendedDimensionsText(for: "Horizontal") == "532 x 132")
        #expect(AppConstants.Widget.recommendedDimensionsText(for: "Vertical") == "252 x 312")
        #expect(AppConstants.Widget.recommendedDimensionsText(for: "Compact") == "382 x 88")
        #expect(AppConstants.Widget.recommendedDimensionsText(for: "Vinyl") == "292 x 332")
        #expect(AppConstants.Widget.recommendedDimensionsText(for: "Classic") == "472 x 144")
        #expect(!AppConstants.Widget.themes.isEmpty)
        #expect(AppConstants.Widget.themes.count == 5)
        #expect(!AppConstants.Widget.layouts.isEmpty)
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
    }
    
    // MARK: - URLs Tests
    
    @Test("URLs are defined and valid")
    func testURLs() async throws {
        // Verify URLs are defined
        #expect(!AppConstants.URLs.docs.isEmpty)
        #expect(!AppConstants.URLs.privacyPolicy.isEmpty)
        #expect(!AppConstants.URLs.termsOfService.isEmpty)
        #expect(!AppConstants.URLs.github.isEmpty)
        #expect(!AppConstants.URLs.githubReleases.isEmpty)
        #expect(!AppConstants.URLs.sponsorUser.isEmpty)
        #expect(!AppConstants.URLs.githubSponsors.isEmpty)

        // Verify URLs are valid
        #expect(URL(string: AppConstants.URLs.docs) != nil)
        #expect(URL(string: AppConstants.URLs.privacyPolicy) != nil)
        #expect(URL(string: AppConstants.URLs.termsOfService) != nil)
        #expect(URL(string: AppConstants.URLs.github) != nil)
        #expect(URL(string: AppConstants.URLs.githubReleases) != nil)
        #expect(URL(string: AppConstants.URLs.githubSponsors) != nil)
        #expect(AppConstants.URLs.githubSponsors.hasPrefix("https://github.com/sponsors/"))
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
        #expect(!AppConstants.DispatchQueues.websocketServer.isEmpty)
    }
    
    // MARK: - Settings Window Constant Tests

    @Test("Settings sidebar fits the minimum window")
    func testSettingsSidebarFitsMinimumWindow() {
        // The fixed sidebar must fit the longest label while leaving the detail
        // pane at least half of the minimum-width Settings window.
        #expect(AppConstants.SettingsUI.sidebarWidth >= 180)
        #expect(AppConstants.SettingsUI.sidebarWidth <= AppConstants.SettingsUI.minWidth / 2)
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
    
    // MARK: - Onboarding Window Constant Tests
    
    @Test("Onboarding window fits a 720p display with the Dock")
    func testOnboardingWindowFits720pWithDock() {
        #expect(AppConstants.OnboardingUI.windowWidth <= 1280)
        #expect(AppConstants.OnboardingUI.windowHeight <= 626)
    }
    
    // MARK: - Menu Labels Tests
    
    @Test("Menu labels are defined")
    func testMenuLabels() async throws {
        #expect(!AppConstants.MenuLabels.settings.isEmpty)
        #expect(!AppConstants.MenuLabels.quit.isEmpty)
        #expect(AppConstants.MenuLabels.settings == "Settings\u{2026}")
        #expect(AppConstants.MenuLabels.quit == "Quit WolfWave")
    }
}
