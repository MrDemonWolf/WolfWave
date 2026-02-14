//
//  WolfWaveApp.swift
//  wolfwave
//
//  Created by MrDemonWolf, Inc. on 1/17/26.
//

/// WolfWave — macOS menu bar app bridging Apple Music to Twitch, Discord, and stream overlays.

import AppKit
import SwiftUI
import UserNotifications

// MARK: - App Entry Point

/// SwiftUI entry point. Runs as a menu bar app with a Settings scene.
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

/// Orchestrates the menu bar, services, and window lifecycle.
class AppDelegate: NSObject, NSApplicationDelegate, NSToolbarDelegate, NSWindowDelegate {
    private static let settingsToolbarIdentifier = "com.wolfwave.settings.toolbar"
    static weak var shared: AppDelegate?

    // MARK: - Properties

    var statusItem: NSStatusItem?
    var musicMonitor: MusicPlaybackMonitor?
    var settingsWindow: NSWindow?
    var onboardingWindow: NSWindow?
    var twitchService: TwitchChatService?
    var discordService: DiscordRPCService?
    var updateChecker: UpdateCheckerService?
    var websocketServer: WebSocketServerService?

    private(set) var currentSong: String?
    private(set) var currentArtist: String?
    private(set) var currentAlbum: String?
    private var currentDuration: TimeInterval = 0
    private var currentElapsed: TimeInterval = 0
    private var lastSong: String?
    private var lastArtist: String?

    private var currentDockVisibilityMode: String {
        UserDefaults.standard.string(forKey: AppConstants.UserDefaults.dockVisibility)
            ?? AppConstants.DockVisibility.default
    }

    private var appName: String {
        Bundle.main.infoDictionary?["CFBundleDisplayName"] as? String ?? Bundle.main
            .infoDictionary?["CFBundleName"] as? String ?? AppConstants.AppInfo.displayName
    }

    // MARK: - Lifecycle

    /// Initializes all services, registers observers, and shows onboarding or validates tokens.
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

        if !OnboardingViewModel.hasCompletedOnboarding {
            showOnboarding()
        } else {
            Task { [weak self] in
                await self?.validateTwitchTokenOnBoot()
            }
        }

        applyInitialDockVisibility()
    }
    
    /// Reopens the Settings window when the dock icon is clicked.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if currentDockVisibilityMode == AppConstants.DockVisibility.menuOnly {
            NSApp.setActivationPolicy(.regular)
        }

        openSettings()
        return true
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

    // MARK: - Notification Handlers

    /// Starts or stops the music monitor when the tracking toggle changes.
    @objc func trackingSettingChanged(_ notification: Notification) {
        guard let enabled = notification.userInfo?["enabled"] as? Bool else { return }

        enabled ? musicMonitor?.startTracking() : stopTrackingAndUpdate()
    }

    /// Stops the music monitor and clears the now-playing display.
    private func stopTrackingAndUpdate() {
        musicMonitor?.stopTracking()
        postNowPlayingUpdate(song: nil, artist: nil, album: nil)
    }

    /// Enables or disables the Discord IPC service and pushes current track if enabling.
    @objc func discordPresenceSettingChanged(_ notification: Notification) {
        guard let enabled = notification.userInfo?["enabled"] as? Bool else { return }
        discordService?.setEnabled(enabled)

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

    /// Applies the new dock visibility mode from the notification payload.
    @objc func dockVisibilityChanged(_ notification: Notification) {
        guard let mode = notification.userInfo?["mode"] as? String else { return }
        applyDockVisibility(mode)
    }

    /// Restores accessory activation policy after the last window closes (menu-only mode).
    @objc private func handleWindowClose(_ notification: Notification) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            self?.restoreMenuOnlyIfNeeded()
        }
    }

    // MARK: - Menu Actions

    /// Opens or brings the Settings window to the front.
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

    /// Shows the About panel with documentation and legal links.
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

    /// Builds the About panel credits with linked documentation and legal pages.
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

    /// Applies the stored dock visibility mode on launch.
    private func applyInitialDockVisibility() {
        applyDockVisibility(currentDockVisibilityMode)
    }

    /// Sets activation policy and status item visibility based on the given mode.
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
    
    /// Hides the dock icon if menu-only mode is active and no windows remain visible.
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

    /// Returns `true` if Apple Music is currently running.
    private func isMusicAppOpen() -> Bool {
        let workspace = NSWorkspace.shared
        let runningApps = workspace.runningApplications
        return runningApps.contains { app in
            app.bundleIdentifier == AppConstants.Music.bundleIdentifier
        }
    }

    /// Returns a formatted string with the current track for Twitch bot commands.
    func getCurrentSongInfo() -> String {
        guard isMusicAppOpen() else {
            return "🐺 Music app is not running"
        }
        
        guard let song = currentSong, let artist = currentArtist else {
            return "🐺 No tracks in the den"
        }
        return "🐺 Now playing: \(song) by \(artist)"
    }

    /// Returns a formatted string with the previously played track for Twitch bot commands.
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

    /// Creates the menu bar status item with the tray icon.
    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        configureStatusItemButton()
    }

    /// Sets the status item button image, falling back to a system music note.
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

    /// Builds and attaches the status bar dropdown menu.
    private func setupMenu() {
        let menu = createMenu()
        statusItem?.menu = menu
    }

    private func createMenu() -> NSMenu {
        let menu = NSMenu()

        addSettingsItem(to: menu)
        addAboutItem(to: menu)
        menu.addItem(.separator())
        addQuitItem(to: menu)

        return menu
    }

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
                title: AppConstants.MenuLabels.quit,
                action: #selector(NSApplication.terminate(_:)),
                keyEquivalent: "q"
            ))
    }

    // MARK: - Service Initialization

    /// Creates the music playback monitor and sets this delegate.
    private func setupMusicMonitor() {
        musicMonitor = MusicPlaybackMonitor()
        musicMonitor?.delegate = self
    }

    /// Creates the Twitch chat service and wires up song info callbacks.
    private func setupTwitchService() {
        twitchService = TwitchChatService()

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

    /// Creates the Discord RPC service, registers state callbacks, and enables if configured.
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

        discordService?.onArtworkResolved = { [weak self] url, track, artist in
            self?.websocketServer?.updateArtworkURL(url)
        }

        let enabled = UserDefaults.standard.bool(forKey: AppConstants.UserDefaults.discordPresenceEnabled)
        if enabled {
            discordService?.setEnabled(true)
        }
    }

    // MARK: - WebSocket Server

    /// Creates the WebSocket server on the configured port and enables if configured.
    private func setupWebSocketServer() {
        let storedPort = UserDefaults.standard.integer(forKey: AppConstants.UserDefaults.websocketServerPort)
        let port: UInt16 = storedPort > 0 ? UInt16(clamping: storedPort) : AppConstants.WebSocketServer.defaultPort

        websocketServer = WebSocketServerService(port: port)

        websocketServer?.onStateChange = { newState, clientCount in
            Log.debug("WebSocket: State changed to \(newState.rawValue) (\(clientCount) clients)", category: "WebSocket")
        }

        let enabled = UserDefaults.standard.bool(forKey: AppConstants.UserDefaults.websocketEnabled)
        if enabled {
            websocketServer?.setEnabled(true)
        }
    }

    /// Toggles the WebSocket server and applies any port change from the notification.
    @objc func websocketServerSettingChanged(_ notification: Notification) {
        let enabled = UserDefaults.standard.bool(forKey: AppConstants.UserDefaults.websocketEnabled)
        websocketServer?.setEnabled(enabled)

        if let port = notification.userInfo?["port"] as? UInt16 {
            websocketServer?.updatePort(port)
        }
    }

    // MARK: - Widget Artwork

    private var widgetArtworkCache: [String: String] = [:]

    /// Fetches album artwork from the iTunes Search API and forwards it to the WebSocket server.
    private func fetchArtworkForWidget(track: String, artist: String) {
        let cacheKey = "\(track)|\(artist)"

        if let cached = widgetArtworkCache[cacheKey] {
            websocketServer?.updateArtworkURL(cached)
            return
        }

        let query = "\(track) \(artist)"
        guard let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "https://itunes.apple.com/search?media=music&entity=song&limit=1&term=\(encoded)") else {
            return
        }

        URLSession.shared.dataTask(with: url) { [weak self] data, _, error in
            guard let data, error == nil,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let results = json["results"] as? [[String: Any]],
                  let first = results.first,
                  let artworkUrl = first["artworkUrl100"] as? String else {
                return
            }

            let highRes = artworkUrl.replacingOccurrences(of: "100x100", with: "512x512")
            self?.widgetArtworkCache[cacheKey] = highRes
            self?.websocketServer?.updateArtworkURL(highRes)
        }.resume()
    }

    // MARK: - Update Checker

    /// Creates the update checker and starts periodic version checks.
    private func setupUpdateChecker() {
        updateChecker = UpdateCheckerService()
        updateChecker?.startPeriodicChecking()
    }

    // MARK: - Notification Observers

    /// Registers all `NotificationCenter` observers for settings and system events.
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

    /// Defaults tracking to enabled on first launch, then starts or stops the monitor.
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

    private func isTrackingEnabled() -> Bool {
        UserDefaults.standard.bool(forKey: AppConstants.UserDefaults.trackingEnabled)
    }

    // MARK: - Onboarding Window

    /// Shows the first-launch onboarding wizard, or brings it forward if already visible.
    func showOnboarding() {
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

        NSApp.setActivationPolicy(.regular)

        onboardingWindow = window
        window.center()
        showWindow(onboardingWindow)
    }

    /// Dismisses the onboarding window on the next run loop to avoid deallocation during close.
    private func dismissOnboarding() {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }

            let window = self.onboardingWindow
            self.onboardingWindow = nil
            window?.orderOut(nil)

            Task { [weak self] in
                await self?.validateTwitchTokenOnBoot()
            }

            self.applyInitialDockVisibility()

            Log.info("Onboarding dismissed, transitioning to normal app state", category: "Onboarding")
        }
    }

    // MARK: - NSWindowDelegate

    /// Marks onboarding as completed when the window is closed via the title bar.
    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow,
              window === onboardingWindow else { return }

        UserDefaults.standard.set(true, forKey: AppConstants.UserDefaults.hasCompletedOnboarding)

        DispatchQueue.main.async { [weak self] in
            self?.onboardingWindow = nil
            self?.applyInitialDockVisibility()
        }
    }

    // MARK: - Settings Window

    /// Creates the Settings window with a transparent title bar and sidebar toolbar.
    private func createSettingsWindow() -> NSWindow {
        let hosting = NSHostingController(rootView: SettingsView())
        let frame = CGRect(x: 0, y: 0, width: AppConstants.UI.settingsWidth, height: AppConstants.UI.settingsHeight)
        let style: NSWindow.StyleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
        let window = NSWindow(contentRect: frame, styleMask: style, backing: .buffered, defer: false)
        window.contentViewController = hosting
        
        window.title = ""
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true

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
        return nil
    }
}

// MARK: - Twitch Token Validation

extension AppDelegate {
    @MainActor
    private func setReauthNeeded(_ needed: Bool) {
        UserDefaults.standard.set(needed, forKey: AppConstants.UserDefaults.twitchReauthNeeded)
    }

    /// Sends a local notification about Twitch authentication status.
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

    /// Opens Settings and navigates to the Twitch section.
    private func openSettingsToTwitch() {
        UserDefaults.standard.set(AppConstants.Twitch.settingsSection, forKey: AppConstants.UserDefaults.selectedSettingsSection)
        openSettings()
    }

    /// Validates the stored Twitch token on launch; prompts for re-auth if expired.
    fileprivate func validateTwitchTokenOnBoot() async {
        guard let token = KeychainService.loadTwitchToken(), !token.isEmpty else {
            await MainActor.run { setReauthNeeded(false) }
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

extension AppDelegate {
    /// Shows a notification if a new version is available.
    @objc func handleUpdateStateChanged(_ notification: Notification) {
        guard let isAvailable = notification.userInfo?["isUpdateAvailable"] as? Bool,
              let version = notification.userInfo?["latestVersion"] as? String,
              isAvailable else { return }

        showUpdateNotification(version: version, installMethod: updateChecker?.detectInstallMethod() ?? .dmg)
    }

    /// Sends a local notification for the given version unless the user has skipped it.
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

extension AppDelegate: MusicPlaybackMonitorDelegate {
    /// Updates track history, broadcasts to all services, and fetches artwork.
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

        websocketServer?.updateNowPlaying(
            track: track,
            artist: artist,
            album: album,
            duration: duration,
            elapsed: elapsed
        )

        fetchArtworkForWidget(track: track, artist: artist)

        discordService?.updatePresence(
            track: track,
            artist: artist,
            album: album,
            duration: duration,
            elapsed: elapsed
        )
    }

    /// Clears track state and notifies services when playback stops.
    func musicPlaybackMonitor(_ monitor: MusicPlaybackMonitor, didUpdateStatus status: String) {
        if status == "No track playing" {
            currentSong = nil
            currentArtist = nil
            currentAlbum = nil
        }

        postNowPlayingUpdate(song: nil, artist: nil, album: nil)

        if currentSong == nil {
            discordService?.clearPresence()
            websocketServer?.clearNowPlaying()
        }
    }
}


