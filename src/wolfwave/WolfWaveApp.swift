//
//  WolfWaveApp.swift
//  wolfwave
//
//  Created by MrDemonWolf, Inc. on 1/13/26.
//

import AppKit
import SwiftUI
import UserNotifications

// MARK: - Main App

/// The main application entry point for WolfWave.
///
/// WolfWave is a macOS menu bar application that monitors Apple Music playback
/// and integrates with Twitch chat to display currently playing tracks.
@main
struct WolfWaveApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings {
            SettingsView()
        }
    }
}

// MARK: - App Delegate

/// Application delegate managing the menu bar item, music monitoring, and Twitch integration.
///
/// This delegate handles:
/// - Status bar menu item creation and updates
/// - Apple Music playback monitoring via `MusicPlaybackMonitor`
/// - Twitch chat service integration
/// - Settings window management
/// - Dock visibility modes (menu-only, dock-only, both)
/// - Token validation and auto-reconnection on app launch
class AppDelegate: NSObject, NSApplicationDelegate {
    
    // MARK: - Constants
    
    fileprivate enum Constants {
        static let defaultAppName = "WolfWave"
        static let displayName = "WolfWave"
        static let settingsWidth: CGFloat = 520
        static let settingsHeight: CGFloat = 560

        enum MenuItemIndex {
            static let header = 0
            static let song = 1
            static let artist = 2
            static let album = 3
        }

        enum Notification {
            static let trackingSettingChanged = "TrackingSettingChanged"
        }

        enum UserDefaults {
            static let trackingEnabled = "trackingEnabled"
            static let dockVisibility = "dockVisibility"
        }
    }

    // MARK: - Properties
    
    /// The status bar item displaying the menu bar icon
    var statusItem: NSStatusItem?
    
    /// Monitors Apple Music for track changes
    var musicMonitor: MusicPlaybackMonitor?
    
    /// Window hosting the settings SwiftUI view
    var settingsWindow: NSWindow?
    
    /// Service managing Twitch chat WebSocket connection
    var twitchService: TwitchChatService?

    /// Currently playing song title
    private var currentSong: String?
    
    /// Currently playing artist name
    private var currentArtist: String?
    
    /// Currently playing album title
    private var currentAlbum: String?
    
    /// Last playing song title
    private var lastSong: String?
    
    /// Last playing artist name
    private var lastArtist: String?

    /// The application display name from Info.plist
    private var appName: String {
        Bundle.main.infoDictionary?["CFBundleDisplayName"] as? String ?? Bundle.main
            .infoDictionary?["CFBundleName"] as? String ?? Constants.displayName
    }

    // MARK: - Lifecycle

    /// Called when the application has finished launching.
    ///
    /// Initializes all components:
    /// - Status bar menu item
    /// - Music playback monitor
    /// - Twitch chat service
    /// - Notification observers
    /// - Token validation and auto-reconnection
    func applicationDidFinishLaunching(_ notification: Notification) {
        setupStatusItem()
        setupMenu()
        setupMusicMonitor()
        setupTwitchService()
        setupNotificationObservers()
        initializeTrackingState()

        Task { [weak self] in
            await self?.validateTwitchTokenOnBoot()
            await self?.autoJoinTwitchChannel()
        }

        applyInitialDockVisibility()
    }
    
    /// Handles user clicking the Dock icon when the app is already running.
    ///
    /// Opens the settings window and ensures the app is visible in the Dock if needed.
    ///
    /// - Parameters:
    ///   - sender: The application
    ///   - flag: Whether any windows are currently visible
    /// - Returns: Always returns `true`
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        let currentMode = UserDefaults.standard.string(forKey: "dockVisibility") ?? "both"
        if currentMode == "menuOnly" {
            NSApp.setActivationPolicy(.regular)
        }

        openSettings()
        return true
    }

    // MARK: - Track Display Updates

    /// Resets the now playing menu to show a single status message.
    ///
    /// - Parameter message: The status message to display (e.g., "No track playing")
    private func resetNowPlayingMenu(message: String) {
        guard let menu = statusItem?.menu,
            menu.items.count > Constants.MenuItemIndex.album
        else {
            return
        }

        let statusText = createStatusAttributedString(message)
        updateMenuItem(at: Constants.MenuItemIndex.song, with: statusText, hidden: false)
        hideMenuItem(at: Constants.MenuItemIndex.artist)
        hideMenuItem(at: Constants.MenuItemIndex.album)
    }

    /// Updates the now playing display with a status message.
    ///
    /// Called from `MusicPlaybackMonitor` delegate when playback stops or tracking is disabled.
    ///
    /// - Parameter text: The status message to display
    func updateNowPlaying(_ text: String) {
        DispatchQueue.main.async { [weak self] in
            self?.resetNowPlayingMenu(message: text)
        }
    }

    /// Updates the track display with song, artist, and album information.
    ///
    /// Called from `MusicPlaybackMonitor` delegate when a new track starts playing.
    ///
    /// - Parameters:
    ///   - song: The track title, or nil if no track is playing
    ///   - artist: The artist name, or nil if no track is playing
    ///   - album: The album title, or nil if no track is playing
    func updateTrackDisplay(song: String?, artist: String?, album: String?) {
        DispatchQueue.main.async { [weak self] in
            guard let self, let menu = self.statusItem?.menu else { return }

            if let song, let artist, let album {
                self.displayTrackInfo(song: song, artist: artist, album: album, in: menu)
            } else {
                self.resetNowPlayingMenu(message: "No track playing")
            }
        }
    }

    // MARK: - Notification Handlers

    /// Handles tracking setting changes from the settings view.
    ///
    /// - Parameter notification: Notification containing the new enabled state
    @objc func trackingSettingChanged(_ notification: Notification) {
        guard let enabled = notification.userInfo?["enabled"] as? Bool else { return }

        enabled ? musicMonitor?.startTracking() : stopTrackingAndUpdate()
    }

    private func stopTrackingAndUpdate() {
        musicMonitor?.stopTracking()
        updateNowPlaying("Tracking disabled")
    }

    /// Handles dock visibility mode changes from settings.
    ///
    /// - Parameter notification: Notification containing the new visibility mode
    @objc func dockVisibilityChanged(_ notification: Notification) {
        guard let mode = notification.userInfo?["mode"] as? String else { return }
        applyDockVisibility(mode)
    }

    /// Handles window close events to restore menu-only mode if appropriate.
    ///
    /// Defers mode restoration by 100ms to allow window state to fully update.
    ///
    /// - Parameter notification: The window close notification
    @objc private func handleWindowClose(_ notification: Notification) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            self?.restoreMenuOnlyIfNeeded()
        }
    }

    // MARK: - Menu Actions

    /// Opens the settings window.
    ///
    /// If the window exists, brings it to the front. Otherwise creates a new instance.
    /// Temporarily enables Dock visibility when in menu-only mode to ensure proper window focus.
    @objc func openSettings() {
        statusItem?.menu?.cancelTracking()
        
        let currentMode = UserDefaults.standard.string(forKey: "dockVisibility") ?? "both"
        if currentMode == "menuOnly" {
            NSApp.setActivationPolicy(.regular)
        }

        if let window = settingsWindow {
            // Bring existing window to front and focus it
            window.level = .normal
            if window.isMiniaturized { window.deminiaturize(nil) }
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        } else {
            settingsWindow = createSettingsWindow()
            showWindow(settingsWindow)
        }
    }

    /// Shows the standard macOS About panel.
    ///
    /// Temporarily enables Dock visibility when in menu-only mode to ensure proper panel display.
    @objc func showAbout() {
        statusItem?.menu?.cancelTracking()
        
        let currentMode = UserDefaults.standard.string(forKey: "dockVisibility") ?? "both"
        if currentMode == "menuOnly" {
            NSApp.setActivationPolicy(.regular)
        }
        
        NSApp.orderFrontStandardAboutPanel(options: [.applicationName: appName])
        NSApp.activate(ignoringOtherApps: true)
    }

    // MARK: - Dock Visibility Management

    /// Applies the initial dock visibility mode on app launch.
    private func applyInitialDockVisibility() {
        let mode = UserDefaults.standard.string(forKey: "dockVisibility") ?? "both"
        applyDockVisibility(mode)
    }

    /// Applies a dock visibility mode.
    ///
    /// Configures menu bar and Dock visibility based on the specified mode.
    /// In menu-only mode, Dock appears only when application windows are visible.
    ///
    /// - Parameter mode: The visibility mode ("menuOnly", "dockOnly", or "both")
    private func applyDockVisibility(_ mode: String) {
        switch mode {
        case "menuOnly":
            statusItem?.isVisible = true
            let hasVisibleWindows = NSApp.windows.contains { window in
                window.isVisible && window.canBecomeKey && window.level == .normal
            }
            NSApp.setActivationPolicy(hasVisibleWindows ? .regular : .accessory)
        case "dockOnly":
            NSApp.setActivationPolicy(.regular)
            statusItem?.isVisible = false
        case "both":
            NSApp.setActivationPolicy(.regular)
            statusItem?.isVisible = true
        default:
            NSApp.setActivationPolicy(.regular)
            statusItem?.isVisible = true
        }
    }
    
    /// Restores menu-only mode after windows close, if configured.
    ///
    /// Only applies when visibility mode is "menuOnly" and no application windows remain visible.
    private func restoreMenuOnlyIfNeeded() {
        let currentMode = UserDefaults.standard.string(forKey: "dockVisibility") ?? "both"
        
        guard currentMode == "menuOnly" else { return }
        
        let hasVisibleWindows = NSApp.windows.contains { window in
            window.isVisible && window.canBecomeKey && window.level == .normal
        }
        
        if !hasVisibleWindows {
            NSApp.setActivationPolicy(.accessory)
        }
    }

    // MARK: - Song Info Provider

    /// Checks if the Music app is currently running.
    ///
    /// - Returns: True if Music app is open, false otherwise
    private func isMusicAppOpen() -> Bool {
        let workspace = NSWorkspace.shared
        let runningApps = workspace.runningApplications
        return runningApps.contains { app in
            app.bundleIdentifier == "com.apple.Music"
        }
    }

    /// Returns the current song information for Twitch bot commands.
    ///
    /// Returns wolf-themed messages based on state:
    /// - "🐺 Music app is not running" if Music app is closed
    /// - "🐺 No tracks in the den" if no track has played yet
    /// - Wolf-themed song info if a track is playing
    ///
    /// - Returns: A formatted string with song and artist, or a status message
    func getCurrentSongInfo() -> String {
        guard isMusicAppOpen() else {
            return "🐺 Music app is not running"
        }
        
        guard let song = currentSong, let artist = currentArtist else {
            return "🐺 No tracks in the den"
        }
        return "🐺 Now playing: \(song) by \(artist)"
    }

    /// Returns the last played song information for Twitch bot commands.
    ///
    /// Returns wolf-themed messages based on state:
    /// - "🐺 Music app is not running" if Music app is closed
    /// - "🐺 No previous tracks yet, keep the music flowing!" if no last song exists
    /// - Wolf-themed song info if a previous track exists
    ///
    /// - Returns: A formatted string with song and artist, or a status message
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

    /// Creates and configures the status bar menu item.
    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        configureStatusItemButton()
    }

    /// Configures the status bar button with the app icon.
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

    /// Creates and configures the status bar menu.
    private func setupMenu() {
        let menu = createMenu()
        statusItem?.menu = menu
        resetNowPlayingMenu(message: "No track playing")
    }

    /// Creates the complete status bar menu with all items.
    ///
    /// - Returns: A configured NSMenu
    private func createMenu() -> NSMenu {
        let menu = NSMenu()

        addNowPlayingItems(to: menu)
        menu.addItem(.separator())
        addSettingsItem(to: menu)
        addAboutItem(to: menu)
        menu.addItem(.separator())
        addQuitItem(to: menu)

        return menu
    }

    /// Adds the "Now Playing" header and placeholder items to the menu.
    ///
    /// - Parameter menu: The menu to add items to
    private func addNowPlayingItems(to menu: NSMenu) {
        let headerItem = NSMenuItem(title: "♪ Now Playing", action: nil, keyEquivalent: "")
        headerItem.isEnabled = false
        menu.addItem(headerItem)

        for _ in 0..<3 {
            let item = NSMenuItem(title: "", action: nil, keyEquivalent: "")
            item.isEnabled = false
            menu.addItem(item)
        }
    }

    /// Adds the Settings menu item.
    ///
    /// - Parameter menu: The menu to add the item to
    private func addSettingsItem(to menu: NSMenu) {
        let settingsItem = NSMenuItem(
            title: "Settings...",
            action: #selector(openSettings),
            keyEquivalent: ","
        )
        settingsItem.image = NSImage(
            systemSymbolName: "gearshape",
            accessibilityDescription: "Settings"
        )
        menu.addItem(settingsItem)
    }

    /// Adds the About menu item.
    ///
    /// - Parameter menu: The menu to add the item to
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

    /// Adds the Quit menu item.
    ///
    /// - Parameter menu: The menu to add the item to
    private func addQuitItem(to menu: NSMenu) {
        menu.addItem(
            NSMenuItem(
                title: "Quit",
                action: #selector(NSApplication.terminate(_:)),
                keyEquivalent: "q"
            ))
    }

    // MARK: - Music Monitor Setup

    /// Creates and configures the music playback monitor.
    private func setupMusicMonitor() {
        musicMonitor = MusicPlaybackMonitor()
        musicMonitor?.delegate = self
    }

    // MARK: - Twitch Service Setup

    /// Creates and configures the Twitch chat service.
    ///
    /// Sets up the song info callbacks so the Twitch bot can respond to !song and !last commands.
    /// Callbacks check if Music app is open and return appropriate status messages.
    /// Also loads saved Twitch credentials from Keychain.
    private func setupTwitchService() {
        twitchService = TwitchChatService()
        twitchService?.getCurrentSongInfo = { [weak self] in
            self?.getCurrentSongInfo() ?? "No song is currently playing"
        }
        twitchService?.getLastSongInfo = { [weak self] in
            self?.getLastSongInfo() ?? "No song is currently playing"
        }
        
        // Credentials are loaded from Keychain during connectToChannel()
    }

    // MARK: - Notification Observers

    /// Registers observers for application-level notifications.
    private func setupNotificationObservers() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(trackingSettingChanged),
            name: NSNotification.Name(Constants.Notification.trackingSettingChanged),
            object: nil
        )

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(dockVisibilityChanged),
            name: NSNotification.Name("DockVisibilityChanged"),
            object: nil
        )

        // Observe any window closing (e.g., About panel) to restore menu-only dock behavior
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleWindowClose(_:)),
            name: NSWindow.willCloseNotification,
            object: nil
        )
    }

    // MARK: - Tracking State

    /// Initializes the tracking enabled state and starts monitoring if enabled.
    private func initializeTrackingState() {
        if UserDefaults.standard.object(forKey: Constants.UserDefaults.trackingEnabled) == nil {
            UserDefaults.standard.set(true, forKey: Constants.UserDefaults.trackingEnabled)
        }

        if isTrackingEnabled() {
            musicMonitor?.startTracking()
        } else {
            resetNowPlayingMenu(message: "Tracking disabled")
        }
    }

    /// Returns whether music tracking is currently enabled in user defaults.
    ///
    /// - Returns: True if tracking is enabled
    private func isTrackingEnabled() -> Bool {
        UserDefaults.standard.bool(forKey: Constants.UserDefaults.trackingEnabled)
    }

    // MARK: - Menu Item Helpers

    /// Creates an attributed string for status messages with secondary label color.
    ///
    /// - Parameter message: The status message
    /// - Returns: An attributed string with formatting
    private func createStatusAttributedString(_ message: String) -> NSAttributedString {
        NSAttributedString(
            string: "  \(message)",
            attributes: [
                .foregroundColor: NSColor.secondaryLabelColor,
                .font: NSFont.systemFont(ofSize: NSFont.systemFontSize - 1),
            ]
        )
    }

    /// Updates a menu item with new attributed text and visibility.
    ///
    /// - Parameters:
    ///   - index: The menu item index
    ///   - title: The new attributed title
    ///   - hidden: Whether the item is hidden
    private func updateMenuItem(at index: Int, with title: NSAttributedString, hidden: Bool) {
        guard let menu = statusItem?.menu, index < menu.items.count else { return }
        menu.items[index].attributedTitle = title
        menu.items[index].isHidden = hidden
    }

    /// Hides a menu item at the specified index.
    ///
    /// - Parameter index: The menu item index
    private func hideMenuItem(at index: Int) {
        guard let menu = statusItem?.menu, index < menu.items.count else { return }
        menu.items[index].isHidden = true
    }

    /// Displays track information in the menu with formatted text.
    ///
    /// - Parameters:
    ///   - song: The track title
    ///   - artist: The artist name
    ///   - album: The album title
    ///   - menu: The menu to update
    private func displayTrackInfo(song: String, artist: String, album: String, in menu: NSMenu) {
        let songAttr = createLabeledText(label: "Song:", value: song)
        let artistAttr = createLabeledText(label: "Artist:", value: artist)
        let albumAttr = createLabeledText(label: "Album:", value: album)

        menu.items[Constants.MenuItemIndex.song].attributedTitle = songAttr
        menu.items[Constants.MenuItemIndex.artist].attributedTitle = artistAttr
        menu.items[Constants.MenuItemIndex.album].attributedTitle = albumAttr

        [
            Constants.MenuItemIndex.song, Constants.MenuItemIndex.artist,
            Constants.MenuItemIndex.album,
        ].forEach {
            menu.items[$0].isHidden = false
        }
    }

    /// Creates an attributed string with a bold label and regular value.
    ///
    /// - Parameters:
    ///   - label: The bold label text (e.g., "Song:")
    ///   - value: The value text
    /// - Returns: An attributed string combining label and value
    private func createLabeledText(label: String, value: String) -> NSAttributedString {
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineBreakMode = .byWordWrapping
        
        let attributed = NSMutableAttributedString()
        attributed.append(
            NSAttributedString(
                string: "  \(label) ",
                attributes: [
                    .font: NSFont.boldSystemFont(ofSize: NSFont.systemFontSize),
                    .paragraphStyle: paragraphStyle
                ]
            ))
        attributed.append(
            NSAttributedString(
                string: value,
                attributes: [.paragraphStyle: paragraphStyle]
            ))
        return attributed
    }

    // MARK: - Settings Window

    /// Creates a new settings window with the SettingsView.
    ///
    /// - Returns: A configured NSWindow
    private func createSettingsWindow() -> NSWindow {
        let hosting = NSHostingController(rootView: SettingsView())
        let window = NSWindow(contentViewController: hosting)
        window.title = "\(appName) Settings"
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.setContentSize(
            NSSize(
                width: Constants.settingsWidth,
                height: Constants.settingsHeight
            ))

        window.collectionBehavior = [.moveToActiveSpace]
        window.canHide = true

        window.center()
        return window
    }

    /// Shows a window and brings it to the front.
    ///
    /// - Parameter window: The window to show
    private func showWindow(_ window: NSWindow?) {
        window?.level = .normal
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

// MARK: - Twitch Token Validation

extension AppDelegate {
    /// Sets the reauth needed flag in UserDefaults.
    ///
    /// - Parameter needed: Whether re-authentication is required
    @MainActor
    private func setReauthNeeded(_ needed: Bool) {
        UserDefaults.standard.set(needed, forKey: "twitchReauthNeeded")
    }

    /// Displays a user notification for Twitch authentication issues.
    ///
    /// Uses the UserNotifications framework to display system notifications.
    ///
    /// - Parameters:
    ///   - title: The notification title
    ///   - message: The notification message body
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
                                "AppDelegate: Failed to send notification - \(error.localizedDescription)",
                                category: "Notifications"
                            )
                        }
                    }
                }
            }
        }
    }

    /// Opens the settings window and navigates to the Twitch Integration section.
    private func openSettingsToTwitch() {
        UserDefaults.standard.set("twitchIntegration", forKey: "selectedSettingsSection")
        openSettings()
    }

    /// Validates the stored Twitch token on application launch.
    ///
    /// Checks if the token is still valid with Twitch.
    /// If invalid, sets the reauth needed flag, displays a notification, and opens Settings to Twitch section.
    fileprivate func validateTwitchTokenOnBoot() async {
        guard let token = KeychainService.loadTwitchToken(), !token.isEmpty else {
            setReauthNeeded(false)
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
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                    self?.openSettingsToTwitch()
                }
            }
        }
    }

    /// Automatically joins the configured Twitch channel on application launch.
    ///
    /// Performs validation checks before attempting connection:
    /// - Valid token exists in keychain
    /// - Channel ID is configured
    /// - Token has been validated (reauth not required)
    ///
    /// Introduces a 2-second delay to ensure services are fully initialized.
    /// Notifies user if auto-join fails.
    fileprivate func autoJoinTwitchChannel() async {
        guard let token = KeychainService.loadTwitchToken(), !token.isEmpty,
            let channelID = KeychainService.loadTwitchChannelID(), !channelID.isEmpty,
            !UserDefaults.standard.bool(forKey: "twitchReauthNeeded")
        else {
            return
        }

        try? await Task.sleep(nanoseconds: 2_000_000_000)

        await MainActor.run {
            guard let clientID = TwitchChatService.resolveClientID(), !clientID.isEmpty else {
                Log.error(
                    "AppDelegate: Cannot auto-join - missing Twitch Client ID", category: "Twitch")
                self.showTwitchAuthNotification(
                    title: "Twitch Configuration Error",
                    message: "Missing Twitch Client ID. Opening Settings..."
                )
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                    self?.openSettingsToTwitch()
                }
                return
            }

            Task {
                do {
                    try await twitchService?.connectToChannel(
                        channelName: channelID,
                        token: token,
                        clientID: clientID
                    )

                    Log.info(
                        "AppDelegate: Auto-joined Twitch channel \(channelID)", category: "Twitch")
                } catch {
                    Log.error(
                        "AppDelegate: Failed to auto-join Twitch channel - \(error.localizedDescription)",
                        category: "Twitch"
                    )
                    self.showTwitchAuthNotification(
                        title: "Twitch Connection Failed",
                        message: "Could not connect to Twitch. Opening Settings..."
                    )
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                        self?.openSettingsToTwitch()
                    }
                }
            }
        }
    }
}

// MARK: - Music Playback Monitor Delegate

extension AppDelegate: MusicPlaybackMonitorDelegate {
    /// Called when the music monitor detects a new track playing.
    ///
    /// Preserves the previous track information for !last command support.
    /// Only updates lastSong when the track actually changes to avoid overwriting with duplicates.
    ///
    /// - Parameters:
    ///   - monitor: The music monitor
    ///   - track: The track title
    ///   - artist: The artist name
    ///   - album: The album title
    func musicPlaybackMonitor(
        _ monitor: MusicPlaybackMonitor, didUpdateTrack track: String, artist: String, album: String
    ) {
        // Only save current as last if the track is actually changing
        if currentSong != track {
            lastSong = currentSong
            lastArtist = currentArtist
        }
        
        currentSong = track
        currentArtist = artist
        currentAlbum = album

        updateTrackDisplay(song: track, artist: artist, album: album)
    }

    /// Called when the music monitor detects a status change (e.g., playback stopped).
    ///
    /// Clears the current track information only when playback has actually stopped.
    ///
    /// - Parameters:
    ///   - monitor: The music monitor
    ///   - status: The status message
    func musicPlaybackMonitor(_ monitor: MusicPlaybackMonitor, didUpdateStatus status: String) {
        if status == "No track playing" {
            currentSong = nil
            currentArtist = nil
            currentAlbum = nil
        }

        updateNowPlaying(status)
    }
}
