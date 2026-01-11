//
//  WolfWaveApp.swift
//  wolfwave
//
//  Created by MrDemonWolf, Inc. on 1/8/26.
//

import AppKit
import SwiftUI

@main
struct WolfWaveApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings {
            SettingsView()
        }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
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
            static let dockVisibility = "dockVisibility"

        enum UserDefaults {
            static let trackingEnabled = "trackingEnabled"
        }
    }

    var statusItem: NSStatusItem?
    var musicMonitor: MusicPlaybackMonitor?
    var settingsWindow: NSWindow?
    var twitchService: TwitchChatService?

    private var currentSong: String?
    private var currentArtist: String?
    private var currentAlbum: String?

    private var appName: String {
        Bundle.main.infoDictionary?["CFBundleDisplayName"] as? String ?? Bundle.main
            .infoDictionary?["CFBundleName"] as? String ?? Constants.displayName
    }

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

    func updateNowPlaying(_ text: String) {
        DispatchQueue.main.async { [weak self] in
            self?.resetNowPlayingMenu(message: text)
        }
    }

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

    @objc func trackingSettingChanged(_ notification: Notification) {
        guard let enabled = notification.userInfo?["enabled"] as? Bool else { return }

        enabled ? musicMonitor?.startTracking() : stopTrackingAndUpdate()
    }

    private func stopTrackingAndUpdate() {
        musicMonitor?.stopTracking()
        updateNowPlaying("Tracking disabled")
    }

    @objc func openSettings() {
        // Dismiss status menu to avoid focus issues
        statusItem?.menu?.cancelTracking()
        // Temporarily show in dock if in menu-only mode
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

    @objc func showAbout() {
        // Dismiss status menu to avoid focus issues
        statusItem?.menu?.cancelTracking()
        // Temporarily show in dock if in menu-only mode
        let currentMode = UserDefaults.standard.string(forKey: "dockVisibility") ?? "both"
        if currentMode == "menuOnly" {
            NSApp.setActivationPolicy(.regular)
        }
        
        NSApp.orderFrontStandardAboutPanel(options: [.applicationName: appName])
        NSApp.activate(ignoringOtherApps: true)
    }

    /// When the user clicks the Dock icon, open Settings (and ensure we're shown in Dock if menu-only)
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        let currentMode = UserDefaults.standard.string(forKey: "dockVisibility") ?? "both"
        if currentMode == "menuOnly" {
            NSApp.setActivationPolicy(.regular)
        }

        openSettings()
        return true
    }

    @objc func dockVisibilityChanged(_ notification: Notification) {
        guard let mode = notification.userInfo?["mode"] as? String else { return }
        applyDockVisibility(mode)
    }

    private func applyInitialDockVisibility() {
        let mode = UserDefaults.standard.string(forKey: "dockVisibility") ?? "both"
        applyDockVisibility(mode)
    }

    private func applyDockVisibility(_ mode: String) {
        switch mode {
        case "menuOnly":
            // Keep menu bar visible; show Dock if any app windows are open
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
    
    private func restoreMenuOnlyIfNeeded() {
        let currentMode = UserDefaults.standard.string(forKey: "dockVisibility") ?? "both"
        
        // Only restore menu-only mode if that's the setting and no windows are visible
        guard currentMode == "menuOnly" else { return }
        
        // Check if any app windows (not system windows) are still visible
        let hasVisibleWindows = NSApp.windows.contains { window in
            window.isVisible && window.canBecomeKey && window.level == .normal
        }
        
        if !hasVisibleWindows {
            NSApp.setActivationPolicy(.accessory)
        }
    }

    @objc private func handleWindowClose(_ notification: Notification) {
        // Delay slightly to allow window state to settle, then restore menu-only if appropriate
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            self?.restoreMenuOnlyIfNeeded()
        }
    }

    func getCurrentSongInfo() -> String {
        guard let song = currentSong, let artist = currentArtist else {
            return "No track currently playing"
        }
        return "Now playing: \(song) by \(artist)"
    }

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
        let headerItem = NSMenuItem(title: "♪ Now Playing", action: nil, keyEquivalent: "")
        headerItem.isEnabled = false
        menu.addItem(headerItem)

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
        // No window delegate needed; close handling is global via notifications

        window.center()
        return window
    }

    private func showWindow(_ window: NSWindow?) {
        window?.level = .normal
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

extension AppDelegate {
    @MainActor
    private func setReauthNeeded(_ needed: Bool) {
        UserDefaults.standard.set(needed, forKey: "twitchReauthNeeded")
    }

    fileprivate func validateTwitchTokenOnBoot() async {
        guard let token = KeychainService.loadTwitchToken(), !token.isEmpty else {
            setReauthNeeded(false)
            return
        }

        let isValid = await twitchService?.validateToken(token) ?? false
        await MainActor.run {
            setReauthNeeded(!isValid)
        }
    }

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
                }
            }
        }
    }
}

extension AppDelegate: MusicPlaybackMonitorDelegate {
    func musicPlaybackMonitor(
        _ monitor: MusicPlaybackMonitor, didUpdateTrack track: String, artist: String, album: String
    ) {
        currentSong = track
        currentArtist = artist
        currentAlbum = album

        updateTrackDisplay(song: track, artist: artist, album: album)
    }

    func musicPlaybackMonitor(_ monitor: MusicPlaybackMonitor, didUpdateStatus status: String) {
        if status != "No track playing" {
            currentSong = nil
            currentArtist = nil
            currentAlbum = nil
        }

        updateNowPlaying(status)
    }
}

// NSWindowDelegate not required; window close is handled via global notifications
