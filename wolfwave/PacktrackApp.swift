//
//  PacktrackApp.swift
//  packtrack
//
//  Created by Nathanial Henniges on 1/8/26.
//

import AppKit
import SwiftUI

/// The main application structure for PackTrack.
///
/// PackTrack is a macOS menu bar app that monitors Apple Music playback
/// and displays currently playing tracks in the system menu bar.
@main
struct PacktrackApp: App {
    /// The application delegate that handles menu bar UI and music tracking
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings {
            SettingsView()
        }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    // MARK: - Constants

    fileprivate enum Constants {
        static let defaultAppName = "Pack Track"
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
        }
    }

    // MARK: - Properties

    var statusItem: NSStatusItem?
    var musicMonitor: MusicPlaybackMonitor?
    var settingsWindow: NSWindow?
    var twitchService: TwitchChatService?

    /// Current song information for Twitch bot
    private var currentSong: String?
    private var currentArtist: String?
    private var currentAlbum: String?

    private var appName: String {
        Bundle.main.infoDictionary?["CFBundleDisplayName"] as? String ?? Bundle.main
            .infoDictionary?["CFBundleName"] as? String ?? Constants.displayName
    }

    // MARK: - Lifecycle

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupStatusItem()
        setupMenu()
        setupMusicMonitor()
        setupTwitchService()
        setupNotificationObservers()
        initializeTrackingState()

        // Validate stored Twitch token on boot and set a reauth flag if needed
        Task { [weak self] in
            await self?.validateTwitchTokenOnBoot()
        }
    }

    // MARK: - Menu State Helpers

    /// Resets the now playing menu items to show a status message.
    ///
    /// This method hides the artist and album items and displays a single
    /// status message in gray text (e.g., "No track playing", "Tracking disabled").
    ///
    /// - Parameter message: The status message to display
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

    /// Updates the menu to display a status message.
    ///
    /// This is a convenience method that calls resetNowPlayingMenu on the main queue.
    ///
    /// - Parameter text: The status message to display
    func updateNowPlaying(_ text: String) {
        DispatchQueue.main.async { [weak self] in
            self?.resetNowPlayingMenu(message: text)
        }
    }

    /// Updates the menu to display currently playing track information.
    ///
    /// If track information is provided, displays song, artist, and album on separate lines.
    /// If any parameter is nil, displays "No track playing" instead.
    ///
    /// - Parameters:
    ///   - song: The song name (optional)
    ///   - artist: The artist name (optional)
    ///   - album: The album name (optional)
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

    // MARK: - Actions

    /// Handles changes to the tracking enabled/disabled setting.
    ///
    /// This method is called when the user toggles tracking in the settings view.
    /// It starts or stops the music tracker accordingly and updates the menu display.
    ///
    /// - Parameter notification: Contains the new enabled state in userInfo["enabled"]
    @objc func trackingSettingChanged(_ notification: Notification) {
        guard let enabled = notification.userInfo?["enabled"] as? Bool else { return }

        enabled ? musicMonitor?.startTracking() : stopTrackingAndUpdate()
    }

    private func stopTrackingAndUpdate() {
        musicMonitor?.stopTracking()
        updateNowPlaying("Tracking disabled")
    }

    /// Opens the settings window.
    ///
    /// Creates the settings window on first open and reuses it on subsequent opens.
    /// The window is brought to the front and the app is activated.
    @objc func openSettings() {
        if settingsWindow == nil {
            settingsWindow = createSettingsWindow()
        }

        showWindow(settingsWindow)
    }

    /// Shows the standard About panel for the application.
    ///
    /// Displays macOS's built-in About panel with app information from Info.plist.
    @objc func showAbout() {
        NSApp.orderFrontStandardAboutPanel(options: [.applicationName: appName])
        NSApp.activate(ignoringOtherApps: true)
    }

    /// Returns the current song information as a formatted string.
    ///
    /// Used by the Twitch bot to respond to !song commands.
    func getCurrentSongInfo() -> String {
        guard let song = currentSong, let artist = currentArtist else {
            return "No track currently playing"
        }
        return "Now playing: \(song) by \(artist)"
    }

    // MARK: - Private Helpers

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        configureStatusItemButton()
    }

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

    private func setupMenu() {
        let menu = createMenu()
        statusItem?.menu = menu
        resetNowPlayingMenu(message: "No track playing")
    }

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

    private func addNowPlayingItems(to menu: NSMenu) {
        let headerItem = NSMenuItem(title: "Now Playing:", action: nil, keyEquivalent: "")
        headerItem.isEnabled = false
        menu.addItem(headerItem)

        // Add three disabled items for song, artist, album
        for _ in 0..<3 {
            let item = NSMenuItem(title: "", action: nil, keyEquivalent: "")
            item.isEnabled = false
            menu.addItem(item)
        }
    }

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

    private func addQuitItem(to menu: NSMenu) {
        menu.addItem(
            NSMenuItem(
                title: "Quit",
                action: #selector(NSApplication.terminate(_:)),
                keyEquivalent: "q"
            ))
    }

    private func setupMusicMonitor() {
        musicMonitor = MusicPlaybackMonitor()
        musicMonitor?.delegate = self
    }

    private func setupTwitchService() {
        twitchService = TwitchChatService()
        twitchService?.getCurrentSongInfo = { [weak self] in
            guard let self = self,
                let song = self.currentSong,
                let artist = self.currentArtist
            else {
                return "No track currently playing"
            }
            return "Now playing: \(song) by \(artist)"
        }
    }

    private func setupNotificationObservers() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(trackingSettingChanged),
            name: NSNotification.Name(Constants.Notification.trackingSettingChanged),
            object: nil
        )
    }

    private func initializeTrackingState() {
        setDefaultTrackingStateIfNeeded()

        if isTrackingEnabled() {
            musicMonitor?.startTracking()
        } else {
            resetNowPlayingMenu(message: "Tracking disabled")
        }
    }

    private func setDefaultTrackingStateIfNeeded() {
        if UserDefaults.standard.object(forKey: Constants.UserDefaults.trackingEnabled) == nil {
            UserDefaults.standard.set(true, forKey: Constants.UserDefaults.trackingEnabled)
        }
    }

    private func isTrackingEnabled() -> Bool {
        UserDefaults.standard.bool(forKey: Constants.UserDefaults.trackingEnabled)
    }

    private func createStatusAttributedString(_ message: String) -> NSAttributedString {
        NSAttributedString(
            string: "  \(message)",
            attributes: [
                .foregroundColor: NSColor.secondaryLabelColor,
                .font: NSFont.systemFont(ofSize: NSFont.systemFontSize - 1),
            ]
        )
    }

    private func updateMenuItem(at index: Int, with title: NSAttributedString, hidden: Bool) {
        guard let menu = statusItem?.menu, index < menu.items.count else { return }
        menu.items[index].attributedTitle = title
        menu.items[index].isHidden = hidden
    }

    private func hideMenuItem(at index: Int) {
        guard let menu = statusItem?.menu, index < menu.items.count else { return }
        menu.items[index].isHidden = true
    }

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

    private func createLabeledText(label: String, value: String) -> NSAttributedString {
        let attributed = NSMutableAttributedString()
        attributed.append(
            NSAttributedString(
                string: "  \(label) ",
                attributes: [.font: NSFont.boldSystemFont(ofSize: NSFont.systemFontSize)]
            ))
        attributed.append(NSAttributedString(string: value))
        return attributed
    }

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

        // Make window appear in Dock
        window.collectionBehavior = [.moveToActiveSpace]
        window.canHide = true

        window.center()
        return window
    }

    private func showWindow(_ window: NSWindow?) {
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

// MARK: - Twitch Token Validation

extension AppDelegate {
    @MainActor
    private func setReauthNeeded(_ needed: Bool) {
        UserDefaults.standard.set(needed, forKey: "twitchReauthNeeded")
    }

    fileprivate func validateTwitchTokenOnBoot() async {
        guard let token = KeychainService.loadTwitchToken(), !token.isEmpty else {
            setReauthNeeded(false)  // no token stored; don't nag until user tries to auth
            return
        }

        // Validate token and scopes
        let isValid = await twitchService?.validateToken(token) ?? false
        await MainActor.run {
            setReauthNeeded(!isValid)
        }
    }
}

// MARK: - MusicPlaybackMonitorDelegate

/// Extension implementing the MusicPlaybackMonitorDelegate protocol.
///
/// Receives callbacks from MusicPlaybackMonitor and updates the menu bar display accordingly.
extension AppDelegate: MusicPlaybackMonitorDelegate {
    func musicPlaybackMonitor(
        _ monitor: MusicPlaybackMonitor, didUpdateTrack track: String, artist: String, album: String
    ) {
        // Store current song info for Twitch bot
        currentSong = track
        currentArtist = artist
        currentAlbum = album

        updateTrackDisplay(song: track, artist: artist, album: album)
    }

    func musicPlaybackMonitor(_ monitor: MusicPlaybackMonitor, didUpdateStatus status: String) {
        // Clear song info when playback stops
        if status != "No track playing" {
            currentSong = nil
            currentArtist = nil
            currentAlbum = nil
        }

        updateNowPlaying(status)
    }
}
