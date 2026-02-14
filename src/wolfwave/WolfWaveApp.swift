//
//  WolfWaveApp.swift
//  wolfwave
//
//  Created by MrDemonWolf, Inc. on 1/17/26.
//

/// WolfWave: A macOS menu bar app for sharing currently playing music to Twitch chat.
///
/// This module provides the main application entry point, menu bar integration,
/// music playback monitoring, and Twitch chat bot functionality.
///
/// Architecture:
/// - WolfWaveApp: SwiftUI app entry point
/// - AppDelegate: Lifecycle management, menu bar setup, service orchestration
/// - SettingsView: Configuration UI for all app features
/// - TwitchChatService: Twitch EventSub WebSocket connection and bot commands
/// - MusicPlaybackMonitor: Apple Music tracking via AppleScript
///
/// Key Features:
/// - Menu bar status with current track information
/// - Configurable Twitch chat bot commands (!song, !last, etc.)
/// - Apple Music monitoring with real-time updates
/// - Secure credential storage via Keychain
/// - OAuth Device Code flow for Twitch authentication
/// - Dock and menu bar visibility modes

import AppKit
import SwiftUI
import UserNotifications

// MARK: - App Entry Point

/// Main application entry point for WolfWave.
///
/// The app uses the SwiftUI App protocol and runs in the menu bar.
/// Configuration is handled through a Settings scene that opens separately
/// from any main window.
@main
struct WolfWaveApp: App {
    /// App delegate handling lifecycle, services, and menu bar management.
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    /// Provides access to the macOS Settings window for configuration.
    var body: some Scene {
        Settings {
            SettingsView()
        }
    }
}


// MARK: - App Delegate

/// Manages application lifecycle, menu bar presence, services, and window management.
///
/// The AppDelegate is responsible for:
/// 1. Setting up the menu bar status item on app launch
/// 2. Initializing and coordinating service objects (MusicPlaybackMonitor, TwitchChatService)
/// 3. Managing the Settings window lifecycle
/// 4. Responding to system notifications (window close, tracking changes, etc.)
/// 5. Handling dock visibility mode changes
/// 6. Validating Twitch tokens and prompting for re-authentication if needed
///
/// Key Properties:
/// - statusItem: macOS menu bar item showing current track
/// - musicMonitor: Monitors Apple Music playback
/// - twitchService: Manages Twitch chat connection and bot commands
/// - settingsWindow: Settings UI window (created on demand)
///
/// Thread Safety:
/// - All UI updates happen on the main thread
/// - Background tasks use Task { } for async work
/// - MusicPlaybackMonitor uses dispatch queues internally
class AppDelegate: NSObject, NSApplicationDelegate, NSToolbarDelegate, NSWindowDelegate {
    /// Unique identifier for the settings window toolbar.
    private static let settingsToolbarIdentifier = "com.wolfwave.settings.toolbar"
    
    /// Shared instance of AppDelegate for global access
    static weak var shared: AppDelegate?
    
    // MARK: - Properties
    
    /// Menu bar status item showing the current track.
    ///
    /// Contains a menu with:
    /// - Header showing "♪ Now Playing"
    /// - Current song title
    /// - Artist name
    /// - Album name
    /// - Separator
    /// - Settings action
    /// - About action
    /// - Quit action
    var statusItem: NSStatusItem?
    
    /// Music playback monitor tracking Apple Music.
    ///
    /// Monitors Apple Music via AppleScript and calls the MusicPlaybackMonitorDelegate
    /// whenever the track changes or playback status changes.
    var musicMonitor: MusicPlaybackMonitor?
    
    /// Settings window (created on-demand when user clicks Settings).
    ///
    /// Hosted SwiftUI view with SettingsView as root. Window is created once and
    /// reused for subsequent opens (made key, brought to front).
    var settingsWindow: NSWindow?

    /// Onboarding wizard window (shown on first launch only).
    ///
    /// Created once during first launch. Dismissed and nilled after completion.
    var onboardingWindow: NSWindow?
    
    /// Twitch chat service managing bot commands and channel connection.
    ///
    /// Handles EventSub WebSocket connection to Twitch, chat message routing,
    /// and bot command dispatching.
    var twitchService: TwitchChatService?

    /// Discord Rich Presence service.
    ///
    /// Manages the local IPC socket connection to Discord for showing
    /// "Listening to Apple Music" on the user's Discord profile.
    var discordService: DiscordRPCService?

    /// Update checker service.
    ///
    /// Periodically queries GitHub Releases for newer versions and posts
    /// notifications when an update is available.
    var updateChecker: UpdateCheckerService?

    /// WebSocket server for broadcasting now-playing data to stream overlays.
    ///
    /// Listens on a configurable local port and sends JSON messages to
    /// connected clients (e.g., OBS browser sources).
    var websocketServer: WebSocketServerService?

    /// Current track being played (song title).
    private(set) var currentSong: String?

    /// Current track artist.
    private(set) var currentArtist: String?

    /// Current track album.
    private(set) var currentAlbum: String?

    /// Current track duration in seconds.
    private var currentDuration: TimeInterval = 0

    /// Current track elapsed time in seconds.
    private var currentElapsed: TimeInterval = 0
    
    /// Previously played track title (for !last command).
    private var lastSong: String?
    
    /// Previously played track artist.
    private var lastArtist: String?

    /// Current dock visibility mode from UserDefaults.
    ///
    /// Returns the stored mode or defaults to `AppConstants.DockVisibility.default`.
    private var currentDockVisibilityMode: String {
        UserDefaults.standard.string(forKey: AppConstants.UserDefaults.dockVisibility)
            ?? AppConstants.DockVisibility.default
    }

    /// Application name from bundle metadata or defaults.
    ///
    /// Used in menu items, window titles, and notifications.
    /// Falls back to "WolfWave" if not found in bundle.
    private var appName: String {
        Bundle.main.infoDictionary?["CFBundleDisplayName"] as? String ?? Bundle.main
            .infoDictionary?["CFBundleName"] as? String ?? AppConstants.AppInfo.displayName
    }

    // MARK: - Lifecycle

    /// Called when the application finishes launching.
    ///
    /// Setup Order:
    /// 1. Creates menu bar status item with app icon
    /// 2. Builds initial menu with placeholder song info
    /// 3. Initializes music playback monitor
    /// 4. Creates Twitch chat service
    /// 5. Registers all notification observers
    /// 6. Sets up initial tracking state from UserDefaults
    /// 7. Validates Twitch token on boot (shows re-auth if expired)
    ///
    /// This runs on the main thread and blocks app initialization until complete.
    /// Heavy async work (token validation) runs in background tasks.
    func applicationDidFinishLaunching(_ notification: Notification) {
        AppDelegate.shared = self
        setupStatusItem()
        setupMenu()
        setupMusicMonitor()
        setupTwitchService()
        setupDiscordService()
        setupWebSocketServer()
        setupUpdateChecker()
        setupNotificationObservers()
        initializeTrackingState()

        // Show onboarding on first launch, or validate Twitch token on subsequent launches
        if !OnboardingViewModel.hasCompletedOnboarding {
            showOnboarding()
        } else {
            Task { [weak self] in
                await self?.validateTwitchTokenOnBoot()
            }
        }

        applyInitialDockVisibility()
    }
    
    /// Called when the app is asked to reopen (e.g., user clicks dock icon).
    ///
    /// If dock visibility is set to "menu only", switches app to show in dock.
    /// Opens or brings the Settings window to front.
    ///
    /// - Parameters:
    ///   - sender: The NSApplication instance.
    ///   - flag: True if windows are already visible; false otherwise.
    /// - Returns: True to allow default reopening behavior; false to prevent it.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if currentDockVisibilityMode == AppConstants.DockVisibility.menuOnly {
            NSApp.setActivationPolicy(.regular)
        }

        openSettings()
        return true
    }

    // MARK: - Track Display Updates

    /// Posts a notification with track information for observers (e.g. settings view).
    ///
    /// - Parameters:
    ///   - song: Current track title (nil clears the display).
    ///   - artist: Current track artist.
    ///   - album: Current track album.
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

    // MARK: - Notification Handlers

    /// Responds to changes in the tracking enabled setting.
    ///
    /// Called when user toggles the "Enable Apple Music monitoring" setting.
    /// Starts or stops the music monitor accordingly.
    @objc func trackingSettingChanged(_ notification: Notification) {
        guard let enabled = notification.userInfo?["enabled"] as? Bool else { return }

        enabled ? musicMonitor?.startTracking() : stopTrackingAndUpdate()
    }

    /// Stops music monitoring and updates the menu display.
    ///
    /// Called when tracking is disabled or the music app closes.
    private func stopTrackingAndUpdate() {
        musicMonitor?.stopTracking()
        postNowPlayingUpdate(song: nil, artist: nil, album: nil)
    }

    /// Responds to changes in the Discord Rich Presence enabled setting.
    ///
    /// Called when user toggles the "Enable Discord Rich Presence" setting.
    /// Enables or disables the Discord IPC service accordingly.
    @objc func discordPresenceSettingChanged(_ notification: Notification) {
        guard let enabled = notification.userInfo?["enabled"] as? Bool else { return }
        discordService?.setEnabled(enabled)

        // If enabling and we have current track info, push it immediately
        if enabled, let song = currentSong, let artist = currentArtist {
            discordService?.updatePresence(
                track: song,
                artist: artist,
                album: currentAlbum ?? "",
                duration: currentDuration,
                elapsed: currentElapsed
            )
        }
    }

    /// Responds to changes in the dock visibility mode setting.
    ///
    /// Called when user changes between "menu bar only", "dock only", or "both".
    /// Updates NSApp.activationPolicy and statusItem.isVisible accordingly.
    @objc func dockVisibilityChanged(_ notification: Notification) {
        guard let mode = notification.userInfo?["mode"] as? String else { return }
        applyDockVisibility(mode)
    }

    /// Handles the window close notification to restore menu-only mode if needed.
    ///
    /// If dock visibility is set to "menu only" and there are no other visible windows,
    /// switches the app to accessory activation policy (hidden from dock).
    @objc private func handleWindowClose(_ notification: Notification) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            self?.restoreMenuOnlyIfNeeded()
        }
    }

    // MARK: - Menu Actions

    /// Opens or brings the Settings window to the front.
    ///
    /// Called when user clicks "Settings..." in menu bar menu or presses Cmd+Comma.
    ///
    /// Behavior:
    /// 1. Closes menu tracking (prevents menu from staying open)
    /// 2. If dock visibility is "menu only", switches to regular activation policy
    /// 3. If Settings window exists, unminiaturizes and brings to front
    /// 4. If not, creates new Settings window via NSHostingController
    ///
    /// The Settings window is only created once and reused; it's not deallocated.
    @objc func openSettings() {
        statusItem?.menu?.cancelTracking()
        
        if currentDockVisibilityMode == AppConstants.DockVisibility.menuOnly {
            NSApp.setActivationPolicy(.regular)
        }

        if let window = settingsWindow {
            window.level = .normal
            if window.isMiniaturized { window.deminiaturize(nil) }
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        } else {
            settingsWindow = createSettingsWindow()
            showWindow(settingsWindow)
        }
    }

    /// Shows the standard macOS About panel with credits linking to docs and legal pages.
    ///
    /// Activated by clicking "About [AppName]" in the menu bar menu.
    /// Shows app name, version, copyright, credits with clickable links to
    /// Documentation, Privacy Policy, and Terms of Service.
    @objc func showAbout() {
        statusItem?.menu?.cancelTracking()

        if currentDockVisibilityMode == AppConstants.DockVisibility.menuOnly {
            NSApp.setActivationPolicy(.regular)
        }

        let credits = buildAboutCredits()
        NSApp.orderFrontStandardAboutPanel(options: [
            .applicationName: appName,
            .credits: credits
        ])
        NSApp.activate(ignoringOtherApps: true)
    }

    /// Builds the attributed string for the About panel credits section.
    ///
    /// Contains clickable links to Documentation, Privacy Policy, and Terms of Service.
    ///
    /// - Returns: Configured NSAttributedString with centered, linked text.
    private func buildAboutCredits() -> NSAttributedString {
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = .center
        paragraphStyle.lineSpacing = 4

        let baseAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 11),
            .foregroundColor: NSColor.secondaryLabelColor,
            .paragraphStyle: paragraphStyle,
        ]

        let linkAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 11),
            .paragraphStyle: paragraphStyle,
        ]

        let credits = NSMutableAttributedString()

        // Documentation link
        let docsLink = NSMutableAttributedString(string: "Documentation", attributes: linkAttributes)
        docsLink.addAttribute(.link, value: AppConstants.URLs.docs, range: NSRange(location: 0, length: docsLink.length))
        credits.append(docsLink)

        credits.append(NSAttributedString(string: "  ·  ", attributes: baseAttributes))

        // Privacy Policy link
        let ppLink = NSMutableAttributedString(string: "Privacy Policy", attributes: linkAttributes)
        ppLink.addAttribute(.link, value: AppConstants.URLs.privacyPolicy, range: NSRange(location: 0, length: ppLink.length))
        credits.append(ppLink)

        credits.append(NSAttributedString(string: "  ·  ", attributes: baseAttributes))

        // Terms of Service link
        let tosLink = NSMutableAttributedString(string: "Terms of Service", attributes: linkAttributes)
        tosLink.addAttribute(.link, value: AppConstants.URLs.termsOfService, range: NSRange(location: 0, length: tosLink.length))
        credits.append(tosLink)

        return credits
    }

    // MARK: - Dock Visibility Management

    /// Applies the initial dock visibility mode on app launch.
    ///
    /// Reads the stored visibility mode from UserDefaults and applies it.
    /// Defaults to "both" (show in dock and menu bar) if not set.
    private func applyInitialDockVisibility() {
        applyDockVisibility(currentDockVisibilityMode)
    }

    /// Applies a dock visibility mode: "menuOnly", "dockOnly", or "both".
    ///
    /// "menuOnly":
    /// - Sets NSApp.activationPolicy to .accessory (hidden from dock)
    /// - Shows menu bar status item
    ///
    /// "dockOnly":
    /// - Sets NSApp.activationPolicy to .regular (shown in dock)
    /// - Hides menu bar status item
    ///
    /// "both":
    /// - Sets NSApp.activationPolicy to .regular
    /// - Shows menu bar status item
    ///
    /// - Parameter mode: The visibility mode to apply.
    private func applyDockVisibility(_ mode: String) {
        switch mode {
        case AppConstants.DockVisibility.menuOnly:
            statusItem?.isVisible = true
            let hasVisibleWindows = NSApp.windows.contains { window in
                window.isVisible && window.canBecomeKey && window.level == .normal
            }
            NSApp.setActivationPolicy(hasVisibleWindows ? .regular : .accessory)
        case AppConstants.DockVisibility.dockOnly:
            NSApp.setActivationPolicy(.regular)
            statusItem?.isVisible = false
        case AppConstants.DockVisibility.both:
            NSApp.setActivationPolicy(.regular)
            statusItem?.isVisible = true
        default:
            NSApp.setActivationPolicy(.regular)
            statusItem?.isVisible = true
        }
    }
    
    /// Restores the menu-only dock visibility mode if active and no windows are open.
    ///
    /// Called after a window closes to hide the app from the dock again.
    /// Only hides if:
    /// 1. Dock visibility is set to "menu only"
    /// 2. No other regular-level windows are visible
    private func restoreMenuOnlyIfNeeded() {
        guard currentDockVisibilityMode == AppConstants.DockVisibility.menuOnly else { return }
        
        let hasVisibleWindows = NSApp.windows.contains { window in
            window.isVisible && window.canBecomeKey && window.level == .normal
        }
        
        if !hasVisibleWindows {
            NSApp.setActivationPolicy(.accessory)
        }
    }

    // MARK: - Song Info Provider

    /// Checks if the Apple Music application is currently running.
    ///
    /// Used to detect if Music.app is available before attempting to fetch track info.
    /// If Music.app is not running, we show a "Music app is not running" message instead.
    ///
    /// - Returns: True if Music.app is running, false otherwise.
    private func isMusicAppOpen() -> Bool {
        let workspace = NSWorkspace.shared
        let runningApps = workspace.runningApplications
        return runningApps.contains { app in
            app.bundleIdentifier == AppConstants.Music.bundleIdentifier
        }
    }

    /// Provides the current song information for Twitch bot commands and display.
    ///
    /// Returns a formatted string with:
    /// - "🐺 Music app is not running" - if Music.app is closed
    /// - "🐺 No tracks in the den" - if no track info is available
    /// - "🐺 Now playing: [song] by [artist]" - if track is playing
    ///
    /// Used by:
    /// - TwitchChatService for !song and !currentsong commands
    /// - Displayed in menu bar when track changes
    ///
    /// - Returns: Formatted current song information string.
    func getCurrentSongInfo() -> String {
        guard isMusicAppOpen() else {
            return "🐺 Music app is not running"
        }
        
        guard let song = currentSong, let artist = currentArtist else {
            return "🐺 No tracks in the den"
        }
        return "🐺 Now playing: \(song) by \(artist)"
    }

    /// Provides the last played song information for Twitch bot commands.
    ///
    /// Returns a formatted string with:
    /// - "🐺 Music app is not running" - if Music.app is closed
    /// - "🐺 No previous tracks yet, keep the music flowing!" - if no history
    /// - "🐺 Last howl: [song] by [artist]" - if history exists
    ///
    /// Used by:
    /// - TwitchChatService for !last, !lastsong, !prevsong commands
    ///
    /// - Returns: Formatted last played song information string.
    func getLastSongInfo() -> String {
        guard isMusicAppOpen() else {
            return "🐺 Music app is not running"
        }
        
        guard let song = lastSong, let artist = lastArtist else {
            return "🐺 No previous tracks yet, keep the music flowing!"
        }
        return "🐺 Last howl: \(song) by \(artist)"
    }

    // MARK: - Status Bar Setup

    /// Creates the menu bar status item with a custom or system icon.
    ///
    /// Registers with NSStatusBar.system to get a persistent menu bar slot.
    /// The status item length is variable to accommodate any width needed.
    /// Icon is looked up from the app bundle or falls back to a system music note.
    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        configureStatusItemButton()
    }

    /// Configures the status item's button appearance.
    ///
    /// Attempts to use a custom "TrayIcon" image from assets.
    /// If not found, falls back to system "music.note" symbol.
    /// Sets isTemplate=true for dark mode compatibility.
    private func configureStatusItemButton() {
        guard let button = statusItem?.button else { return }

        if let icon = NSImage(named: "TrayIcon") {
            icon.isTemplate = true
            button.image = icon
        } else {
            button.image = NSImage(
                systemSymbolName: "music.note",
                accessibilityDescription: appName
            )
        }
    }

    // MARK: - Menu Setup

    /// Creates and attaches the main status bar menu.
    ///
    /// Menu contains:
    /// 1. Settings...
    /// 2. About WolfWave
    /// 3. Separator
    /// 4. Quit WolfWave
    private func setupMenu() {
        let menu = createMenu()
        statusItem?.menu = menu
    }

    /// Creates the menu bar menu structure.
    ///
    /// - Returns: Configured NSMenu ready for display.
    private func createMenu() -> NSMenu {
        let menu = NSMenu()

        addSettingsItem(to: menu)
        addAboutItem(to: menu)
        menu.addItem(.separator())
        addQuitItem(to: menu)

        return menu
    }

    /// Adds the "Settings..." menu item with keyboard shortcut.
    ///
    /// - Parameter menu: Menu to add item to.
    private func addSettingsItem(to menu: NSMenu) {
        let settingsItem = NSMenuItem(
            title: AppConstants.MenuLabels.settings,
            action: #selector(openSettings),
            keyEquivalent: ","
        )
        settingsItem.image = NSImage(
            systemSymbolName: "gearshape",
            accessibilityDescription: "Settings"
        )
        menu.addItem(settingsItem)
    }

    /// Adds the "About [AppName]" menu item.
    ///
    /// - Parameter menu: Menu to add item to.
    private func addAboutItem(to menu: NSMenu) {
        let aboutItem = NSMenuItem(
            title: "About \(appName)",
            action: #selector(showAbout),
            keyEquivalent: ""
        )
        aboutItem.image = NSImage(
            systemSymbolName: "info.circle",
            accessibilityDescription: "About"
        )
        menu.addItem(aboutItem)
    }

    /// Adds the "Quit" menu item with keyboard shortcut.
    ///
    /// - Parameter menu: Menu to add item to.
    private func addQuitItem(to menu: NSMenu) {
        menu.addItem(
            NSMenuItem(
                title: AppConstants.MenuLabels.quit,
                action: #selector(NSApplication.terminate(_:)),
                keyEquivalent: "q"
            ))
    }

    // MARK: - Service Initialization

    /// Initializes the music playback monitor.
    ///
    /// Creates a MusicPlaybackMonitor and attaches this AppDelegate as its delegate.
    /// The monitor will call musicPlaybackMonitor(_:didUpdateTrack:artist:album)
    /// whenever the current track changes.
    private func setupMusicMonitor() {
        musicMonitor = MusicPlaybackMonitor()
        musicMonitor?.delegate = self
    }

    /// Initializes the Twitch chat service.
    ///
    /// Creates a TwitchChatService and provides callbacks for:
    /// - getCurrentSongInfo: Called when !song command is issued
    /// - getLastSongInfo: Called when !last command is issued
    ///
    /// These allow the Twitch bot to fetch current track info on-demand.
    private func setupTwitchService() {
        twitchService = TwitchChatService()

        // Resolve Twitch Client ID and log helpful messages
        if TwitchChatService.resolveClientID() == nil {
            Log.error("AppDelegate: No Twitch Client ID found. Copy Config.xcconfig.example to Config.xcconfig and set your Client ID.", category: "Twitch")
        }

        twitchService?.getCurrentSongInfo = { [weak self] in
            self?.getCurrentSongInfo() ?? "No song is currently playing"
        }
        twitchService?.getLastSongInfo = { [weak self] in
            self?.getLastSongInfo() ?? "No song is currently playing"
        }
    }

    // MARK: - Discord Service

    /// Initializes the Discord Rich Presence service.
    ///
    /// Creates a DiscordRPCService and registers a state-change callback that
    /// posts notifications for the settings UI. Enables the service if the user
    /// has previously turned on Discord presence in settings.
    private func setupDiscordService() {
        discordService = DiscordRPCService()

        if DiscordRPCService.resolveClientID() != nil {
            Log.debug("AppDelegate: Resolved Discord Client ID from Info.plist", category: "Discord")
        } else {
            Log.info("AppDelegate: No Discord Client ID found. Set DISCORD_CLIENT_ID in Config.xcconfig to enable Rich Presence.", category: "Discord")
        }

        discordService?.onStateChange = { [weak self] newState in
            let stateString: String
            switch newState {
            case .connected: stateString = "connected"
            case .connecting: stateString = "connecting"
            case .disconnected: stateString = "disconnected"
            }

            NotificationCenter.default.post(
                name: NSNotification.Name(AppConstants.Notifications.discordStateChanged),
                object: self,
                userInfo: ["state": stateString]
            )
        }

        // Forward artwork URLs to the WebSocket server
        discordService?.onArtworkResolved = { [weak self] url, track, artist in
            self?.websocketServer?.updateArtworkURL(url)
        }

        // Enable if user previously turned it on
        let enabled = UserDefaults.standard.bool(forKey: AppConstants.UserDefaults.discordPresenceEnabled)
        if enabled {
            discordService?.setEnabled(true)
        }
    }

    // MARK: - WebSocket Server

    /// Initializes the WebSocket server for streaming now-playing data to overlays.
    ///
    /// Reads the port from UserDefaults (defaulting to 8765), creates the service,
    /// and enables it if the user has previously turned on WebSocket in settings.
    private func setupWebSocketServer() {
        let storedPort = UserDefaults.standard.integer(forKey: AppConstants.UserDefaults.websocketServerPort)
        let port: UInt16 = storedPort > 0 ? UInt16(clamping: storedPort) : AppConstants.WebSocketServer.defaultPort

        websocketServer = WebSocketServerService(port: port)

        // The service already posts websocketServerStateChanged notifications internally,
        // so the onStateChange callback is only used for logging.
        websocketServer?.onStateChange = { newState, clientCount in
            Log.debug("WebSocket: State changed to \(newState.rawValue) (\(clientCount) clients)", category: "WebSocket")
        }

        let enabled = UserDefaults.standard.bool(forKey: AppConstants.UserDefaults.websocketEnabled)
        if enabled {
            websocketServer?.setEnabled(true)
        }
    }

    /// Responds to changes in the WebSocket server settings (enable/disable, port change).
    @objc func websocketServerSettingChanged(_ notification: Notification) {
        let enabled = UserDefaults.standard.bool(forKey: AppConstants.UserDefaults.websocketEnabled)
        websocketServer?.setEnabled(enabled)

        if let port = notification.userInfo?["port"] as? UInt16 {
            websocketServer?.updatePort(port)
        }
    }

    // MARK: - Update Checker

    /// Initializes the update checker service and starts periodic checking.
    ///
    /// Creates an UpdateCheckerService that queries GitHub Releases on a schedule.
    /// The first check is delayed to avoid slowing down launch.
    private func setupUpdateChecker() {
        updateChecker = UpdateCheckerService()
        updateChecker?.startPeriodicChecking()
    }

    // MARK: - Notification Observers

    /// Registers all notification observers for system events.
    ///
    /// Observes:
    /// 1. Tracking setting changes (user toggle in settings)
    /// 2. Dock visibility changes (user selection in settings)
    /// 3. Window close events (to restore menu-only mode if needed)
    private func setupNotificationObservers() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(trackingSettingChanged),
            name: NSNotification.Name(AppConstants.Notifications.trackingSettingChanged),
            object: nil
        )

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(dockVisibilityChanged),
            name: NSNotification.Name(AppConstants.Notifications.dockVisibilityChanged),
            object: nil
        )

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleWindowClose(_:)),
            name: NSWindow.willCloseNotification,
            object: nil
        )

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(discordPresenceSettingChanged),
            name: NSNotification.Name(AppConstants.Notifications.discordPresenceChanged),
            object: nil
        )

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(websocketServerSettingChanged),
            name: NSNotification.Name(AppConstants.Notifications.websocketServerChanged),
            object: nil
        )

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleUpdateStateChanged),
            name: NSNotification.Name(AppConstants.Notifications.updateStateChanged),
            object: nil
        )
    }

    // MARK: - Tracking State

    /// Initializes the tracking state from UserDefaults on app launch.
    ///
    /// If tracking preference doesn't exist, defaults to enabled (true).
    /// If enabled, starts the music monitor; if disabled, shows "Tracking disabled" in menu.
    private func initializeTrackingState() {
        if UserDefaults.standard.object(forKey: AppConstants.UserDefaults.trackingEnabled) == nil {
            UserDefaults.standard.set(true, forKey: AppConstants.UserDefaults.trackingEnabled)
        }

        if isTrackingEnabled() {
            musicMonitor?.startTracking()
        } else {
            postNowPlayingUpdate(song: nil, artist: nil, album: nil)
        }
    }

    /// Checks if music tracking is currently enabled in UserDefaults.
    ///
    /// - Returns: True if tracking enabled, false if disabled.
    private func isTrackingEnabled() -> Bool {
        UserDefaults.standard.bool(forKey: AppConstants.UserDefaults.trackingEnabled)
    }

    // MARK: - Onboarding Window

    /// Shows the first-launch onboarding wizard in a dedicated window.
    ///
    /// Creates a non-resizable, centered window hosting `OnboardingView`.
    /// On completion, the window is closed and normal app flow continues.
    func showOnboarding() {
        // If the onboarding window is already visible, just bring it forward
        if let existing = onboardingWindow, existing.isVisible {
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let onboardingView = OnboardingView(onComplete: { [weak self] in
            self?.dismissOnboarding()
        })

        let hosting = NSHostingController(rootView: onboardingView)
        let frame = CGRect(
            x: 0, y: 0,
            width: AppConstants.OnboardingUI.windowWidth,
            height: AppConstants.OnboardingUI.windowHeight
        )
        let style: NSWindow.StyleMask = [.titled, .closable, .fullSizeContentView]
        let window = NSWindow(
            contentRect: frame,
            styleMask: style,
            backing: .buffered,
            defer: false
        )
        window.contentViewController = hosting
        window.title = "Welcome to WolfWave"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.delegate = self
        window.collectionBehavior = [.moveToActiveSpace]

        // Ensure app is visible during onboarding
        NSApp.setActivationPolicy(.regular)

        onboardingWindow = window
        window.center()
        showWindow(onboardingWindow)
    }

    /// Dismisses the onboarding wizard and transitions to normal app state.
    ///
    /// Called when the user clicks Finish or Skip in the onboarding wizard.
    /// Defers window teardown to the next run loop iteration so the SwiftUI
    /// view's call stack can fully unwind before its hosting window is destroyed
    /// (prevents EXC_BAD_ACCESS).
    private func dismissOnboarding() {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }

            // Detach the reference first so windowWillClose (called
            // synchronously from close()) will skip its cleanup path.
            let window = self.onboardingWindow
            self.onboardingWindow = nil

            // orderOut hides without triggering delegate callbacks,
            // avoiding re-entrant deallocation during the close lifecycle.
            window?.orderOut(nil)

            // Validate Twitch token if one was saved during onboarding
            Task { [weak self] in
                await self?.validateTwitchTokenOnBoot()
            }

            // Restore dock visibility to configured state
            self.applyInitialDockVisibility()

            Log.info("Onboarding dismissed, transitioning to normal app state", category: "Onboarding")
        }
    }

    // MARK: - NSWindowDelegate

    /// Handles the onboarding window being closed via the X button.
    ///
    /// Treats closing the window as completing onboarding so the Reset button
    /// in Advanced settings works correctly and state is properly cleaned up.
    ///
    /// The reference cleanup (`onboardingWindow = nil`) is deferred to the next
    /// run-loop iteration so the window and its hosted SwiftUI views can finish
    /// their close lifecycle before ARC deallocates them.
    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow,
              window === onboardingWindow else { return }

        // Mark onboarding as completed so Reset Onboarding works
        UserDefaults.standard.set(true, forKey: AppConstants.UserDefaults.hasCompletedOnboarding)

        // Defer reference cleanup so the window finishes its close
        // lifecycle before being deallocated (prevents EXC_BAD_ACCESS).
        DispatchQueue.main.async { [weak self] in
            self?.onboardingWindow = nil
            self?.applyInitialDockVisibility()
        }
    }

    // MARK: - Settings Window

    /// Creates the Settings window with SwiftUI content and custom toolbar.
    ///
    /// Creates an NSHostingController wrapping SettingsView and configures:
    /// 1. Window properties (title bar, appearance, size)
    /// 2. Custom toolbar with sidebar toggle button
    /// 3. Window behavior (movable by background, closable, etc.)
    /// 4. Centers on screen and applies collection behavior
    ///
    /// - Returns: Configured NSWindow ready for display.
    private func createSettingsWindow() -> NSWindow {
        let hosting = NSHostingController(rootView: SettingsView())
        let frame = CGRect(x: 0, y: 0, width: AppConstants.UI.settingsWidth, height: AppConstants.UI.settingsHeight)
        let style: NSWindow.StyleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
        let window = NSWindow(contentRect: frame, styleMask: style, backing: .buffered, defer: false)
        window.contentViewController = hosting
        
        // Configure title bar for modern appearance
        window.title = ""
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true

        // Add toolbar with sidebar toggle
        let toolbar = NSToolbar(identifier: NSToolbar.Identifier(Self.settingsToolbarIdentifier))
        toolbar.displayMode = .iconOnly
        toolbar.allowsUserCustomization = false
        toolbar.delegate = self
        if #available(macOS 11.0, *) {
            toolbar.centeredItemIdentifier = nil
        }
        window.toolbar = toolbar
        if #available(macOS 13.0, *) {
            window.toolbarStyle = .unified
        }

        // Behavior settings
        window.collectionBehavior = [.moveToActiveSpace]
        window.canHide = true

        window.center()
        return window
    }

    /// Shows a window by making it key and ordering it to front.
    ///
    /// - Parameter window: Window to show.
    private func showWindow(_ window: NSWindow?) {
        window?.level = .normal
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

// MARK: - Toolbar Delegate

/// Toolbar customization for the Settings window.
extension AppDelegate {
    /// Returns the toolbar items that are allowed in this toolbar.
    ///
    /// - Returns: Array of allowed toolbar item identifiers.
    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        return [.toggleSidebar, .flexibleSpace]
    }

    /// Returns the default toolbar items to display.
    ///
    /// Configuration:
    /// - Flexible space left
    /// - Sidebar toggle button center
    /// - Flexible space right
    ///
    /// - Returns: Array of default toolbar item identifiers.
    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        return [.flexibleSpace, .toggleSidebar, .flexibleSpace]
    }

    /// Creates a toolbar item for the given identifier.
    ///
    /// Returns nil to use system default toolbar items (e.g., toggleSidebar).
    ///
    /// - Parameters:
    ///   - toolbar: The toolbar requesting the item.
    ///   - itemIdentifier: The identifier for the requested item.
    ///   - flag: True if item will be inserted; false if querying for possible items.
    /// - Returns: Configured NSToolbarItem or nil to use default.
    func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier, willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        return nil
    }
}

// MARK: - Twitch Token Validation

/// Handles Twitch token validation on boot.
extension AppDelegate {
    /// Sets the reauth-needed flag in UserDefaults.
    ///
    /// - Parameter needed: True if user must re-authenticate, false otherwise.
    @MainActor
    private func setReauthNeeded(_ needed: Bool) {
        UserDefaults.standard.set(needed, forKey: AppConstants.UserDefaults.twitchReauthNeeded)
    }

    /// Shows a local notification with Twitch authentication status.
    ///
    /// Requests user permission for notifications and displays the alert.
    /// Used to notify user of token expiration or connection errors.
    ///
    /// - Parameters:
    ///   - title: Notification title.
    ///   - message: Notification body text.
    private func showTwitchAuthNotification(title: String, message: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = message
        content.sound = .default
        
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, _ in
            if granted {
                DispatchQueue.main.async {
                    UNUserNotificationCenter.current().add(request) { error in
                        if let error = error {
                            Log.error(
                                "Failed to send notification: \(error.localizedDescription)",
                                category: "Notifications"
                            )
                        }
                    }
                }
            }
        }
    }

    /// Opens Settings window and navigates to Twitch Integration section.
    ///
    /// Called when token validation fails or connection errors occur.
    /// Sets the selectedSettingsSection UserDefaults key so SettingsView opens to Twitch tab.
    private func openSettingsToTwitch() {
        UserDefaults.standard.set(AppConstants.Twitch.settingsSection, forKey: AppConstants.UserDefaults.selectedSettingsSection)
        openSettings()
    }

    /// Validates the stored Twitch OAuth token on app launch.
    ///
    /// Process:
    /// 1. Checks if token exists in Keychain
    /// 2. Calls TwitchChatService.validateToken() to check with Twitch API
    /// 3. If invalid, sets reauth-needed flag and shows notification
    /// 4. Opens Settings automatically after delay
    ///
    /// If no token exists, silently returns (user hasn't authenticated yet).
    ///
    /// Called from applicationDidFinishLaunching() in a background task.
    fileprivate func validateTwitchTokenOnBoot() async {
        guard let token = KeychainService.loadTwitchToken(), !token.isEmpty else {
            await setReauthNeeded(false)
            return
        }

        let isValid = await twitchService?.validateToken(token) ?? false
        await MainActor.run {
            setReauthNeeded(!isValid)
            
            if !isValid {
                showTwitchAuthNotification(
                    title: "Twitch Authentication Expired",
                    message: "Your Twitch session has expired. Opening Settings..."
                )
                DispatchQueue.main.asyncAfter(deadline: .now() + AppConstants.Timing.notificationDelay) { [weak self] in
                    self?.openSettingsToTwitch()
                }
            }
        }
    }
}

// MARK: - Update Notifications

/// Handles update-available notifications from UpdateCheckerService.
extension AppDelegate {
    /// Called when the update checker finishes a check.
    ///
    /// If an update is available and the user hasn't skipped that version,
    /// shows a macOS notification with install instructions.
    @objc func handleUpdateStateChanged(_ notification: Notification) {
        guard let isAvailable = notification.userInfo?["isUpdateAvailable"] as? Bool,
              let version = notification.userInfo?["latestVersion"] as? String,
              isAvailable else { return }

        showUpdateNotification(version: version, installMethod: updateChecker?.detectInstallMethod() ?? .dmg)
    }

    /// Shows a macOS notification for an available update.
    ///
    /// Checks the skipped version preference before showing. Uses a version-specific
    /// notification identifier to avoid duplicates.
    ///
    /// - Parameters:
    ///   - version: The new version string (e.g. "1.1.0").
    ///   - installMethod: How the app was installed (affects the message text).
    private func showUpdateNotification(version: String, installMethod: InstallMethod) {
        let skippedVersion = UserDefaults.standard.string(forKey: AppConstants.UserDefaults.updateSkippedVersion)
        guard skippedVersion != version else {
            Log.debug("UpdateChecker: Skipping notification for v\(version) (user skipped)", category: "Update")
            return
        }

        let content = UNMutableNotificationContent()
        content.title = "WolfWave Update Available"
        content.sound = .default

        switch installMethod {
        case .homebrew:
            content.body = "Version \(version) is available. Run: brew upgrade wolfwave"
        case .dmg:
            content.body = "Version \(version) is available. Open Settings to download."
        }

        let request = UNNotificationRequest(
            identifier: "update-\(version)",
            content: content,
            trigger: nil
        )

        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, _ in
            if granted {
                DispatchQueue.main.async {
                    UNUserNotificationCenter.current().add(request) { error in
                        if let error {
                            Log.error("Failed to send update notification: \(error.localizedDescription)", category: "Update")
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Music Playback Monitor Delegate

/// Handles music playback updates from the MusicPlaybackMonitor.
///
/// Called whenever the current track changes or playback status changes.
/// Updates the menu bar display and Twitch bot command responses.
extension AppDelegate: MusicPlaybackMonitorDelegate {
    /// Called when the current track information changes.
    ///
    /// Updates both the track history (for !last command) and menu display.
    /// Called on a background queue by MusicPlaybackMonitor; updates dispatch to main thread.
    ///
    /// - Parameters:
    ///   - monitor: The MusicPlaybackMonitor instance.
    ///   - track: New track title.
    ///   - artist: New track artist.
    ///   - album: New track album.
    func musicPlaybackMonitor(
        _ monitor: MusicPlaybackMonitor, didUpdateTrack track: String, artist: String, album: String, duration: TimeInterval, elapsed: TimeInterval
    ) {
        if currentSong != track {
            lastSong = currentSong
            lastArtist = currentArtist
        }

        currentSong = track
        currentArtist = artist
        currentAlbum = album
        currentDuration = duration
        currentElapsed = elapsed

        postNowPlayingUpdate(song: track, artist: artist, album: album)

        // Update WebSocket server with the new track
        websocketServer?.updateNowPlaying(
            track: track,
            artist: artist,
            album: album,
            duration: duration,
            elapsed: elapsed
        )

        // Update Discord Rich Presence with the new track
        discordService?.updatePresence(
            track: track,
            artist: artist,
            album: album,
            duration: duration,
            elapsed: elapsed
        )
    }

    /// Called when the playback status changes (e.g., playing, paused, stopped).
    ///
    /// Updates the menu display with the status message.
    /// If status is "No track playing", clears the track history.
    ///
    /// - Parameters:
    ///   - monitor: The MusicPlaybackMonitor instance.
    ///   - status: Status message (e.g., "Music app is not running").
    func musicPlaybackMonitor(_ monitor: MusicPlaybackMonitor, didUpdateStatus status: String) {
        if status == "No track playing" {
            currentSong = nil
            currentArtist = nil
            currentAlbum = nil
        }

        postNowPlayingUpdate(song: nil, artist: nil, album: nil)

        // Clear Discord Rich Presence and WebSocket when not playing
        if currentSong == nil {
            discordService?.clearPresence()
            websocketServer?.clearNowPlaying()
        }
    }
}


