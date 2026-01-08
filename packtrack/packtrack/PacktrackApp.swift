//
//  PacktrackApp.swift
//  packtrack
//
//  Created by Nathanial Henniges on 1/8/26.
//

import SwiftUI
import AppKit

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
    var statusItem: NSStatusItem?
    var musicTracker: MusicTracker?
    var settingsWindow: NSWindow?

    private var appName: String {
        Bundle.main.infoDictionary?["CFBundleDisplayName"] as? String ??
        Bundle.main.infoDictionary?["CFBundleName"] as? String ??
        "Pack Track"
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem?.button {
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

        let menu = NSMenu()

        // Header
        let headerItem = NSMenuItem(title: "Now Playing:", action: nil, keyEquivalent: "")
        headerItem.isEnabled = false
        menu.addItem(headerItem)

        // Song / Status line
        let songItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        songItem.isEnabled = false
        menu.addItem(songItem)

        // Artist
        let artistItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        artistItem.isEnabled = false
        menu.addItem(artistItem)

        // Album
        let albumItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        albumItem.isEnabled = false
        menu.addItem(albumItem)

        statusItem?.menu = menu

        resetNowPlayingMenu(message: "No track playing")

        menu.addItem(.separator())

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
        menu.addItem(
            NSMenuItem(
                title: "Quit",
                action: #selector(NSApplication.terminate(_:)),
                keyEquivalent: "q"
            )
        )

        musicTracker = MusicTracker()
        musicTracker?.delegate = self

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(trackingSettingChanged),
            name: NSNotification.Name("TrackingSettingChanged"),
            object: nil
        )

        if UserDefaults.standard.object(forKey: "trackingEnabled") == nil {
            UserDefaults.standard.set(true, forKey: "trackingEnabled")
        }

        if UserDefaults.standard.bool(forKey: "trackingEnabled") {
            musicTracker?.startTracking()
        } else {
            resetNowPlayingMenu(message: "Tracking disabled")
        }
    }

    // MARK: - Menu State Helpers

    private func resetNowPlayingMenu(message: String) {
        guard let menu = statusItem?.menu, menu.items.count > 3 else { return }

        let attr = NSAttributedString(
            string: "  \(message)",
            attributes: [
                .foregroundColor: NSColor.secondaryLabelColor,
                .font: NSFont.systemFont(ofSize: NSFont.systemFontSize - 1)
            ]
        )

        menu.items[1].attributedTitle = attr
        menu.items[1].isHidden = false

        menu.items[2].isHidden = true
        menu.items[3].isHidden = true
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

    func updateTrackDisplay(song: String?, artist: String?, album: String?) {
        DispatchQueue.main.async { [weak self] in
            guard let self, let menu = self.statusItem?.menu else { return }

            if let song, let artist, let album {
                let songAttr = NSMutableAttributedString()
                songAttr.append(NSAttributedString(
                    string: "  Song: ",
                    attributes: [.font: NSFont.boldSystemFont(ofSize: NSFont.systemFontSize)]
                ))
                songAttr.append(NSAttributedString(string: song))

                let artistAttr = NSMutableAttributedString()
                artistAttr.append(NSAttributedString(
                    string: "  Artist: ",
                    attributes: [.font: NSFont.boldSystemFont(ofSize: NSFont.systemFontSize)]
                ))
                artistAttr.append(NSAttributedString(string: artist))

                let albumAttr = NSMutableAttributedString()
                albumAttr.append(NSAttributedString(
                    string: "  Album: ",
                    attributes: [.font: NSFont.boldSystemFont(ofSize: NSFont.systemFontSize)]
                ))
                albumAttr.append(NSAttributedString(string: album))

                menu.items[1].attributedTitle = songAttr
                menu.items[2].attributedTitle = artistAttr
                menu.items[3].attributedTitle = albumAttr

                menu.items[1].isHidden = false
                menu.items[2].isHidden = false
                menu.items[3].isHidden = false
            } else {
                self.resetNowPlayingMenu(message: "No track playing")
            }
        }
    }

    // MARK: - Actions

    @objc func trackingSettingChanged(_ notification: Notification) {
        guard let enabled = notification.userInfo?["enabled"] as? Bool else { return }

        if enabled {
            musicTracker?.startTracking()
        } else {
            musicTracker?.stopTracking()
            updateNowPlaying("Tracking disabled")
        }
    }

    /// Opens the settings window.
    ///
    /// Creates the settings window on first open and reuses it on subsequent opens.
    /// The window is brought to the front and the app is activated.
    @objc func openSettings() {
        if settingsWindow == nil {
            let hosting = NSHostingController(rootView: SettingsView())
            settingsWindow = NSWindow(contentViewController: hosting)
            settingsWindow?.title = "\(appName) Settings"
            settingsWindow?.styleMask = [.titled, .closable, .miniaturizable]
            settingsWindow?.setContentSize(NSSize(width: 520, height: 560))
            settingsWindow?.center()
        }

        settingsWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    /// Shows the standard About panel for the application.
    ///
    /// Displays macOS's built-in About panel with app information from Info.plist.
    @objc func showAbout() {
        NSApp.orderFrontStandardAboutPanel(
            options: [.applicationName: appName]
        )
        NSApp.activate(ignoringOtherApps: true)
    }
}

// MARK: - MusicTrackerDelegate

/// Extension implementing the MusicTrackerDelegate protocol.
///
/// Receives callbacks from MusicTracker and updates the menu bar display accordingly.
extension AppDelegate: MusicTrackerDelegate {
    func musicTracker(_ tracker: MusicTracker, didUpdateTrack track: String, artist: String, album: String) {
        updateTrackDisplay(song: track, artist: artist, album: album)
    }

    func musicTracker(_ tracker: MusicTracker, didUpdateStatus status: String) {
        updateNowPlaying(status)
    }
}
