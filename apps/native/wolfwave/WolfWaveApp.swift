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
class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate, NSMenuDelegate {
    static weak var shared: AppDelegate?

    // MARK: - Properties

    var statusItem: NSStatusItem?
    var musicMonitor: MusicPlaybackMonitor?
    var settingsWindow: NSWindow?
    var onboardingWindow: NSWindow?
    var twitchService: TwitchChatService?
    var discordService: DiscordRPCService?
    var sparkleUpdater: SparkleUpdaterService?
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
        setupSparkleUpdater()
        setupPowerStateMonitor()
        setupNotificationObservers()
        initializeTrackingState()

        Log.debug("AppDelegate: hasCompletedOnboarding = \(OnboardingViewModel.hasCompletedOnboarding)", category: "App")

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

    // MARK: - Menu Actions

    /// Opens or brings the Settings window to the front.
    @objc func openSettings() {
        statusItem?.menu?.cancelTracking()
        
        if currentDockVisibilityMode == AppConstants.DockVisibility.menuOnly {
            NSApp.setActivationPolicy(.regular)
        }

        if let window = settingsWindow {
            if window.isVisible {
                // Window is already visible — just bring it forward
                window.level = .normal
                window.makeKeyAndOrderFront(nil)
                NSApp.activate(ignoringOtherApps: true)
            } else if window.isMiniaturized {
                // Window is miniaturized — restore it
                window.deminiaturize(nil)
                window.makeKeyAndOrderFront(nil)
                NSApp.activate(ignoringOtherApps: true)
            } else {
                // Window exists but is closing or in weird state — wait for it to fully close
                // The windowWillClose delegate will nil out settingsWindow when ready
                Log.debug("AppDelegate: Settings window exists but is not visible - waiting for close to complete", category: "App")
            }
        } else {
            // No window exists — create and show a new one
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
        let tosLink = NSMutableAttributedString(string: "Terms", attributes: linkAttributes)
        tosLink.addAttribute(.link, value: AppConstants.URLs.termsOfService, range: NSRange(location: 0, length: tosLink.length))
        credits.append(tosLink)

        // Trademark disclaimer
        credits.append(NSAttributedString(string: "\n\n", attributes: baseAttributes))
        credits.append(NSAttributedString(
            string: "Twitch, Discord, OBS, and Apple Music are trademarks of their respective owners. WolfWave is not affiliated with or endorsed by any of them.",
            attributes: baseAttributes
        ))

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
            guard window.isVisible, window.canBecomeKey, window.level == .normal else { return false }
            // Exclude the system About panel — it is owned by AppKit and closes asynchronously
            guard window.className != "NSAboutPanel" else { return false }
            return true
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
            return "🐺 Please open Apple Music"
        }
        
        guard let song = currentSong, let artist = currentArtist else {
            return "🐺 No music playing"
        }
        return "🐺 Playing: \(song) by \(artist)"
    }

    /// Returns a formatted string with the previously played track for Twitch bot commands.
    func getLastSongInfo() -> String {
        guard isMusicAppOpen() else {
            return "🐺 Please open Apple Music"
        }
        
        guard let song = lastSong, let artist = lastArtist else {
            return "🐺 No previous tracks yet, keep the music flowing!"
        }	
        return "🐺 Previous: \(song) by \(artist)"
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

    /// Builds and attaches the status bar dropdown menu with dynamic rebuilding.
    private func setupMenu() {
        let menu = NSMenu()
        menu.delegate = self
        statusItem?.menu = menu
    }

    /// Returns a 16×16 image from the asset catalog for use in menu items.
    private func menuItemIcon(named name: String) -> NSImage? {
        guard let image = NSImage(named: name) else { return nil }
        image.size = NSSize(width: 16, height: 16)
        return image
    }

    /// Creates a now-playing menu item with a fixed-width, word-wrapping layout.
    private func makeNowPlayingMenuItem(song: String, artist: String?) -> NSMenuItem {
        let maxTextWidth: CGFloat = 256
        let horizontalPadding: CGFloat = 12
        let verticalPadding: CGFloat = 8

        let songLabel = NSTextField(wrappingLabelWithString: song)
        songLabel.font = NSFont.boldSystemFont(ofSize: 13)
        songLabel.textColor = .labelColor
        songLabel.preferredMaxLayoutWidth = maxTextWidth
        songLabel.translatesAutoresizingMaskIntoConstraints = false

        let stack = NSStackView(views: [songLabel])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 2

        songLabel.setAccessibilityElement(false)

        if let artist = artist {
            let artistLabel = NSTextField(wrappingLabelWithString: "by \(artist)")
            artistLabel.font = NSFont.systemFont(ofSize: 12)
            artistLabel.textColor = .secondaryLabelColor
            artistLabel.preferredMaxLayoutWidth = maxTextWidth
            artistLabel.translatesAutoresizingMaskIntoConstraints = false
            artistLabel.setAccessibilityElement(false)
            stack.addArrangedSubview(artistLabel)
        }

        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false
        container.setAccessibilityElement(true)
        container.setAccessibilityRole(.staticText)
        if let artist = artist {
            container.setAccessibilityLabel("Now playing: \(song) by \(artist)")
        } else {
            container.setAccessibilityLabel("Now playing: \(song)")
        }
        stack.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: horizontalPadding),
            stack.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -horizontalPadding),
            stack.topAnchor.constraint(equalTo: container.topAnchor, constant: verticalPadding),
            stack.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -verticalPadding),
            container.widthAnchor.constraint(equalToConstant: maxTextWidth + horizontalPadding * 2)
        ])

        container.layoutSubtreeIfNeeded()
        let fittingSize = container.fittingSize
        container.frame = NSRect(origin: .zero, size: fittingSize)

        let item = NSMenuItem()
        item.view = container
        item.isEnabled = false
        return item
    }

    // MARK: - NSMenuDelegate

    /// Rebuilds the menu each time it opens so items reflect live state.
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        // Now Playing section
        if let song = currentSong {
            let nowPlayingItem = makeNowPlayingMenuItem(song: song, artist: currentArtist)
            menu.addItem(nowPlayingItem)
            menu.addItem(.separator())
        }

        // Quick Toggles
        let trackingItem = NSMenuItem(
            title: "Music Sync",
            action: #selector(toggleTracking),
            keyEquivalent: ""
        )
        trackingItem.state = UserDefaults.standard.bool(forKey: AppConstants.UserDefaults.trackingEnabled) ? .on : .off
        trackingItem.image = menuItemIcon(named: "AppleMusicLogo")
        menu.addItem(trackingItem)

        // Twitch toggle — only show if credentials are saved
        if KeychainService.loadTwitchToken() != nil {
            let twitchItem = NSMenuItem(
                title: "Twitch Chat",
                action: #selector(toggleTwitchConnection),
                keyEquivalent: ""
            )
            twitchItem.state = (twitchService?.isConnected ?? false) ? .on : .off
            twitchItem.image = menuItemIcon(named: "TwitchLogo")
            menu.addItem(twitchItem)
        }

        let discordItem = NSMenuItem(
            title: "Discord Status",
            action: #selector(toggleDiscordPresence),
            keyEquivalent: ""
        )
        discordItem.state = UserDefaults.standard.bool(forKey: AppConstants.UserDefaults.discordPresenceEnabled) ? .on : .off
        discordItem.image = menuItemIcon(named: "DiscordLogo")
        menu.addItem(discordItem)

        let overlayItem = NSMenuItem(
            title: "Now-Playing Widget",
            action: #selector(toggleWebSocket),
            keyEquivalent: ""
        )
        overlayItem.state = UserDefaults.standard.bool(forKey: AppConstants.UserDefaults.websocketEnabled) ? .on : .off
        overlayItem.image = menuItemIcon(named: "OBSLogo")
        menu.addItem(overlayItem)

        menu.addItem(.separator())

        // Copy Widget URL — only if websocket enabled
        if UserDefaults.standard.bool(forKey: AppConstants.UserDefaults.websocketEnabled) {
            let copyItem = NSMenuItem(
                title: "Copy Widget Link",
                action: #selector(copyWidgetURL),
                keyEquivalent: ""
            )
            copyItem.image = NSImage(
                systemSymbolName: "link",
                accessibilityDescription: "Copy Widget Link"
            )
            menu.addItem(copyItem)
            menu.addItem(.separator())
        }

        // Standard items
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

        menu.addItem(.separator())

        let quitItem = NSMenuItem(
            title: AppConstants.MenuLabels.quit,
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        quitItem.image = NSImage(
            systemSymbolName: "power",
            accessibilityDescription: "Quit"
        )
        menu.addItem(quitItem)
    }

    // MARK: - Menu Toggle Actions

    @objc private func toggleTracking() {
        toggleBoolSetting(
            key: AppConstants.UserDefaults.trackingEnabled,
            notification: AppConstants.Notifications.trackingSettingChanged
        )
    }

    @objc private func toggleTwitchConnection() {
        if twitchService?.isConnected ?? false {
            twitchService?.leaveChannel()
        } else {
            // Connecting requires channel + credentials — open Twitch settings
            UserDefaults.standard.set(AppConstants.Twitch.settingsSection, forKey: AppConstants.UserDefaults.selectedSettingsSection)
            openSettings()
        }
    }

    @objc private func toggleDiscordPresence() {
        toggleBoolSetting(
            key: AppConstants.UserDefaults.discordPresenceEnabled,
            notification: AppConstants.Notifications.discordPresenceChanged
        )
    }

    @objc private func toggleWebSocket() {
        toggleBoolSetting(
            key: AppConstants.UserDefaults.websocketEnabled,
            notification: AppConstants.Notifications.websocketServerChanged,
            includeEnabledInUserInfo: false
        )

        // Keep widgetHTTPEnabled in sync with the tray toggle
        let newValue = UserDefaults.standard.bool(forKey: AppConstants.UserDefaults.websocketEnabled)
        UserDefaults.standard.set(newValue, forKey: AppConstants.UserDefaults.widgetHTTPEnabled)
        NotificationCenter.default.post(
            name: NSNotification.Name(AppConstants.Notifications.websocketServerChanged),
            object: nil,
            userInfo: ["widgetHTTPEnabled": newValue]
        )
        websocketServer?.setWidgetHTTPEnabled(newValue)
    }

    /// Toggles a boolean UserDefaults setting and posts a notification.
    private func toggleBoolSetting(key: String, notification: String, includeEnabledInUserInfo: Bool = true) {
        let current = UserDefaults.standard.bool(forKey: key)
        let newValue = !current
        UserDefaults.standard.set(newValue, forKey: key)
        NotificationCenter.default.post(
            name: NSNotification.Name(notification),
            object: nil,
            userInfo: includeEnabledInUserInfo ? ["enabled": newValue] : nil
        )
    }

    @objc private func copyWidgetURL() {
        let storedWidgetPort = UserDefaults.standard.integer(forKey: AppConstants.UserDefaults.widgetPort)
        let port = storedWidgetPort > 0
            ? UInt16(clamping: storedWidgetPort)
            : AppConstants.WebSocketServer.widgetDefaultPort
        let url = "http://localhost:\(port)"
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(url, forType: .string)
        Log.debug("AppDelegate: Widget URL copied to clipboard: \(url)", category: "App")
    }

    // MARK: - Power State

    /// Initializes the power state monitor and registers for power state change notifications.
    private func setupPowerStateMonitor() {
        _ = PowerStateMonitor.shared

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(powerStateChanged),
            name: NSNotification.Name(AppConstants.Notifications.powerStateChanged),
            object: nil
        )
    }

    /// Adjusts service polling intervals when system power state changes.
    @objc func powerStateChanged(_ notification: Notification) {
        let reduced = PowerStateMonitor.shared.isReducedMode

        musicMonitor?.updateCheckInterval(
            reduced ? AppConstants.PowerManagement.reducedMusicCheckInterval : 5.0
        )
        discordService?.updatePollInterval(
            reduced ? AppConstants.PowerManagement.reducedDiscordPollInterval
                    : AppConstants.Discord.availabilityPollInterval
        )
        websocketServer?.updateProgressInterval(
            reduced ? AppConstants.PowerManagement.reducedProgressBroadcastInterval
                    : AppConstants.WebSocketServer.progressBroadcastInterval
        )

        Log.debug("AppDelegate: Power state changed: reduced=\(reduced)", category: "App")
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
            if Thread.isMainThread {
                return self?.getCurrentSongInfo() ?? "Nothing playing right now"
            }
            var result = "Nothing playing right now"
            DispatchQueue.main.sync {
                result = self?.getCurrentSongInfo() ?? "Nothing playing right now"
            }
            return result
        }
        twitchService?.getLastSongInfo = { [weak self] in
            if Thread.isMainThread {
                return self?.getLastSongInfo() ?? "No previous track yet"
            }
            var result = "No previous track yet"
            DispatchQueue.main.sync {
                result = self?.getLastSongInfo() ?? "No previous track yet"
            }
            return result
        }
    }

    // MARK: - Discord Service

    /// Creates the Discord RPC service, registers state callbacks, and enables if configured.
    private func setupDiscordService() {
        discordService = DiscordRPCService()

        if DiscordRPCService.resolveClientID() != nil {
            Log.debug("AppDelegate: Resolved Discord Client ID from Info.plist", category: "Discord")
        } else {
            Log.info("AppDelegate: No Discord Client ID found. Set DISCORD_CLIENT_ID in Config.xcconfig to enable Discord Status.", category: "Discord")
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
            Log.debug("AppDelegate: WebSocket state changed to \(newState.rawValue) (\(clientCount) clients)", category: "WebSocket")
        }

        let enabled = UserDefaults.standard.bool(forKey: AppConstants.UserDefaults.websocketEnabled)
        if enabled {
            websocketServer?.setEnabled(true)
        }
    }

    /// Toggles the WebSocket server and applies any port change from the notification.
    @objc func websocketServerSettingChanged(_ notification: Notification) {
        let enabled = notification.userInfo?["enabled"] as? Bool
            ?? UserDefaults.standard.bool(forKey: AppConstants.UserDefaults.websocketEnabled)
        websocketServer?.setEnabled(enabled)

        if let port = notification.userInfo?["port"] as? UInt16 {
            websocketServer?.updatePort(port)
        }
    }

    /// Toggles the widget HTTP server independently from the WebSocket server.
    @objc func widgetHTTPServerSettingChanged(_ notification: Notification) {
        let enabled = notification.userInfo?["enabled"] as? Bool
            ?? UserDefaults.standard.object(forKey: AppConstants.UserDefaults.widgetHTTPEnabled) as? Bool ?? false
        websocketServer?.setWidgetHTTPEnabled(enabled)
    }

    // MARK: - Widget Artwork

    /// Fetches album artwork via the shared ArtworkService and forwards it to the WebSocket server.
    private func fetchArtworkForWidget(track: String, artist: String) {
        ArtworkService.shared.fetchArtworkURL(track: track, artist: artist) { [weak self] url in
            guard let url else { return }
            self?.websocketServer?.updateArtworkURL(url)
        }
    }

    // MARK: - Sparkle Updater

    /// Creates the Sparkle updater and starts automatic update checking.
    ///
    /// Sparkle handles all aspects of the update process:
    /// - Checking for updates on a schedule
    /// - Downloading and verifying packages
    /// - Installing updates with user confirmation
    /// - Code signature verification
    ///
    /// Note: Sparkle is automatically disabled for Homebrew installations.
    private func setupSparkleUpdater() {
        sparkleUpdater = SparkleUpdaterService()
        Log.info("AppDelegate: Sparkle updater initialized", category: "Update")
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
            forName: NSWindow.willCloseNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self,
                  let window = notification.object as? NSWindow,
                  window !== self.settingsWindow,
                  window !== self.onboardingWindow else { return }
            // Defer slightly so the window is fully off-screen before we check
            DispatchQueue.main.async { [weak self] in
                self?.restoreMenuOnlyIfNeeded()
            }
        }

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
            selector: #selector(widgetHTTPServerSettingChanged),
            name: NSNotification.Name(AppConstants.Notifications.widgetHTTPServerChanged),
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
        hosting.view.translatesAutoresizingMaskIntoConstraints = false
        if let contentView = window.contentView {
            NSLayoutConstraint.activate([
                hosting.view.topAnchor.constraint(equalTo: contentView.topAnchor),
                hosting.view.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
                hosting.view.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
                hosting.view.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            ])
        }
        window.title = "Welcome to WolfWave"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.delegate = self
        window.isReleasedWhenClosed = false
        window.collectionBehavior = [.moveToActiveSpace]

        NSApp.setActivationPolicy(.regular)

        onboardingWindow = window

        if let screen = NSScreen.main {
            let screenFrame = screen.visibleFrame
            let x = screenFrame.midX - frame.width / 2
            let y = screenFrame.midY - frame.height / 2
            window.setFrameOrigin(NSPoint(x: x, y: y))
        } else {
            window.center()
        }

        window.alphaValue = 0
        showWindow(onboardingWindow)

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.3
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            window.animator().alphaValue = 1
        }
    }

    /// Dismisses the onboarding window with a fade-out animation.
    private func dismissOnboarding() {
        DispatchQueue.main.async { [weak self] in
            guard let self, let window = self.onboardingWindow else { return }

            NSAnimationContext.runAnimationGroup({ context in
                context.duration = 0.3
                context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                window.animator().alphaValue = 0
            }, completionHandler: { [weak self] in
                window.close()

                Task { [weak self] in
                    await self?.validateTwitchTokenOnBoot()
                }

                Log.info("AppDelegate: Onboarding dismissed, transitioning to normal app state", category: "App")
            })
        }
    }

    // MARK: - NSWindowDelegate

    /// Handles cleanup when any owned window closes (onboarding or settings).
    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }

        if window === onboardingWindow {
            // Only mark onboarding as completed if the user actually finished all steps.
            // Closing via the title-bar X button should not permanently skip setup.
            if OnboardingViewModel.hasCompletedOnboarding == false {
                Log.info("AppDelegate: Onboarding window closed before completion — will show again on next launch", category: "App")
            }
            // Defer niling and dock restoration to let AppKit finish the close animation
            // so that isVisible returns false before hasVisibleWindows is checked.
            DispatchQueue.main.async { [weak self] in
                self?.onboardingWindow = nil
                self?.restoreMenuOnlyIfNeeded()
            }
        } else if window === settingsWindow {
            // Defer niling and dock restoration to let AppKit finish the close animation
            // so that isVisible returns false before hasVisibleWindows is checked.
            DispatchQueue.main.async { [weak self] in
                self?.settingsWindow = nil
                self?.restoreMenuOnlyIfNeeded()
            }
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
        hosting.view.translatesAutoresizingMaskIntoConstraints = false
        if let contentView = window.contentView {
            NSLayoutConstraint.activate([
                hosting.view.topAnchor.constraint(equalTo: contentView.topAnchor),
                hosting.view.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
                hosting.view.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
                hosting.view.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            ])
        }

        window.title = ""
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true

        window.collectionBehavior = [.moveToActiveSpace]
        window.canHide = true
        window.isReleasedWhenClosed = false
        window.delegate = self

        window.center()
        return window
    }

    private func showWindow(_ window: NSWindow?) {
        window?.level = .normal
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
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
                                "AppDelegate: Failed to send notification: \(error.localizedDescription)",
                                category: "App"
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
                    message: "Your Twitch session has expired. Please re-authorize in Settings."
                )
                openSettingsToTwitch()
            }
        }
    }
}

// MARK: - Update Notifications

extension AppDelegate {
    /// Shows a notification if a new version is available.
    ///
    /// Note: With Sparkle, this is handled automatically by the framework.
    /// This method is kept for compatibility but may not be needed.
    @objc func handleUpdateStateChanged(_ notification: Notification) {
        guard let isAvailable = notification.userInfo?["isUpdateAvailable"] as? Bool,
              let version = notification.userInfo?["latestVersion"] as? String,
              isAvailable else { return }

        // Sparkle handles notifications, but we log for debugging
        Log.info("AppDelegate: Update available notification received — v\(version)", category: "Update")
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


