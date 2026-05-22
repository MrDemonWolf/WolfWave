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
    ///
    /// `NSClassFromString("XCTestCase")` is the canonical, toolchain-independent
    /// detection — `XCTest.framework` is only loaded into the host process when
    /// xctest runs. The env-var fallbacks preserve behavior on older runners
    /// that did expose those variables.
    static let isRunningTests = NSClassFromString("XCTestCase") != nil
        || ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
        || ProcessInfo.processInfo.environment["XCTestBundlePath"] != nil

    var body: some Scene {
        // Settings UI is managed by AppDelegate via a hand-rolled NSWindow
        // (see AppDelegate+Windows.swift). The SwiftUI Settings scene is kept
        // empty to avoid instantiating a duplicate SettingsView when Cmd+, fires.
        Settings {
            EmptyView()
        }
    }
}


// MARK: - App Delegate

/// Orchestrates the menu bar, services, and window lifecycle.
///
/// Behavior is split across focused extension files:
/// - `AppDelegate+MenuBar.swift` — status item, menu construction, toggle actions
/// - `AppDelegate+Windows.swift` — settings/onboarding/whatsNew/about windows, dock visibility
/// - `AppDelegate+Services.swift` — service setup, notification observers, playback delegate
class AppDelegate: NSObject, NSApplicationDelegate {
    static weak var shared: AppDelegate?

    // MARK: - Properties

    var statusItem: NSStatusItem?
    var playbackSourceManager: PlaybackSourceManager?
    var settingsWindow: NSWindow?
    var onboardingWindow: NSWindow?
    var whatsNewWindow: NSWindow?
    var aboutWindow: NSWindow?
    var twitchService: TwitchChatService?
    var discordService: DiscordRPCService?
    var sparkleUpdater: SparkleUpdaterService?
    var websocketServer: WebSocketServerService?
    var songRequestService: SongRequestService?
    var historyService: ListeningHistoryService?
    var notificationObservers: [Any] = []

    var currentSong: String?
    var currentArtist: String?
    var currentAlbum: String?
    var currentPlaylist: String?
    var currentDuration: TimeInterval = 0
    var currentElapsed: TimeInterval = 0
    var lastSong: String?
    var lastArtist: String?

    /// Whether a track has been seen since launch. The first track represents
    /// music that was already playing, so its song-change notification is
    /// suppressed; every change thereafter notifies.
    var hasSeenInitialTrack = false

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
        setupHistoryService()
        setupDiagnostics()
        setupNotificationObservers()
        initializeTrackingState()
        applyInitialDockVisibility()

        // Defer onboarding and What's New past the initial layout pass
        // to avoid "layoutSubtreeIfNeeded on a view already being laid out" warning
        Task { @MainActor [weak self] in
            Log.debug("AppDelegate: hasCompletedOnboarding = \(OnboardingViewModel.hasCompletedOnboarding)", category: "App")

            if !OnboardingViewModel.hasCompletedOnboarding {
                self?.showOnboarding()
            } else {
                await self?.validateTwitchTokenOnBoot()
            }

            self?.checkWhatsNew()
        }
    }

    /// Removes all stored notification observers and tears down services.
    func applicationWillTerminate(_ notification: Notification) {
        flushCurrentPlayToHistory()
        historyService?.shutdown()
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
    func postNowPlayingUpdate(song: String?, artist: String?, album: String?, playlist: String? = nil) {
        Task { @MainActor in
            var userInfo: [String: Any] = [:]
            if let song { userInfo["track"] = song }
            if let artist { userInfo["artist"] = artist }
            if let album { userInfo["album"] = album }
            if let playlist { userInfo["playlist"] = playlist }
            NotificationCenter.default.post(
                name: .nowPlayingChanged,
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

    /// Returns a formatted listening-stats string for the `!stats` Twitch command.
    func getStatsInfo() -> String {
        historyService?.statsChatLine() ?? "🐺 Listening stats aren't turned on right now"
    }

    /// Records the currently-playing track to history if it crossed the
    /// scrobble threshold. Called when playback stops or the app terminates.
    ///
    /// `currentElapsed` holds the track's last polled playhead position, which
    /// `ListeningHistoryService` uses as the played duration.
    func flushCurrentPlayToHistory() {
        guard let song = currentSong, let artist = currentArtist else { return }
        historyService?.recordTrackChange(
            track: song,
            artist: artist,
            album: currentAlbum ?? "",
            duration: currentDuration,
            playedSeconds: currentElapsed
        )
    }
}
