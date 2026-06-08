//
//  AppDelegate+MenuBar.swift
//  WolfWave
//
//  Created by Nathanial Henniges on 2026-04-03.
//  Copyright © 2026 MrDemonWolf, Inc. All rights reserved.
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

    /// Returns a 16×16 template image from the asset catalog for use in menu items.
    /// Template rendering tints the icon with the menu text color so brand
    /// silhouettes match the surrounding SF Symbol items.
    private func menuItemIcon(named name: String) -> NSImage? {
        guard let image = NSImage(named: name) else { return nil }
        image.size = NSSize(width: 16, height: 16)
        image.isTemplate = true
        return image
    }

    /// Creates a now-playing menu item with album art (when available),
    /// song title, and artist line in a fixed-width, word-wrapping layout.
    fileprivate func makeNowPlayingMenuItem(
        song: String,
        artist: String?,
        artwork: NSImage?
    ) -> NSMenuItem {
        let maxTextWidth: CGFloat = 232
        let horizontalPadding: CGFloat = 12
        let verticalPadding: CGFloat = 8
        let artSize: CGFloat = 36
        let artTextSpacing: CGFloat = 10

        let songLabel = NSTextField(wrappingLabelWithString: song)
        songLabel.font = NSFont.boldSystemFont(ofSize: 13)
        songLabel.textColor = .labelColor
        songLabel.preferredMaxLayoutWidth = maxTextWidth
        songLabel.translatesAutoresizingMaskIntoConstraints = false
        songLabel.setAccessibilityElement(false)

        let textStack = NSStackView(views: [songLabel])
        textStack.orientation = .vertical
        textStack.alignment = .leading
        textStack.spacing = 2

        if let artist {
            let artistLabel = NSTextField(wrappingLabelWithString: "by \(artist)")
            artistLabel.font = NSFont.systemFont(ofSize: 12)
            artistLabel.textColor = .secondaryLabelColor
            artistLabel.preferredMaxLayoutWidth = maxTextWidth
            artistLabel.translatesAutoresizingMaskIntoConstraints = false
            artistLabel.setAccessibilityElement(false)
            textStack.addArrangedSubview(artistLabel)
        }
        textStack.translatesAutoresizingMaskIntoConstraints = false

        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false
        container.setAccessibilityElement(true)
        container.setAccessibilityRole(.staticText)
        if let artist {
            container.setAccessibilityLabel("Now playing: \(song) by \(artist)")
        } else {
            container.setAccessibilityLabel("Now playing: \(song)")
        }

        var leadingForText: NSLayoutXAxisAnchor = container.leadingAnchor
        var leadingTextConstant: CGFloat = horizontalPadding

        if let artwork {
            let artView = NSImageView()
            artView.image = artwork
            artView.imageScaling = .scaleProportionallyUpOrDown
            artView.wantsLayer = true
            artView.layer?.cornerRadius = 4
            artView.layer?.masksToBounds = true
            artView.translatesAutoresizingMaskIntoConstraints = false
            container.addSubview(artView)
            NSLayoutConstraint.activate([
                artView.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: horizontalPadding),
                artView.centerYAnchor.constraint(equalTo: container.centerYAnchor),
                artView.widthAnchor.constraint(equalToConstant: artSize),
                artView.heightAnchor.constraint(equalToConstant: artSize),
            ])
            leadingForText = artView.trailingAnchor
            leadingTextConstant = artTextSpacing
        }

        container.addSubview(textStack)

        let totalWidth = (artwork != nil ? artSize + artTextSpacing : 0) + maxTextWidth + horizontalPadding * 2
        NSLayoutConstraint.activate([
            textStack.leadingAnchor.constraint(equalTo: leadingForText, constant: leadingTextConstant),
            textStack.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -horizontalPadding),
            textStack.topAnchor.constraint(equalTo: container.topAnchor, constant: verticalPadding),
            textStack.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -verticalPadding),
            container.widthAnchor.constraint(equalToConstant: totalWidth),
        ])

        // Read `fittingSize` to size the menu item from its constraints. Do NOT
        // call `container.layout()` here: this runs inside `menuNeedsUpdate`
        // while a layout pass is already in flight, and a manual `layout()`
        // (which forces `layoutSubtreeIfNeeded`) trips `_NSDetectedLayoutRecursion`
        // ("not legal to call -layoutSubtreeIfNeeded on a view already being laid
        // out"). `fittingSize` solves Auto Layout on its own without recursing.
        let fittingSize = container.fittingSize
        container.frame = NSRect(origin: .zero, size: fittingSize)

        let item = NSMenuItem()
        item.view = container
        item.isEnabled = false
        return item
    }

    /// Builds the "Copy Song Link" menu item. Shows a `song.link` multi-platform
    /// URL when resolved; falls back to the Apple Music track URL while the
    /// song.link sentinel is still warming. When no URL is cached the row is
    /// disabled with a trailing hint: "Resolving…" while a lookup is still
    /// pending, or "No link found" once a lookup has finished without a match
    /// (so the row stays put rather than lying "Resolving…" for the lookup TTL).
    ///
    /// On a cache miss the menu drives resolution itself (mirroring
    /// `currentAlbumArtwork()`), so a track whose links were never fetched. or
    /// were lost to a launch/relaunch race. resolves on the next menu open,
    /// independent of play/pause state.
    ///
    /// Mirrors the same `ArtworkService.cachedTrackLinks` source the Discord
    /// RPC button row uses, so what the streamer pastes matches what their
    /// audience sees.
    fileprivate func makeCopySongLinkItem(song: String, artist: String?) -> NSMenuItem {
        let item = NSMenuItem(
            title: "Copy Song Link",
            action: #selector(copySongLink),
            keyEquivalent: ""
        )
        item.image = NSImage(
            systemSymbolName: "link",
            accessibilityDescription: "Copy Song Link"
        )

        let links = artist.map { ArtworkService.shared.cachedTrackLinks(track: song, artist: $0) }
        let hasLink = (links?.songLinkURL != nil) || (links?.trackViewURL != nil)
        if hasLink { return item }

        // No URL cached. Decide between "Resolving…" and "No link found", and
        // drive a lookup ourselves on the first miss so it resolves on the next
        // menu open whether Music is playing or paused.
        let attempted: Bool
        if let artist {
            attempted = ArtworkService.shared.hasAttemptedTrackLinks(track: song, artist: artist)
            if !attempted {
                ArtworkService.shared.fetchTrackLinks(track: song, artist: artist) { _ in }
            }
        } else {
            attempted = true // No artist to search on: nothing will resolve.
        }

        item.isEnabled = false
        let attributed = NSMutableAttributedString(
            string: "Copy Song Link",
            attributes: [
                .font: NSFont.menuFont(ofSize: 0),
                .foregroundColor: NSColor.labelColor,
            ]
        )
        attributed.append(NSAttributedString(
            string: attempted ? "  No link found" : "  Resolving\u{2026}",
            attributes: [
                .font: NSFont.menuFont(ofSize: NSFont.systemFontSize(for: .small)),
                .foregroundColor: NSColor.secondaryLabelColor,
            ]
        ))
        item.attributedTitle = attributed
        return item
    }

    /// Returns a tray menu item with a primary title and a dimmed trailing
    /// status string, e.g. `"Twitch Chat"` + `"@nathanial"`.
    fileprivate func makeStatusItem(
        title: String,
        status: String,
        action: Selector,
        on: Bool,
        image: NSImage?
    ) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.state = on ? .on : .off
        item.image = image
        let attributed = NSMutableAttributedString(
            string: title,
            attributes: [
                .font: NSFont.menuFont(ofSize: 0),
                .foregroundColor: NSColor.labelColor,
            ]
        )
        attributed.append(NSAttributedString(
            string: "  " + status,
            attributes: [
                .font: NSFont.menuFont(ofSize: NSFont.systemFontSize(for: .small)),
                .foregroundColor: NSColor.secondaryLabelColor,
            ]
        ))
        item.attributedTitle = attributed
        return item
    }
}

// MARK: - Album-Art Cache

extension AppDelegate {

    /// Returns the cached album art for the current song if one has been
    /// fetched. On cache miss, kicks off a background fetch via
    /// `ArtworkService` and stores the decoded image. The next menu open
    /// will pick it up. Never blocks the menu.
    fileprivate func currentAlbumArtwork() -> NSImage? {
        guard let song = currentSong, let artist = currentArtist else { return nil }
        let key = "\(artist)|\(song)"

        if let cached = albumArtCache.object(forKey: key as NSString) { return cached }

        // No image yet, request the URL (cached) and asynchronously fetch
        // bitmap data. Bail when nothing is known yet; ArtworkService will
        // have populated its URL cache by the time the next menu opens.
        guard let urlString = ArtworkService.shared.cachedArtworkURL(track: song, artist: artist),
              let url = URL(string: urlString) else {
            return nil
        }

        Task { [weak self] in
            guard let data = try? await HTTPClient.shared.data(url: url),
                  let image = NSImage(data: data) else { return }
            await MainActor.run { [weak self] in
                self?.albumArtCache.setObject(image, forKey: key as NSString)
            }
        }

        return nil
    }
}

// MARK: - NSMenuDelegate

extension AppDelegate: NSMenuDelegate {

    /// Rebuilds the menu each time it opens so items reflect live state.
    public func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        buildNowPlayingSection(into: menu)
        buildPlaybackControls(into: menu)
        buildSongRequestSection(into: menu)
        buildServiceToggles(into: menu)
        buildStreamerActions(into: menu)
        buildAppItems(into: menu)
    }

    // MARK: - Now Playing

    private func buildNowPlayingSection(into menu: NSMenu) {
        guard let song = currentSong else { return }

        let nowPlayingItem = makeNowPlayingMenuItem(
            song: song,
            artist: currentArtist,
            artwork: currentAlbumArtwork()
        )
        menu.addItem(nowPlayingItem)

        let copyItem = NSMenuItem(
            title: "Copy Song Info",
            action: #selector(copyCurrentTrack),
            keyEquivalent: ""
        )
        copyItem.image = NSImage(
            systemSymbolName: "doc.on.doc",
            accessibilityDescription: "Copy Song Info"
        )
        menu.addItem(copyItem)

        let linkItem = makeCopySongLinkItem(song: song, artist: currentArtist)
        menu.addItem(linkItem)

        if twitchService?.isConnectedSnapshot.value ?? false {
            let shareItem = NSMenuItem(
                title: "Share to Twitch Chat",
                action: #selector(shareCurrentTrackToTwitch),
                keyEquivalent: ""
            )
            shareItem.image = NSImage(
                systemSymbolName: "bubble.left.and.bubble.right",
                accessibilityDescription: "Share to Twitch Chat"
            )
            menu.addItem(shareItem)
        }

        if !recentTracks.isEmpty {
            let recentParent = NSMenuItem(
                title: "Recently Played",
                action: nil,
                keyEquivalent: ""
            )
            recentParent.image = NSImage(
                systemSymbolName: "clock.arrow.circlepath",
                accessibilityDescription: "Recently Played"
            )
            recentParent.submenu = buildRecentlyPlayedSubmenu()
            menu.addItem(recentParent)
        }

        menu.addItem(.separator())
    }

    private func buildRecentlyPlayedSubmenu() -> NSMenu {
        let submenu = NSMenu()
        for track in recentTracks.entries {
            let item = NSMenuItem(
                title: track.displayLabel,
                action: #selector(copyRecentTrack(_:)),
                keyEquivalent: ""
            )
            item.representedObject = track.displayLabel
            submenu.addItem(item)
        }
        return submenu
    }

    // MARK: - Playback Controls

    private func buildPlaybackControls(into menu: NSMenu) {
        // Only surface playback controls when Music.app is running. The
        // AppleScript commands silently no-op otherwise and a greyed-out
        // section is more confusing than absent.
        let musicRunning = NSWorkspace.shared.runningApplications.contains {
            $0.bundleIdentifier == AppConstants.Music.bundleIdentifier
        }
        guard musicRunning else { return }

        let isPlaying = songRequestService?.musicController.isPlaying ?? false

        let playPauseItem = NSMenuItem(
            title: isPlaying ? "Pause" : "Play",
            action: #selector(playPause),
            keyEquivalent: ""
        )
        playPauseItem.image = NSImage(
            systemSymbolName: isPlaying ? "pause.fill" : "play.fill",
            accessibilityDescription: isPlaying ? "Pause" : "Play"
        )
        menu.addItem(playPauseItem)

        let nextItem = NSMenuItem(
            title: "Next Track",
            action: #selector(nextTrack),
            keyEquivalent: ""
        )
        nextItem.image = NSImage(
            systemSymbolName: "forward.fill",
            accessibilityDescription: "Next Track"
        )
        menu.addItem(nextItem)

        let prevItem = NSMenuItem(
            title: "Previous Track",
            action: #selector(previousTrack),
            keyEquivalent: ""
        )
        prevItem.image = NSImage(
            systemSymbolName: "backward.fill",
            accessibilityDescription: "Previous Track"
        )
        menu.addItem(prevItem)

        menu.addItem(.separator())
    }

    // MARK: - Song Requests

    private func buildSongRequestSection(into menu: NSMenu) {
        guard FeatureFlags.songRequestEnabled,
              let srQueue = songRequestService?.queue else { return }

        let queueCount = srQueue.count
        let nowPlaying = srQueue.nowPlaying
        let hasNowPlaying = nowPlaying != nil
        let holdEnabled = songRequestService?.isHoldEnabled ?? false

        // Hold/Resume is the live-streamer button, always promoted to the
        // top level, even when the rest of the section is collapsed.
        let holdItem = NSMenuItem(
            title: holdEnabled ? "Resume Song Requests" : "Hold Song Requests",
            action: #selector(toggleSongRequestHold),
            keyEquivalent: ""
        )
        holdItem.image = NSImage(
            systemSymbolName: holdEnabled ? "play.circle" : "pause.circle",
            accessibilityDescription: holdEnabled ? "Resume" : "Hold"
        )
        menu.addItem(holdItem)

        let collapse = MenuStatusFormatter.shouldCollapseSongRequests(
            queueCount: queueCount,
            hasNowPlaying: hasNowPlaying
        )

        if collapse {
            let parentTitle = "Song Requests (\(queueCount))"
            let parent = NSMenuItem(title: parentTitle, action: nil, keyEquivalent: "")
            parent.image = NSImage(
                systemSymbolName: "music.note.list",
                accessibilityDescription: "Song Requests"
            )
            parent.submenu = buildSongRequestSubmenu(
                nowPlaying: nowPlaying,
                queueCount: queueCount
            )
            menu.addItem(parent)
        } else {
            if let nowPlaying {
                let requestItem = NSMenuItem(
                    title: "\(nowPlaying.title) · \(nowPlaying.artist)",
                    action: nil,
                    keyEquivalent: ""
                )
                requestItem.isEnabled = false
                menu.addItem(requestItem)
            }
            if queueCount > 0 {
                let queueLabel = NSMenuItem(
                    title: "\(queueCount) song\(queueCount == 1 ? "" : "s") in queue",
                    action: nil,
                    keyEquivalent: ""
                )
                queueLabel.isEnabled = false
                menu.addItem(queueLabel)
            }
            if hasNowPlaying || queueCount > 0 {
                addSongRequestActions(into: menu)
            }
        }

        menu.addItem(.separator())
    }

    private func buildSongRequestSubmenu(
        nowPlaying: SongRequestItem?,
        queueCount: Int
    ) -> NSMenu {
        let submenu = NSMenu()
        if let nowPlaying {
            let nowItem = NSMenuItem(
                title: "Now: \(nowPlaying.title) · \(nowPlaying.artist)",
                action: nil,
                keyEquivalent: ""
            )
            nowItem.isEnabled = false
            submenu.addItem(nowItem)
        }
        if queueCount > 0 {
            let queueLabel = NSMenuItem(
                title: "\(queueCount) song\(queueCount == 1 ? "" : "s") in queue",
                action: nil,
                keyEquivalent: ""
            )
            queueLabel.isEnabled = false
            submenu.addItem(queueLabel)
        }
        submenu.addItem(.separator())
        addSongRequestActions(into: submenu)
        return submenu
    }

    private func addSongRequestActions(into menu: NSMenu) {
        let skipItem = NSMenuItem(
            title: "Skip Song Request",
            action: #selector(skipSongRequest),
            keyEquivalent: ""
        )
        skipItem.image = NSImage(
            systemSymbolName: "forward.fill",
            accessibilityDescription: "Skip"
        )
        menu.addItem(skipItem)

        let clearItem = NSMenuItem(
            title: "Clear Queue",
            action: #selector(clearSongRequestQueue),
            keyEquivalent: ""
        )
        clearItem.image = NSImage(
            systemSymbolName: "trash",
            accessibilityDescription: "Clear Queue"
        )
        menu.addItem(clearItem)
    }

    // MARK: - Service Toggles

    private func buildServiceToggles(into menu: NSMenu) {
        let trackingOn = FeatureFlags.trackingEnabled
        let trackingItem = makeStatusItem(
            title: "Apple Music",
            status: MenuStatusFormatter.musicStatus(trackingEnabled: trackingOn),
            action: #selector(toggleTracking),
            on: trackingOn,
            image: menuItemIcon(named: "AppleMusicLogo")
        )
        menu.addItem(trackingItem)

        if KeychainService.loadTwitchToken() != nil {
            let connected = twitchService?.isConnectedSnapshot.value ?? false
            let rawChannel = Preferences.twitchChannelName
            let channel: String? = rawChannel.isEmpty
                ? nil
                : StreamerMode.mask(rawChannel, style: .channel, isOn: StreamerMode.isEnabled)
            let twitchItem = makeStatusItem(
                title: "Twitch",
                status: MenuStatusFormatter.twitchStatus(isConnected: connected, channelName: channel),
                action: #selector(toggleTwitchConnection),
                on: connected,
                image: menuItemIcon(named: "TwitchLogo")
            )
            menu.addItem(twitchItem)
        }

        let discordEnabled = FeatureFlags.discordEnabled
        let discordState: MenuStatusFormatter.DiscordState = {
            switch discordService?.stateSnapshot {
            case .connected: return .connected
            case .connecting: return .connecting
            case .disconnected, .none: return .disconnected
            }
        }()
        let discordItem = makeStatusItem(
            title: "Discord",
            status: MenuStatusFormatter.discordStatus(enabled: discordEnabled, state: discordState),
            action: #selector(toggleDiscordPresence),
            on: discordEnabled,
            image: menuItemIcon(named: "DiscordLogo")
        )
        menu.addItem(discordItem)

        let widgetsEnabled = FeatureFlags.websocketEnabled
        let widgetPort = resolvedWidgetPort()
        let clientCount = websocketServer?.connectedClientCount ?? 0
        let overlayItem = makeStatusItem(
            title: "OBS Overlay",
            status: MenuStatusFormatter.widgetsStatus(
                enabled: widgetsEnabled,
                widgetPort: widgetPort,
                clientCount: clientCount
            ),
            action: #selector(toggleWebSocket),
            on: widgetsEnabled,
            image: menuItemIcon(named: "OBSLogo")
        )
        menu.addItem(overlayItem)

        menu.addItem(.separator())
    }

    // MARK: - Streamer Quick Actions

    private func buildStreamerActions(into menu: NSMenu) {
        let streamerModeOn = StreamerMode.isEnabled
        let streamerModeItem = NSMenuItem(
            title: "Streamer Mode",
            action: #selector(toggleStreamerMode),
            keyEquivalent: ""
        )
        streamerModeItem.state = streamerModeOn ? .on : .off
        streamerModeItem.image = NSImage(
            systemSymbolName: streamerModeOn ? "eye.slash.fill" : "eye.slash",
            accessibilityDescription: "Streamer Mode"
        )
        streamerModeItem.toolTip = "Hide channel name, overlay URL, and other sensitive details from the WolfWave UI while you're on stream."
        menu.addItem(streamerModeItem)

        let widgetsEnabled = FeatureFlags.websocketEnabled
        if widgetsEnabled {
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

            let openItem = NSMenuItem(
                title: "Open Widget in Browser",
                action: #selector(openWidgetInBrowser),
                keyEquivalent: ""
            )
            openItem.image = NSImage(
                systemSymbolName: "safari",
                accessibilityDescription: "Open Widget in Browser"
            )
            menu.addItem(openItem)
        }

        let reconnectItem = NSMenuItem(
            title: "Restart Integrations",
            action: #selector(reconnectAllServices),
            keyEquivalent: ""
        )
        reconnectItem.image = NSImage(
            systemSymbolName: "arrow.triangle.2.circlepath",
            accessibilityDescription: "Restart Integrations"
        )
        menu.addItem(reconnectItem)

        menu.addItem(.separator())
    }

    // MARK: - App Items (Settings · Help ▸ · About · Quit)

    private func buildAppItems(into menu: NSMenu) {
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

        let helpParent = NSMenuItem(title: "Help", action: nil, keyEquivalent: "")
        helpParent.image = NSImage(
            systemSymbolName: "questionmark.circle",
            accessibilityDescription: "Help"
        )
        helpParent.submenu = buildHelpSubmenu()
        menu.addItem(helpParent)

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

    private func buildHelpSubmenu() -> NSMenu {
        let submenu = NSMenu()

        let whatsNew = NSMenuItem(
            title: "What's New",
            action: #selector(showWhatsNewFromMenu),
            keyEquivalent: ""
        )
        whatsNew.image = NSImage(systemSymbolName: "sparkles", accessibilityDescription: nil)
        submenu.addItem(whatsNew)

        submenu.addItem(.separator())

        let docs = NSMenuItem(
            title: "Documentation",
            action: #selector(openDocs),
            keyEquivalent: ""
        )
        docs.image = NSImage(systemSymbolName: "book", accessibilityDescription: nil)
        submenu.addItem(docs)

        let community = NSMenuItem(
            title: "Community Discord",
            action: #selector(openCommunityDiscord),
            keyEquivalent: ""
        )
        community.image = NSImage(systemSymbolName: "bubble.left.and.bubble.right", accessibilityDescription: nil)
        submenu.addItem(community)

        submenu.addItem(.separator())

        let bug = NSMenuItem(
            title: "Report a Bug",
            action: #selector(reportBug),
            keyEquivalent: ""
        )
        bug.image = NSImage(systemSymbolName: "ant", accessibilityDescription: nil)
        submenu.addItem(bug)

        let github = NSMenuItem(
            title: "Star on GitHub",
            action: #selector(openGitHub),
            keyEquivalent: ""
        )
        github.image = NSImage(systemSymbolName: "star", accessibilityDescription: nil)
        submenu.addItem(github)

        return submenu
    }

    // MARK: - Helpers

    /// Resolves the user-configured widget HTTP port, falling back to the default.
    fileprivate func resolvedWidgetPort() -> UInt16 {
        let stored = Preferences.widgetPort
        return stored > 0
            ? UInt16(clamping: stored)
            : AppConstants.WebSocketServer.widgetDefaultPort
    }
}

// MARK: - Menu Toggle Actions

extension AppDelegate {

    /// Opens the GitHub Sponsors page in the user's default browser.
    @objc func openSponsorPage() {
        ExternalLink.open(AppConstants.URLs.githubSponsors)
    }

    /// Toggles the "Sync Music" preference, mirroring the General settings
    /// pane. Triggered by the menu bar's tracking item.
    @objc func toggleTracking() {
        toggleBoolSetting(
            key: AppConstants.UserDefaults.trackingEnabled,
            notification: AppConstants.Notifications.trackingSettingChanged
        )
    }

    /// Toggles the Twitch chat connection. Connects if credentials are saved
    /// and the bot is idle; opens the Twitch settings pane when credentials
    /// are missing or the channel is unconfigured.
    @objc func toggleTwitchConnection() {
        if twitchService?.isConnectedSnapshot.value ?? false {
            if let service = twitchService {
                Task { await service.leaveChannel() }
            }
        } else {
            // Connecting requires channel + credentials, open Twitch settings
            Preferences.setSelectedSettingsSection(AppConstants.Twitch.settingsSection)
            openSettings()
        }
    }

    /// Toggles Streamer Mode. Masks sensitive values in the WolfWave UI
    /// (channel name, overlay URL, WebSocket URI, etc.) so the app can be
    /// safely shown on stream. UI-only; does not change broadcast payloads.
    @objc func toggleStreamerMode() {
        toggleBoolSetting(
            key: AppConstants.UserDefaults.streamerModeEnabled,
            notification: AppConstants.Notifications.streamerModeChanged
        )
    }

    /// Toggles Discord Rich Presence on/off.
    @objc func toggleDiscordPresence() {
        toggleBoolSetting(
            key: AppConstants.UserDefaults.discordPresenceEnabled,
            notification: AppConstants.Notifications.discordPresenceChanged
        )
    }

    /// Toggles the WebSocket overlay broadcast plus the bundled widget HTTP
    /// server. Both flags are kept in sync from this single tray control.
    @objc func toggleWebSocket() {
        let current = FeatureFlags.websocketEnabled
        let newValue = !current
        Preferences.setWebSocketEnabled(newValue)
        // Keep widgetHTTPEnabled in sync with the tray toggle
        Preferences.setWidgetHTTPEnabled(newValue)
        NotificationCenter.default.postWebSocketServerChanged(
            enabled: newValue,
            widgetHTTPEnabled: newValue
        )
        Task { [weak self] in await self?.websocketServer?.setWidgetHTTPEnabled(newValue) }
    }

    /// Flips a boolean UserDefaults value and broadcasts a notification.
    ///
    /// Helper used by the menu toggle actions to keep persistence and
    /// observers in lockstep.
    ///
    /// - Parameters:
    ///   - key: UserDefaults key holding the current `Bool`.
    ///   - notification: Notification name to post after the flip.
    ///   - includeEnabledInUserInfo: When `true`, attaches
    ///     `["enabled": newValue]` to the posted notification.
    func toggleBoolSetting(key: String, notification: String, includeEnabledInUserInfo: Bool = true) {
        let current = UserDefaults.standard.bool(forKey: key)
        let newValue = !current
        UserDefaults.standard.set(newValue, forKey: key)
        let name = NSNotification.Name(notification)
        if includeEnabledInUserInfo {
            NotificationCenter.default.postEnabled(name, enabled: newValue)
        } else {
            NotificationCenter.default.post(name: name, object: nil)
        }
    }

    /// Toggles song-request auto-play. While held, new requests still queue
    /// but nothing plays automatically.
    @objc func toggleSongRequestHold() {
        guard let service = songRequestService else { return }
        let newValue = !service.isHoldEnabled
        Task { await service.setHold(newValue) }
    }

    /// Skips the currently playing song request, advancing the queue.
    @objc func skipSongRequest() {
        Task {
            _ = await songRequestService?.skip()
        }
    }

    /// Removes every entry from the song-request queue.
    @objc func clearSongRequestQueue() {
        Task {
            _ = await songRequestService?.clearQueue()
        }
    }

    /// Copies the local widget URL (e.g. `http://localhost:8766`) to the
    /// pasteboard for OBS browser-source configuration.
    @objc func copyWidgetURL() {
        let url = "http://localhost:\(resolvedWidgetPort())"
        Pasteboard.copy(url)
        Log.debug("AppDelegate: Widget URL copied to clipboard: \(url)", category: "App")
    }
}

// MARK: - Playback Controls

extension AppDelegate {

    /// Toggles Music.app play/pause without stealing focus.
    @objc func playPause() {
        guard let controller = songRequestService?.musicController else { return }
        Task { try? await controller.playPause() }
    }

    /// Advances Music.app to the next track in its player queue.
    @objc func nextTrack() {
        guard let controller = songRequestService?.musicController else { return }
        Task { try? await controller.skipToNext() }
    }

    /// Rewinds Music.app to the previous track in its player queue.
    @objc func previousTrack() {
        guard let controller = songRequestService?.musicController else { return }
        Task { try? await controller.previousTrack() }
    }
}

// MARK: - Now Playing Actions

extension AppDelegate {

    /// Copies the currently-playing track as `"Title · Artist"`.
    @objc func copyCurrentTrack() {
        guard let song = currentSong else { return }
        let value = currentArtist.map { "\(song) · \($0)" } ?? song
        Pasteboard.copy(value)
        Log.debug("AppDelegate: Copied current track: \(value)", category: "App")
    }

    /// Copies a multi-platform `song.link` URL for the currently-playing track
    /// to the pasteboard, falling back to the Apple Music track URL when the
    /// song.link sentinel hasn't resolved yet. No-op when nothing is cached.
    /// The menu item is disabled in that state, so this guard is belt-and-suspenders.
    @objc func copySongLink() {
        guard let song = currentSong, let artist = currentArtist else { return }
        let links = ArtworkService.shared.cachedTrackLinks(track: song, artist: artist)
        guard let url = links.songLinkURL ?? links.trackViewURL else {
            Log.debug("AppDelegate: Copy Song Link no-op: no URL cached for \(song) by \(artist)", category: "App")
            return
        }
        Pasteboard.copy(url)
        Log.debug("AppDelegate: Copied song link: \(url)", category: "App")
    }

    /// Sends the same `!song` reply a viewer would see, directly to chat.
    @objc func shareCurrentTrackToTwitch() {
        guard twitchService?.isConnectedSnapshot.value ?? false else { return }
        let message = getCurrentSongInfo()
        if let service = twitchService {
            Task { await service.sendMessage(message) }
        }
        Log.debug("AppDelegate: Shared current track to Twitch chat", category: "App")
    }

    /// Copies a recently-played track label from the submenu. The full
    /// `"Title · Artist"` string is stashed on the menu item as
    /// `representedObject`.
    @objc func copyRecentTrack(_ sender: NSMenuItem) {
        guard let value = sender.representedObject as? String else { return }
        Pasteboard.copy(value)
    }
}

// MARK: - Streamer Quick Actions

extension AppDelegate {

    /// Opens the local widget page in the user's default browser.
    @objc func openWidgetInBrowser() {
        ExternalLink.open("http://localhost:\(resolvedWidgetPort())")
    }

    /// Force-cycles Twitch, Discord, and the websocket overlays so a streamer
    /// can recover from a network blip without poking each integration.
    ///
    /// Twitch leaves *and* rejoins (when creds + channel are available) so
    /// the menu item lives up to its name. Previously it only left, which
    /// required opening Settings to come back online.
    @objc func reconnectAllServices() {
        // Twitch: leave then rejoin when creds + channel + clientID are all present.
        if let twitch = twitchService, twitch.isConnectedSnapshot.value {
            let token = KeychainService.loadTwitchToken()
            let channelRaw = Preferences.twitchChannelName
            let channel: String? = channelRaw.isEmpty ? nil : channelRaw
            let clientID = TwitchChatService.resolveClientID()
            Task {
                await twitch.leaveChannel()
                Log.info("AppDelegate: Twitch left channel for restart", category: "App")
                guard let token, !token.isEmpty,
                      let channel, !channel.isEmpty,
                      let clientID, !clientID.isEmpty else {
                    Log.info("AppDelegate: Skipped Twitch rejoin (missing creds or channel)", category: "App")
                    return
                }
                try? await Task.sleep(for: .milliseconds(250))
                do {
                    try await twitch.connectToChannel(channelName: channel, token: token, clientID: clientID)
                    Log.info("AppDelegate: Twitch rejoin requested for #\(channel)", category: "App")
                } catch {
                    Log.warn("AppDelegate: Twitch rejoin failed: \(error.localizedDescription)", category: "App")
                }
            }
        }

        // Discord: setEnabled(false) → setEnabled(true) tears down and
        // re-opens the IPC socket with fresh state.
        if FeatureFlags.discordEnabled {
            let discord = discordService
            Task {
                await discord?.setEnabled(false)
                try? await Task.sleep(for: .milliseconds(250))
                await discord?.setEnabled(true)
                Log.info("AppDelegate: Discord IPC cycled", category: "App")
            }
        }

        // Widgets: same toggle dance restarts the NWListener.
        if FeatureFlags.websocketEnabled {
            let server = websocketServer
            Task {
                await server?.setEnabled(false)
                try? await Task.sleep(for: .milliseconds(250))
                await server?.setEnabled(true)
                Log.info("AppDelegate: Widget WebSocket server cycled", category: "App")
            }
        }

        Log.info("AppDelegate: Restart Integrations triggered from tray", category: "App")
    }
}

// MARK: - Help Actions

extension AppDelegate {

    /// Triggers a manual Sparkle update check (works in DEBUG via the
    /// bundled dev-appcast.xml; reaches the real appcast in release builds).
    /// Falls back to opening the GitHub Releases page when Sparkle is
    /// unavailable (Homebrew install or updater not initialized) so the
    /// click is never silent.
    @objc func checkForUpdatesFromMenu() {
        if sparkleUpdater?.checkForUpdates() != true {
            ExternalLink.open(AppConstants.URLs.githubReleases)
        }
    }

    /// Re-opens the What's New sheet for the current marketing version.
    @objc func showWhatsNewFromMenu() {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
        showWhatsNew(version: version)
    }

    /// Opens the public documentation site.
    @objc func openDocs() {
        ExternalLink.open(AppConstants.URLs.docs)
    }

    /// Opens the GitHub issue form with prefilled environment info.
    @objc func reportBug() {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "0"
        let install: BugReportURL.InstallMethod = Bundle.main.isHomebrewInstall ? .homebrew : .dmg
        let url = BugReportURL.make(
            base: AppConstants.URLs.githubIssuesNew,
            appVersion: version,
            build: build,
            osVersion: ProcessInfo.processInfo.operatingSystemVersionString,
            arch: BugReportURL.currentArch(),
            install: install
        )
        if let url { NSWorkspace.shared.open(url) }
    }

    /// Opens the community Discord invite.
    @objc func openCommunityDiscord() {
        ExternalLink.open(AppConstants.URLs.communityDiscord)
    }

    /// Opens the WolfWave GitHub repository.
    @objc func openGitHub() {
        ExternalLink.open(AppConstants.URLs.github)
    }
}
