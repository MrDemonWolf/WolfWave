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

/// SwiftUI entry point. Runs as a menu bar app with a dedicated Settings `Window` scene.
@main
struct WolfWaveApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    /// Identifier for the Settings `Window` scene. Shared with
    /// `SettingsSceneBridge`, which opens it via `@Environment(\.openWindow)`.
    static let settingsWindowID = "wolfwave-settings"

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
        // the Settings `Window` scene. Scene order is load-bearing: a helper
        // window placed after the Settings scene leaves the bridge's
        // `openWindow(id:)` action a silent no-op. It gives the AppKit entry
        // points (tray menu, Dock menu, Dock reopen, Twitch re-auth) a live
        // SwiftUI scene tree to drive, so they open Settings via the public
        // `openWindow(id:)` environment action rather than the private
        // `showSettingsWindow:` selector. `BridgeWindowNeutralizer` keeps this
        // window offscreen and invisible, so it never appears and never trips
        // `applyDockVisibility`'s probe. The app stays alive when this window
        // orders out via `applicationShouldTerminateAfterLastWindowClosed`
        // returning `false`.
        Window("WolfWave Settings Bridge", id: SettingsSceneBridge.windowID) {
            SettingsSceneBridge()
        }
        .windowResizability(.contentSize)
        .defaultSize(width: 1, height: 1)
        .commandsRemoved()
        // Hidden 1×1 host: never persist/restore its frame (avoids the
        // "window frame from string '… 0 1 …' failed" restore log).
        .restorationBehavior(.disabled)

        // Settings lives in a dedicated SwiftUI `Window` scene (NOT a `Settings`
        // scene). A real window scene is the only host where SwiftUI fully owns
        // the window chrome the way the Landmarks sample does: the
        // `NavigationSplitView` renders a true full-height sidebar, the toggle
        // tucks beside the traffic lights, the sidebar tracking separator and
        // toggle animate as one unit, and there is no reserved dead title-bar
        // band. The old `Settings`-scene host (like an `NSHostingController`)
        // only half-owns the toolbar, which produced the dead band, the off
        // toggle placement, and the `>>` overflow flash during sidebar
        // animation. `Window(_:id:)` is single-instance by construction, so
        // reopening just fronts the existing window. `.restorationBehavior(.disabled)`
        // keeps a menu-bar app from auto-restoring Settings at launch.
        //
        // AppDelegate still drives *when* the window opens (dock-visibility
        // activation policy, tray/reopen entry points) by posting
        // `.openSettingsRequested` to `SettingsSceneBridge`, which now runs the
        // public `openWindow(id:)` action.
        Window("WolfWave Settings", id: WolfWaveApp.settingsWindowID) {
            SettingsView()
        }
        .windowResizability(.contentSize)
        .windowToolbarStyle(.unified)
        .restorationBehavior(.disabled)
        // Suppress the scene's default macOS commands — a `Window(_:id:)` scene
        // otherwise injects a "WolfWave Settings" entry into the Window menu that
        // duplicates Cmd+, and reads oddly for a menu-bar app. `openWindow(id:)`
        // (used by `SettingsSceneBridge`) is an environment action, not a menu
        // command, so it keeps working. Our explicit `.commands` below are added
        // on top and are unaffected.
        .commandsRemoved()
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
            // Cmd+, routes through `appDelegate.openSettings()`, the same path
            // the tray/Dock/Twitch-reauth entry points use, so there is exactly
            // one way the Settings window opens (post `.openSettingsRequested` →
            // `SettingsSceneBridge` runs `openWindow(id:)`). `SettingsLink` is not
            // usable here because it only opens a `Settings` scene, which this app
            // no longer declares.
            //
            // No dock-visibility handling is lost: the App menu (and its Cmd+,)
            // is only reachable when the app is already `.regular`. An
            // `.accessory` menu-only app shows no main menu, so openSettings()'s
            // `.regular` switch would be a no-op on this path anyway.
            CommandGroup(replacing: .appSettings) {
                Button("Settings\u{2026}") {
                    appDelegate.openSettings()
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
    // Settings is a dedicated SwiftUI `Window` scene (see WolfWaveApp.body);
    // SwiftUI owns that window, so AppDelegate no longer holds an `NSWindow` for it.
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
    /// bitmap hasn't been decoded yet. Backed by `NSCache` so it has a hard
    /// upper bound and evicts under memory pressure, instead of growing without
    /// limit for the lifetime of the process.
    let albumArtCache: NSCache<NSString, NSImage> = {
        let cache = NSCache<NSString, NSImage>()
        cache.countLimit = 64
        return cache
    }()

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

    /// Installs the crash safety net before any UI or service starts, so even an
    /// early-launch crash leaves a breadcrumb. Skipped under XCTest so the test
    /// host keeps its own crash reporting (and never gets process-wide signal
    /// handlers). Runs before `applicationDidFinishLaunching`.
    func applicationWillFinishLaunching(_ notification: Notification) {
        guard !WolfWaveApp.isRunningTests else { return }
        CrashReporter.install()

        // If the user runs menu-only, claim `.accessory` here — before AppKit's
        // first Dock paint in `applicationDidFinishLaunching`. The Info.plist keeps
        // the app a regular (Dock-visible) process by default, so a menu-only user
        // would otherwise see the Dock icon flash on every launch until
        // `applyInitialDockVisibility()` later flips it to `.accessory`. Setting it
        // this early suppresses that flash without blanket `LSUIElement = YES`,
        // which would break Dock-Only / Dock-and-Menu-Bar users.
        if currentDockVisibilityMode == AppConstants.DockVisibility.menuOnly {
            NSApp.setActivationPolicy(.accessory)
        }
    }

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

        // Each setup is wrapped so a synchronous failure in one service logs and
        // degrades instead of aborting the rest of launch. Order is preserved.
        guardedStart("StatusItem") { self.setupStatusItem() }
        guardedStart("Menu") { self.setupMenu() }
        guardedStart("MusicMonitor") { self.setupMusicMonitor() }
        guardedStart("Twitch") { self.setupTwitchService() }
        guardedStart("Discord") { self.setupDiscordService() }
        guardedStart("WebSocket") { self.setupWebSocketServer() }
        guardedStart("PowerState") { self.setupPowerStateMonitor() }
        guardedStart("Sparkle") { self.setupSparkleUpdater() }
        guardedStart("SongRequest") { self.setupSongRequestService() }
        guardedStart("History") { self.setupHistoryService() }
        guardedStart("Diagnostics") { self.setupDiagnostics() }

        // Record whether the previous run left a crash breadcrumb, mirror it to a
        // UserDefaults flag the Advanced pane reads, then clear the marker so the
        // callout shows exactly once (next clean launch is silent).
        let crashedLastLaunch = CrashReporter.didCrashLastLaunch()
        Foundation.UserDefaults.standard.set(crashedLastLaunch, forKey: AppConstants.UserDefaults.lastLaunchCrashed)
        if crashedLastLaunch {
            Log.warn("AppDelegate: previous launch ended in a crash (breadcrumb found)", category: "App")
        }
        CrashReporter.clearMarker()

        guardedStart("Observers") { self.setupNotificationObservers() }
        guardedStart("TrackingState") { self.initializeTrackingState() }
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
            NSApp.activate()
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
    ///
    /// When the link can't be found, chat gets a plain "No link found" instead of
    /// a silently dropped link, so viewers know nothing's coming rather than
    /// wondering. While a lookup is still pending the link is omitted (and a
    /// fetch kicked off) so a quick re-run of the command picks up the real URL.
    private func appendSongLink(to reply: String, track: String, artist: String) -> String {
        guard FeatureFlags.songCommandSongLinkEnabled else { return reply }
        if let url = ArtworkService.shared.cachedTrackLinks(track: track, artist: artist).songLinkURL {
            return "\(reply) · \(url)"
        }
        if ArtworkService.shared.hasAttemptedTrackLinks(track: track, artist: artist) {
            return "\(reply) · No link found"
        }
        ArtworkService.shared.fetchTrackLinks(track: track, artist: artist) { _ in }
        return reply
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
