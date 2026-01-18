import AppKit
import SwiftUI
import UserNotifications

@main
struct WolfWaveApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings {
            SettingsView()
        }
    }
}

// MARK: - Notifications & App Helpers

extension Notification.Name {
    static let toggleSettingsSidebar = Notification.Name("com.wolfwave.toggleSettingsSidebar")
}

extension AppDelegate {
    @objc func toggleSettingsSidebar(_ sender: Any?) {
        NotificationCenter.default.post(name: .toggleSettingsSidebar, object: nil)
    }
}

// MARK: - App Delegate

/// Manages the menu bar item, music monitoring, and Twitch integration.
class AppDelegate: NSObject, NSApplicationDelegate, NSToolbarDelegate {
    // Toolbar identifier used for the settings window
    private static let settingsToolbarIdentifier = "com.wolfwave.settings.toolbar"
    
    // MARK: - Properties
    
    var statusItem: NSStatusItem?
    var musicMonitor: MusicPlaybackMonitor?
    var settingsWindow: NSWindow?
    var twitchService: TwitchChatService?

    private var currentSong: String?
    private var currentArtist: String?
    private var currentAlbum: String?
    private var lastSong: String?
    private var lastArtist: String?

    private var appName: String {
        Bundle.main.infoDictionary?["CFBundleDisplayName"] as? String ?? Bundle.main
            .infoDictionary?["CFBundleName"] as? String ?? AppConstants.AppInfo.displayName
    }

    // MARK: - Lifecycle

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
    
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        let currentMode = UserDefaults.standard.string(forKey: AppConstants.UserDefaults.dockVisibility) ?? AppConstants.DockVisibility.default
        if currentMode == AppConstants.DockVisibility.menuOnly {
            NSApp.setActivationPolicy(.regular)
        }

        openSettings()
        return true
    }

    // MARK: - Track Display Updates

    private func resetNowPlayingMenu(message: String) {
        guard let menu = statusItem?.menu,
            menu.items.count > AppConstants.MenuItemIndex.album
        else {
            return
        }

        let statusText = createStatusAttributedString(message)
        updateMenuItem(at: AppConstants.MenuItemIndex.song, with: statusText, hidden: false)
        hideMenuItem(at: AppConstants.MenuItemIndex.artist)
        hideMenuItem(at: AppConstants.MenuItemIndex.album)
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

    // MARK: - Notification Handlers

    @objc func trackingSettingChanged(_ notification: Notification) {
        guard let enabled = notification.userInfo?["enabled"] as? Bool else { return }

        enabled ? musicMonitor?.startTracking() : stopTrackingAndUpdate()
    }

    private func stopTrackingAndUpdate() {
        musicMonitor?.stopTracking()
        updateNowPlaying("Tracking disabled")
    }

    @objc func dockVisibilityChanged(_ notification: Notification) {
        guard let mode = notification.userInfo?["mode"] as? String else { return }
        applyDockVisibility(mode)
    }

    @objc private func handleWindowClose(_ notification: Notification) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            self?.restoreMenuOnlyIfNeeded()
        }
    }

    // MARK: - Menu Actions

    @objc func openSettings() {
        statusItem?.menu?.cancelTracking()
        
        let currentMode = UserDefaults.standard.string(forKey: AppConstants.UserDefaults.dockVisibility) ?? AppConstants.DockVisibility.default
        if currentMode == AppConstants.DockVisibility.menuOnly {
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

    @objc func showAbout() {
        statusItem?.menu?.cancelTracking()
        
        let currentMode = UserDefaults.standard.string(forKey: AppConstants.UserDefaults.dockVisibility) ?? AppConstants.DockVisibility.default
        if currentMode == AppConstants.DockVisibility.menuOnly {
            NSApp.setActivationPolicy(.regular)
        }
        
        NSApp.orderFrontStandardAboutPanel(options: [.applicationName: appName])
        NSApp.activate(ignoringOtherApps: true)
    }

    // MARK: - Dock Visibility Management

    private func applyInitialDockVisibility() {
        let mode = UserDefaults.standard.string(forKey: "dockVisibility") ?? "both"
        applyDockVisibility(mode)
    }

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
    
    private func restoreMenuOnlyIfNeeded() {
        let currentMode = UserDefaults.standard.string(forKey: AppConstants.UserDefaults.dockVisibility) ?? AppConstants.DockVisibility.default
        
        guard currentMode == AppConstants.DockVisibility.menuOnly else { return }
        
        let hasVisibleWindows = NSApp.windows.contains { window in
            window.isVisible && window.canBecomeKey && window.level == .normal
        }
        
        if !hasVisibleWindows {
            NSApp.setActivationPolicy(.accessory)
        }
    }

    // MARK: - Song Info Provider

    private func isMusicAppOpen() -> Bool {
        let workspace = NSWorkspace.shared
        let runningApps = workspace.runningApplications
        return runningApps.contains { app in
            app.bundleIdentifier == AppConstants.Music.bundleIdentifier
        }
    }

    func getCurrentSongInfo() -> String {
        guard isMusicAppOpen() else {
            return "🐺 Music app is not running"
        }
        
        guard let song = currentSong, let artist = currentArtist else {
            return "🐺 No tracks in the den"
        }
        return "🐺 Now playing: \(song) by \(artist)"
    }

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

    // MARK: - Menu Setup

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

    // MARK: - Music Monitor Setup

    private func setupMusicMonitor() {
        musicMonitor = MusicPlaybackMonitor()
        musicMonitor?.delegate = self
    }

    // MARK: - Twitch Service Setup

    private func setupTwitchService() {
        twitchService = TwitchChatService()
        twitchService?.getCurrentSongInfo = { [weak self] in
            self?.getCurrentSongInfo() ?? "No song is currently playing"
        }
        twitchService?.getLastSongInfo = { [weak self] in
            self?.getLastSongInfo() ?? "No song is currently playing"
        }
    }

    // MARK: - Notification Observers

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
    }

    // MARK: - Tracking State

    private func initializeTrackingState() {
        if UserDefaults.standard.object(forKey: AppConstants.UserDefaults.trackingEnabled) == nil {
            UserDefaults.standard.set(true, forKey: AppConstants.UserDefaults.trackingEnabled)
        }

        if isTrackingEnabled() {
            musicMonitor?.startTracking()
        } else {
            resetNowPlayingMenu(message: "Tracking disabled")
        }
    }

    private func isTrackingEnabled() -> Bool {
        UserDefaults.standard.bool(forKey: AppConstants.UserDefaults.trackingEnabled)
    }

    // MARK: - Menu Item Helpers

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

        menu.items[AppConstants.MenuItemIndex.song].attributedTitle = songAttr
        menu.items[AppConstants.MenuItemIndex.artist].attributedTitle = artistAttr
        menu.items[AppConstants.MenuItemIndex.album].attributedTitle = albumAttr

        [
            AppConstants.MenuItemIndex.song, AppConstants.MenuItemIndex.artist,
            AppConstants.MenuItemIndex.album,
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

    // MARK: - Settings Window

    private func createSettingsWindow() -> NSWindow {
        let hosting = NSHostingController(rootView: SettingsView())
        let frame = CGRect(x: 0, y: 0, width: AppConstants.UI.settingsWidth, height: AppConstants.UI.settingsHeight)
        let style: NSWindow.StyleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
        let window = NSWindow(contentRect: frame, styleMask: style, backing: .buffered, defer: false)
        window.contentViewController = hosting
        
        // Configure title bar for VoiceInk-style appearance
        window.title = ""
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true

        // Add a toolbar that sits in the unified title bar
        let toolbar = NSToolbar(identifier: NSToolbar.Identifier(Self.settingsToolbarIdentifier))
        toolbar.displayMode = .iconOnly
        toolbar.allowsUserCustomization = false
        toolbar.showsBaselineSeparator = false
        toolbar.delegate = self
        if #available(macOS 11.0, *) {
            toolbar.centeredItemIdentifier = nil
        }
        window.toolbar = toolbar
        window.toolbarStyle = .unified

        window.collectionBehavior = [.moveToActiveSpace]
        window.canHide = true

        window.center()
        return window
    }

    private func showWindow(_ window: NSWindow?) {
        window?.level = .normal
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

// MARK: - Toolbar Delegate

extension AppDelegate {
    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        return [.toggleSidebar, .flexibleSpace]
    }

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        return [.flexibleSpace, .toggleSidebar, .flexibleSpace]
    }

    func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier, willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        // Use system-provided toggle sidebar item
        if itemIdentifier == .toggleSidebar {
            return nil // Return nil to use system default
        }
        return nil
    }
}

// MARK: - Twitch Token Validation

extension AppDelegate {
    @MainActor
    private func setReauthNeeded(_ needed: Bool) {
        UserDefaults.standard.set(needed, forKey: AppConstants.UserDefaults.twitchReauthNeeded)
    }

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

    private func openSettingsToTwitch() {
        UserDefaults.standard.set(AppConstants.Twitch.settingsSection, forKey: AppConstants.UserDefaults.selectedSettingsSection)
        openSettings()
    }

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
                DispatchQueue.main.asyncAfter(deadline: .now() + AppConstants.Timing.notificationDelay) { [weak self] in
                    self?.openSettingsToTwitch()
                }
            }
        }
    }

    fileprivate func autoJoinTwitchChannel() async {
        guard let token = KeychainService.loadTwitchToken(), !token.isEmpty,
            let channelID = KeychainService.loadTwitchChannelID(), !channelID.isEmpty,
            !UserDefaults.standard.bool(forKey: AppConstants.UserDefaults.twitchReauthNeeded)
        else {
            return
        }

        try? await Task.sleep(nanoseconds: UInt64(AppConstants.Timing.twitchAutoJoinDelay * 1_000_000_000))

        await MainActor.run {
            guard let clientID = TwitchChatService.resolveClientID(), !clientID.isEmpty else {
                Log.error("Missing Twitch Client ID", category: "Twitch")
                self.showTwitchAuthNotification(
                    title: "Twitch Configuration Error",
                    message: "Missing Twitch Client ID. Opening Settings..."
                )
                DispatchQueue.main.asyncAfter(deadline: .now() + AppConstants.Timing.notificationDelay) { [weak self] in
                    self?.openSettingsToTwitch()
                }
                return
            }

            Task {
                do {
                    self.twitchService?.shouldSendConnectionMessageOnSubscribe = false
                    try await twitchService?.connectToChannel(
                        channelName: channelID,
                        token: token,
                        clientID: clientID
                    )

                    self.twitchService?.shouldSendConnectionMessageOnSubscribe = true

                    Log.info("Auto-joined Twitch channel \(channelID)", category: "Twitch")
                } catch {
                    Log.error(
                        "Failed to auto-join Twitch channel: \(error.localizedDescription)",
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
    func musicPlaybackMonitor(
        _ monitor: MusicPlaybackMonitor, didUpdateTrack track: String, artist: String, album: String
    ) {
        if currentSong != track {
            lastSong = currentSong
            lastArtist = currentArtist
        }
        
        currentSong = track
        currentArtist = artist
        currentAlbum = album

        updateTrackDisplay(song: track, artist: artist, album: album)
    }

    func musicPlaybackMonitor(_ monitor: MusicPlaybackMonitor, didUpdateStatus status: String) {
        if status == "No track playing" {
            currentSong = nil
            currentArtist = nil
            currentAlbum = nil
        }

        updateNowPlaying(status)
    }
}
