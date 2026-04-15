//
//  WolfWaveApp.swift
//  wolfwave
//
//  Created by MrDemonWolf, Inc. on 1/17/26.
//

/// WolfWave — macOS menu bar app bridging Apple Music to Twitch, Discord, and stream widgets.

import AppKit
import SwiftUI
import UserNotifications

// MARK: - App Entry Point

/// SwiftUI entry point. Runs as a menu bar app with a Settings scene.
@main
struct WolfWaveApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    /// True when the app is launched as a test host by xcodebuild.
    static let isRunningTests = ProcessInfo.processInfo.environment["XCTestBundlePath"] != nil

    var body: some Scene {
        Settings {
            if !Self.isRunningTests {
                SettingsView()
            }
        }
    }
}


// MARK: - App Delegate

/// Orchestrates the menu bar, services, and window lifecycle.
///
/// Behavior is split across focused extension files:
/// - `AppDelegate+MenuBar.swift` — status item, menu construction, toggle actions
/// - `AppDelegate+Windows.swift` — settings/onboarding/whatsNew windows, dock visibility
/// - `AppDelegate+Services.swift` — service setup, notification observers, playback delegate
class AppDelegate: NSObject, NSApplicationDelegate {
    static weak var shared: AppDelegate?

    // MARK: - Properties

    var statusItem: NSStatusItem?
    var playbackSourceManager: PlaybackSourceManager?
    var settingsWindow: NSWindow?
    var onboardingWindow: NSWindow?
    var whatsNewWindow: NSWindow?
    var twitchService: TwitchChatService?
    var discordService: DiscordRPCService?
    var sparkleUpdater: SparkleUpdaterService?
    var websocketServer: WebSocketServerService?
    var songRequestService: SongRequestService?
    var notificationObservers: [Any] = []

    var currentSong: String?
    var currentArtist: String?
    var currentAlbum: String?
    var currentDuration: TimeInterval = 0
    var currentElapsed: TimeInterval = 0
    var lastSong: String?
    var lastArtist: String?

    var currentDockVisibilityMode: String {
        UserDefaults.standard.string(forKey: AppConstants.UserDefaults.dockVisibility)
            ?? AppConstants.DockVisibility.default
    }

    var appName: String {
        Bundle.main.infoDictionary?["CFBundleDisplayName"] as? String
            ?? Bundle.main.infoDictionary?["CFBundleName"] as? String
            ?? AppConstants.AppInfo.displayName
    }

    // MARK: - Lifecycle

    /// Initializes all services, registers observers, and shows onboarding or validates tokens.
    func applicationDidFinishLaunching(_ notification: Notification) {
        AppDelegate.shared = self

        // Skip full app setup when running unit tests to prevent windows from
        // appearing and services (WebSocket, Discord) from starting.
        if WolfWaveApp.isRunningTests {
            Log.debug("AppDelegate: Running under XCTest — skipping service setup", category: "App")
            return
        }

        setupStatusItem()
        setupMenu()
        setupMusicMonitor()
        setupTwitchService()
        setupDiscordService()
        setupWebSocketServer()
        setupPowerStateMonitor()
        setupSparkleUpdater()
        setupSongRequestService()
        setupNotificationObservers()
        initializeTrackingState()
        applyInitialDockVisibility()

        // Defer onboarding and What's New past the initial layout pass
        // to avoid "layoutSubtreeIfNeeded on a view already being laid out" warning
        DispatchQueue.main.async { [weak self] in
            Log.debug("AppDelegate: hasCompletedOnboarding = \(OnboardingViewModel.hasCompletedOnboarding)", category: "App")

            if !OnboardingViewModel.hasCompletedOnboarding {
                self?.showOnboarding()
            } else {
                Task { [weak self] in
                    await self?.validateTwitchTokenOnBoot()
                }
            }

            self?.checkWhatsNew()
        }
    }

    /// Removes all stored notification observers and tears down services.
    func applicationWillTerminate(_ notification: Notification) {
        notificationObservers.forEach { NotificationCenter.default.removeObserver($0) }
        notificationObservers.removeAll()
    }

    /// Reopens the Settings window when the dock icon is clicked.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if let onboarding = onboardingWindow, onboarding.isVisible {
            onboarding.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        } else {
            openSettings()
        }
        return false
    }

    // MARK: - Track Display Updates

    /// Posts a `nowPlayingChanged` notification for settings view observers.
    func postNowPlayingUpdate(song: String?, artist: String?, album: String?) {
        DispatchQueue.main.async {
            var userInfo: [String: Any] = [:]
            if let song { userInfo["track"] = song }
            if let artist { userInfo["artist"] = artist }
            if let album { userInfo["album"] = album }
            NotificationCenter.default.post(
                name: NSNotification.Name(AppConstants.Notifications.nowPlayingChanged),
                object: nil,
                userInfo: userInfo.isEmpty ? nil : userInfo
            )
        }
    }

    // MARK: - Song Info Provider

    /// Returns `true` if Apple Music is currently running.
    private func isMusicAppOpen() -> Bool {
        NSWorkspace.shared.runningApplications.contains {
            $0.bundleIdentifier == AppConstants.Music.bundleIdentifier
        }
    }

    /// Returns a formatted string with the current track for Twitch bot commands.
    func getCurrentSongInfo() -> String {
        guard isMusicAppOpen() else { return "🐺 Please open Apple Music" }
        guard let song = currentSong, let artist = currentArtist else { return "🐺 No music playing" }
        return "🐺 Playing: \(song) by \(artist)"
    }

    /// Returns a formatted string with the previously played track for Twitch bot commands.
    func getLastSongInfo() -> String {
        guard isMusicAppOpen() else { return "🐺 Please open Apple Music" }
        guard let song = lastSong, let artist = lastArtist else {
            return "🐺 No previous tracks yet, keep the music flowing!"
        }
        return "🐺 Previous: \(song) by \(artist)"
    }
}
