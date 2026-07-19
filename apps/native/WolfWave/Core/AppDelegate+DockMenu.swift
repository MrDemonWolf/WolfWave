//
//  AppDelegate+DockMenu.swift
//  WolfWave
//
//  Created by Nathanial Henniges on 2026-05-25.
//  Copyright © 2026 MrDemonWolf, Inc. All rights reserved.
//

import AppKit

// MARK: - Dock Menu

extension AppDelegate {

    /// Builds the right-click Dock menu shown when the app is dock-visible
    /// (`DockVisibility.dockOnly` or `.both`). Surfaces the most-used tray
    /// actions (now-playing, playback controls, song-request hold,
    /// integration toggles, and Settings) so streamers don't have to open
    /// the app to drive it from the Dock.
    ///
    /// All items reuse existing `@objc` selectors from
    /// `AppDelegate+MenuBar.swift`; no business logic lives here.
    func applicationDockMenu(_ sender: NSApplication) -> NSMenu? {
        let menu = NSMenu()

        addDockNowPlaying(into: menu)
        addDockPlaybackControls(into: menu)
        addDockSongRequestHold(into: menu)
        addDockServiceToggles(into: menu)
        addDockSettings(into: menu)

        return menu
    }

    // MARK: - Sections

    private func addDockNowPlaying(into menu: NSMenu) {
        guard let song = currentSong else { return }
        let title = currentArtist.map { "\(song) · \($0)" } ?? song
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        menu.addItem(item)
        menu.addItem(.separator())
    }

    private func addDockPlaybackControls(into menu: NSMenu) {
        guard isMusicAppOpen() else { return }

        // Derive Play/Pause from the cached playback snapshot pushed by the
        // AppleMusicSource delegate, matching the menu-bar path. Building the
        // Dock menu must return immediately, so avoid the blocking
        // musicController.isPlaying read here.
        let isPlaying = isPlayingNow

        menu.addItem(NSMenuItem(
            title: isPlaying ? "Pause" : "Play",
            action: #selector(playPause),
            keyEquivalent: ""
        ))
        menu.addItem(NSMenuItem(
            title: "Next Track",
            action: #selector(nextTrack),
            keyEquivalent: ""
        ))
        menu.addItem(NSMenuItem(
            title: "Previous Track",
            action: #selector(previousTrack),
            keyEquivalent: ""
        ))
        menu.addItem(.separator())
    }

    private func addDockSongRequestHold(into menu: NSMenu) {
        guard FeatureFlags.songRequestEnabled else { return }
        let holdEnabled = songRequestService?.isHoldEnabled ?? false
        menu.addItem(NSMenuItem(
            title: holdEnabled ? "Resume Song Requests" : "Hold Song Requests",
            action: #selector(toggleSongRequestHold),
            keyEquivalent: ""
        ))
        menu.addItem(.separator())
    }

    private func addDockServiceToggles(into menu: NSMenu) {
        let trackingOn = FeatureFlags.trackingEnabled
        let trackingItem = NSMenuItem(
            title: "Apple Music",
            action: #selector(toggleTracking),
            keyEquivalent: ""
        )
        trackingItem.state = trackingOn ? .on : .off
        menu.addItem(trackingItem)

        if KeychainService.loadTwitchToken() != nil {
            let connected = twitchService?.currentlyConnected ?? false
            let twitchItem = NSMenuItem(
                title: "Twitch",
                action: #selector(toggleTwitchConnection),
                keyEquivalent: ""
            )
            twitchItem.state = connected ? .on : .off
            menu.addItem(twitchItem)
        }

        let discordEnabled = FeatureFlags.discordEnabled
        let discordItem = NSMenuItem(
            title: "Discord",
            action: #selector(toggleDiscordPresence),
            keyEquivalent: ""
        )
        discordItem.state = discordEnabled ? .on : .off
        menu.addItem(discordItem)

        let widgetsEnabled = FeatureFlags.websocketEnabled
        let widgetsItem = NSMenuItem(
            title: "OBS Overlay",
            action: #selector(toggleWebSocket),
            keyEquivalent: ""
        )
        widgetsItem.state = widgetsEnabled ? .on : .off
        menu.addItem(widgetsItem)

        menu.addItem(.separator())
    }

    private func addDockSettings(into menu: NSMenu) {
        let settingsItem = NSMenuItem(
            title: AppConstants.MenuLabels.settings,
            action: #selector(openSettings),
            keyEquivalent: ","
        )
        menu.addItem(settingsItem)
    }
}
