//
//  AppDelegate+MenuBar.swift
//  wolfwave
//
//  Created by MrDemonWolf, Inc. on 4/2/26.
//

import AppKit

// MARK: - Status Bar Setup

extension AppDelegate {

    /// Creates the menu bar status item with the tray icon.
    func setupStatusItem() {
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

    /// Builds and attaches the status bar dropdown menu with dynamic rebuilding.
    func setupMenu() {
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

        if let artist {
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
        if let artist {
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
            container.widthAnchor.constraint(equalToConstant: maxTextWidth + horizontalPadding * 2),
        ])

        container.layout()
        let fittingSize = container.fittingSize
        container.frame = NSRect(origin: .zero, size: fittingSize)

        let item = NSMenuItem()
        item.view = container
        item.isEnabled = false
        return item
    }
}

// MARK: - NSMenuDelegate

extension AppDelegate: NSMenuDelegate {

    /// Rebuilds the menu each time it opens so items reflect live state.
    public func menuNeedsUpdate(_ menu: NSMenu) {
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
}

// MARK: - Menu Toggle Actions

extension AppDelegate {

    @objc func toggleTracking() {
        toggleBoolSetting(
            key: AppConstants.UserDefaults.trackingEnabled,
            notification: AppConstants.Notifications.trackingSettingChanged
        )
    }

    @objc func toggleTwitchConnection() {
        if twitchService?.isConnected ?? false {
            twitchService?.leaveChannel()
        } else {
            // Connecting requires channel + credentials — open Twitch settings
            UserDefaults.standard.set(AppConstants.Twitch.settingsSection, forKey: AppConstants.UserDefaults.selectedSettingsSection)
            openSettings()
        }
    }

    @objc func toggleDiscordPresence() {
        toggleBoolSetting(
            key: AppConstants.UserDefaults.discordPresenceEnabled,
            notification: AppConstants.Notifications.discordPresenceChanged
        )
    }

    @objc func toggleWebSocket() {
        let current = UserDefaults.standard.bool(forKey: AppConstants.UserDefaults.websocketEnabled)
        let newValue = !current
        UserDefaults.standard.set(newValue, forKey: AppConstants.UserDefaults.websocketEnabled)
        // Keep widgetHTTPEnabled in sync with the tray toggle
        UserDefaults.standard.set(newValue, forKey: AppConstants.UserDefaults.widgetHTTPEnabled)
        NotificationCenter.default.post(
            name: NSNotification.Name(AppConstants.Notifications.websocketServerChanged),
            object: nil,
            userInfo: ["enabled": newValue, "widgetHTTPEnabled": newValue]
        )
        websocketServer?.setWidgetHTTPEnabled(newValue)
    }

    /// Toggles a boolean UserDefaults setting and posts a notification.
    func toggleBoolSetting(key: String, notification: String, includeEnabledInUserInfo: Bool = true) {
        let current = UserDefaults.standard.bool(forKey: key)
        let newValue = !current
        UserDefaults.standard.set(newValue, forKey: key)
        NotificationCenter.default.post(
            name: NSNotification.Name(notification),
            object: nil,
            userInfo: includeEnabledInUserInfo ? ["enabled": newValue] : nil
        )
    }

    @objc func copyWidgetURL() {
        let storedWidgetPort = UserDefaults.standard.integer(forKey: AppConstants.UserDefaults.widgetPort)
        let port = storedWidgetPort > 0
            ? UInt16(clamping: storedWidgetPort)
            : AppConstants.WebSocketServer.widgetDefaultPort
        let url = "http://localhost:\(port)"
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(url, forType: .string)
        Log.debug("AppDelegate: Widget URL copied to clipboard: \(url)", category: "App")
    }
}
