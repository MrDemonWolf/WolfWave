//
//  WolfWaveApp.swift
//  WolfWave
//
//  Created by Nathanial Henniges on 2026-01-08.
//  Copyright © 2026 MrDemonWolf, Inc. All rights reserved.
//

/// WolfWave: macOS menu bar app bridging Apple Music to Twitch, Discord, and stream widgets.

import AppKit
import SwiftUI

// MARK: - App Entry Point

/// SwiftUI entry point. Runs as a menu bar app with a Settings scene.
@main
struct WolfWaveApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    /// True when the app is launched as a test host by xcodebuild.
    ///
    /// `NSClassFromString("XCTestCase")` is the canonical, toolchain-independent
    /// detection. `XCTest.framework` is only loaded into the host process when
    /// xctest runs. The env-var fallbacks preserve behavior on older runners
    /// that did expose those variables.
    static let isRunningTests = NSClassFromString("XCTestCase") != nil
        || ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
        || ProcessInfo.processInfo.environment["XCTestBundlePath"] != nil

    var body: some Scene {
        // Hidden helper window that hosts `SettingsSceneBridge`, declared BEFORE
        // the `Settings` scene. Scene order is load-bearing: a helper window
        // placed after `Settings` leaves the bridge's `openSettings` action a
        // silent no-op. It gives the AppKit entry points (tray menu, Dock menu,
        // Dock reopen, Twitch re-auth) a live SwiftUI scene tree to drive, so
        // they open Settings via the public `openSettings` environment action
        // rather than the private `showSettingsWindow:` selector (which logs
        // "Please use SettingsLink for opening the Settings scene" on macOS 14+).
        // `BridgeWindowNeutralizer` keeps this window offscreen and invisible, so
        // it never appears and never trips `applyDockVisibility`'s probe. The app
        // stays alive when this window orders out via
        // `applicationShouldTerminateAfterLastWindowClosed` returning `false`.
        Window("WolfWave Settings Bridge", id: SettingsSceneBridge.windowID) {
            SettingsSceneBridge()
        }
        .windowResizability(.contentSize)
        .defaultSize(width: 1, height: 1)
        .commandsRemoved()

        // Settings lives in SwiftUI's own `Settings` scene so SwiftUI creates
        // and drives the window's `NSToolbar`. That lets `NavigationSplitView`'s
        // sidebar toggle, tracking separator, and overflow math animate as one
        // unit, which is what finally kills the `>>` overflow flash that the
        // old hand-rolled `NSWindow` + foreign `NSToolbar` produced during the
        // sidebar collapse animation. AppDelegate still drives *when* the window
        // opens (dock-visibility activation policy, tray/reopen entry points) by
        // posting `.openSettingsRequested` to `SettingsSceneBridge`; it no longer
        // owns the window itself nor uses the private `showSettingsWindow:`
        // selector. See `apps/native/docs/sidebar-toggle-glitch-research.md`.
        Settings {
            SettingsView()
        }
        .commands {
            // Route the standard App menu's About/Settings to our AppKit
            // windows so the system main menu matches the tray when the app
            // is dock-visible.
            CommandGroup(replacing: .appInfo) {
                Button("About \(appDelegate.appName)") {
                    appDelegate.showAbout()
                }
            }
            CommandGroup(after: .appInfo) {
                Button("Check for Updates\u{2026}") {
                    appDelegate.checkForUpdatesFromMenu()
                }
            }
            // `SettingsLink` is the public macOS 14+ way to open the `Settings`
            // scene. It runs the same scene-open action that
            // `appDelegate.openSettings()` now routes through `SettingsSceneBridge`,
            // just without the private selector. It only works here because
            // `.commands` is a SwiftUI context; the tray/Dock `NSMenu` entry
            // points can't host a SwiftUI view, so they keep routing through
            // `appDelegate.openSettings()`.
            //
            // No dock-visibility handling is lost: the App menu (and its Cmd+,)
            // is only reachable when the app is already `.regular`. An
            // `.accessory` menu-only app shows no main menu and its command
            // shortcuts need a key window, so openSettings()'s `.regular` switch
            // would be a no-op on this path anyway.
            CommandGroup(replacing: .appSettings) {
                SettingsLink {
                    Text("Settings\u{2026}")
                }
                .keyboardShortcut(",", modifiers: .command)
            }
            // Mirror the tray Help submenu in the system Help menu.
            CommandGroup(replacing: .help) {
                Button("\(appDelegate.appName) Help") { appDelegate.openDocs() }
                Button("What's New") { appDelegate.showWhatsNewFromMenu() }
                Divider()
                Button("Report a Bug\u{2026}") { appDelegate.reportBug() }
                Button("Join Discord Community") { appDelegate.openCommunityDiscord() }
                Button("View on GitHub") { appDelegate.openGitHub() }
                Button("Sponsor \(appDelegate.appName)") { appDelegate.openSponsorPage() }
            }
        }
    }
}


// MARK: - App Delegate

/// Orchestrates the menu bar, services, and window lifecycle.
///
/// Behavior is split across focused extension files:
/// - `AppDelegate+MenuBar.swift`: status item, menu construction, toggle actions
/// - `AppDelegate+Windows.swift`: settings/onboarding/whatsNew/about windows, dock visibility
/// - `AppDelegate+Services.swift`: service setup, notification observers, playback delegate
class AppDelegate: NSObject, NSApplicationDelegate {
    static weak var shared: AppDelegate?

    // MARK: - Properties

    var statusItem: NSStatusItem?
    var playbackSourceManager: PlaybackSourceManager?
    // Settings is a SwiftUI `Settings` scene (see WolfWaveApp.body); SwiftUI
    // owns that window, so AppDelegate no longer holds an `NSWindow` for it.
    var onboardingWindow: NSWindow?
    var whatsNewWindow: NSWindow?
    var twitchService: TwitchChatService?
    var discordService: DiscordRPCService?
    var sparkleUpdater: SparkleUpdaterService?
    var websocketServer: WebSocketServerService?
    var songRequestService: SongRequestService?
    var skipVoteManager: SkipVoteManager?
    var historyService: ListeningHistoryService?
    var notificationObservers: [Any] = []

    /// Long-lived task consuming `discordService.stateChanges`.
    var discordStateConsumer: Task<Void, Never>?
    /// Long-lived task consuming `discordService.artworkResolutions`.
    var discordArtworkConsumer: Task<Void, Never>?
    /// Long-lived consumer of `twitchService.skipPollResults`. Cancelled on
    /// teardown / re-setup of the skip-vote manager.
    var skipPollObserverTask: Task<Void, Never>?

    /// Most-recent Discord connection state seen from the actor's stream.
    /// Used by the synchronous menu builder; updated by `discordStateConsumer`.
    var discordCachedState: DiscordRPCService.ConnectionState = .disconnected

    var currentSong: String?
    var currentArtist: String?
    var currentAlbum: String?
    var currentPlaylist: String?
    var currentDuration: TimeInterval = 0
    var currentElapsed: TimeInterval = 0
    /// `true` while the loaded track is paused in the active source. Drives
    /// the paused affordances in Discord Rich Presence, the OBS widget, and
    /// `NowPlayingHeroCard` without clearing the now-playing snapshot.
    var currentIsPaused: Bool = false
    var lastSong: String?
    var lastArtist: String?

    /// Ring buffer of recently-played tracks shown in the tray menu's
    /// "Recently Played" submenu. Mutated only on the main thread from the
    /// `PlaybackSourceDelegate` callback.
    var recentTracks = RecentTracksBuffer()

    /// Decoded album-art images keyed by `"artist|track"`. Populated lazily
    /// by the tray menu when an artwork URL is in `ArtworkService` but the
    /// bitmap hasn't been decoded yet. Bounded by track turnover.
    var albumArtCache: [String: NSImage] = [:]

    /// Whether a track has been seen since launch. The first track represents
    /// music that was already playing, so its song-change notification is
    /// suppressed; every change thereafter notifies.
    var hasSeenInitialTrack = false

    var currentDockVisibilityMode: String {
        Preferences.dockVisibility ?? AppConstants.DockVisibility.default
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
            Log.debug("AppDelegate: Running under XCTest, skipping service setup", category: "App")
            return
        }

        // Apply the stored appearance override before any UI is built so the
        // menu bar menu, status item, and onboarding adopt it from first paint.
        AppearanceController.applyStored()

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

        // Pre-warm the Apple Music permission probe off-main so the first open
        // of General and History & Stats settings doesn't pay the
        // tens-of-milliseconds Apple Events round-trip on the main thread.
        Task.detached(priority: .utility) {
            let state = MusicPermissionChecker.currentState()
            await MainActor.run { MusicPermissionCache.write(state) }
        }

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
        NotificationCenter.default.removeObserver(self)
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

    /// Keeps the menu-bar app alive when its last window closes.
    ///
    /// WolfWave lives in the status bar (and optionally the Dock) and quits only
    /// via the explicit Quit item, never by closing a window. Returning `false`
    /// matters now that `WolfWaveApp.body` declares a hidden `Window` scene for
    /// `SettingsSceneBridge`: that helper window is ordered out at launch, so
    /// without this the app could see zero windows and auto-terminate right after
    /// launching.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    // MARK: - Track Display Updates

    /// Posts a `nowPlayingChanged` notification for settings view observers.
    func postNowPlayingUpdate(song: String?, artist: String?, album: String?, playlist: String? = nil, isPaused: Bool = false) {
        Task { @MainActor in
            NotificationCenter.default.postNowPlaying(
                track: song,
                artist: artist,
                album: album,
                playlist: playlist,
                isPaused: isPaused
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
    ///
    /// Reflects pause state: a paused track is still "loaded" per the
    /// `AppleMusicSource` playerState rules, so chat sees `⏸️ Paused:` instead
    /// of the silent fallback that confused viewers in earlier builds.
    func getCurrentSongInfo() -> String {
        guard isMusicAppOpen() else { return "🐺 The streamer needs to open Apple Music" }
        guard let song = currentSong, let artist = currentArtist else { return "🐺 Nothing playing right now" }
        let verb = currentIsPaused ? "⏸️ Paused" : "▶️ Playing"
        return appendSongLink(to: "🐺 \(verb): \(song) by \(artist)", track: song, artist: artist)
    }

    /// Returns a formatted string with the previously played track for Twitch bot commands.
    func getLastSongInfo() -> String {
        guard isMusicAppOpen() else { return "🐺 The streamer needs to open Apple Music" }
        guard let song = lastSong, let artist = lastArtist else {
            return "🐺 No previous tracks yet, keep the music flowing!"
        }
        return appendSongLink(to: "🐺 Previous: \(song) by \(artist)", track: song, artist: artist)
    }

    /// Appends a song.link URL to `reply` when the toggle is on and ArtworkService has a cached URL.
    /// Shared by `getCurrentSongInfo` and `getLastSongInfo` to avoid duplicate logic.
    private func appendSongLink(to reply: String, track: String, artist: String) -> String {
        guard FeatureFlags.songCommandSongLinkEnabled,
              let url = ArtworkService.shared.cachedTrackLinks(track: track, artist: artist).songLinkURL
        else { return reply }
        return "\(reply) · \(url)"
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
