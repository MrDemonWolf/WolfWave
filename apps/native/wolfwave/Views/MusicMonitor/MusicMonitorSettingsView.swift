//
//  MusicMonitorSettingsView.swift
//  wolfwave
//
//  Created by MrDemonWolf, Inc. on 1/17/26.
//

import SwiftUI

/// Settings for Apple Music playback monitoring.
///
/// Allows users to enable or disable real-time Apple Music tracking.
/// When enabled, WolfWave monitors the current playing track and updates:
/// - Twitch chat bot command responses (!song, !last)
/// - Discord Rich Presence
/// - External WebSocket endpoints (if configured)
///
/// Also detects whether Apple Events permission has been granted for Apple Music
/// and shows guidance if the permission has been denied.
struct MusicMonitorSettingsView: View {
    // MARK: - User Settings

    @AppStorage(AppConstants.UserDefaults.trackingEnabled)
    private var trackingEnabled = true

    @State private var permissionDenied = false
    @State private var currentTrack: String?
    @State private var currentArtist: String?
    @State private var currentAlbum: String?

    // MARK: - Integration Status

    @State private var twitchConnected = false
    @State private var discordActive = false
    @State private var widgetRunning = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Section Header
            VStack(alignment: .leading, spacing: 6) {
                Text("Music Sync")
                    .sectionHeader()
                    .accessibilityLabel("Music Playback Monitor")

                Text("Connects to Apple Music and shares what's playing everywhere.")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            // Permission warning
            if permissionDenied {
                HStack(spacing: 10) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(.orange)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Need Apple Music Permission")
                            .font(.system(size: 12, weight: .semibold))
                        Text("WolfWave needs permission to see what song is playing. Click here to fix it.")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer()

                    Button("Open Settings") {
                        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation") {
                            NSWorkspace.shared.open(url)
                        }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
                .padding(12)
                .background(Color.orange.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: AppConstants.SettingsUI.cardCornerRadius))
                .overlay(
                    RoundedRectangle(cornerRadius: AppConstants.SettingsUI.cardCornerRadius)
                        .stroke(Color.orange.opacity(0.2), lineWidth: 1)
                )
            }

            // Unified Monitoring Panel
            unifiedPanel
        }
        .onAppear {
            loadCurrentTrack()
            loadIntegrationStatuses()
        }
        .onReceive(
            NotificationCenter.default.publisher(
                for: NSNotification.Name(AppConstants.Notifications.nowPlayingChanged)
            )
        ) { notification in
            withAnimation(.easeInOut(duration: 0.25)) {
                currentTrack = notification.userInfo?["track"] as? String
                currentArtist = notification.userInfo?["artist"] as? String
                currentAlbum = notification.userInfo?["album"] as? String
            }
        }
        .onReceive(
            NotificationCenter.default.publisher(
                for: NSNotification.Name(AppConstants.Notifications.twitchConnectionStateChanged)
            )
        ) { notification in
            withAnimation(.easeInOut(duration: 0.2)) {
                twitchConnected = notification.userInfo?["isConnected"] as? Bool ?? false
            }
        }
        .onReceive(
            NotificationCenter.default.publisher(
                for: NSNotification.Name(AppConstants.Notifications.discordStateChanged)
            )
        ) { notification in
            withAnimation(.easeInOut(duration: 0.2)) {
                let state = notification.userInfo?["state"] as? String ?? ""
                discordActive = state == "connected"
            }
        }
        .onReceive(
            NotificationCenter.default.publisher(
                for: NSNotification.Name(AppConstants.Notifications.websocketServerStateChanged)
            )
        ) { notification in
            withAnimation(.easeInOut(duration: 0.2)) {
                let state = notification.userInfo?["state"] as? String ?? ""
                widgetRunning = state == "listening"
            }
        }
        .onAppear {
            checkMusicPermission()
        }
    }

    // MARK: - Unified Panel

    @ViewBuilder
    private var unifiedPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Toggle row
            ToggleSettingRow(
                title: "Sync Music",
                subtitle: "Updates your status and widget when the song changes",
                isOn: $trackingEnabled,
                accessibilityLabel: "Enable Apple Music monitoring",
                accessibilityIdentifier: "musicTrackingToggle",
                accessibilityHint: "Toggle to enable or disable Apple Music monitoring",
                onChange: { newValue in
                    notifyTrackingSettingChanged(enabled: newValue)
                }
            )
            .padding(AppConstants.SettingsUI.cardPadding)

            Divider()
                .padding(.horizontal, AppConstants.SettingsUI.cardPadding)

            // Now Playing section
            nowPlayingSection
                .padding(AppConstants.SettingsUI.cardPadding)

            Divider()
                .padding(.horizontal, AppConstants.SettingsUI.cardPadding)

            // Integration statuses
            integrationStatusSection
                .padding(AppConstants.SettingsUI.cardPadding)
        }
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: AppConstants.SettingsUI.cardCornerRadius))
    }

    // MARK: - Now Playing Section

    @ViewBuilder
    private var nowPlayingSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "music.note")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
                Text("Now Playing")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
            }

            if let track = currentTrack {
                HStack(spacing: 12) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color.accentColor.opacity(0.15))
                        Image(systemName: "music.note")
                            .font(.system(size: 18, weight: .medium))
                            .foregroundStyle(Color.accentColor)
                    }
                    .frame(width: 48, height: 48)

                    VStack(alignment: .leading, spacing: 3) {
                        Text(track)
                            .font(.system(size: 13, weight: .semibold))
                            .lineLimit(1)

                        if let artist = currentArtist {
                            Text(artist)
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }

                        if let album = currentAlbum {
                            Text(album)
                                .font(.system(size: 11))
                                .foregroundStyle(.tertiary)
                                .lineLimit(1)
                        }
                    }

                    Spacer()
                }
            } else {
                HStack(spacing: 12) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color(nsColor: .separatorColor).opacity(0.3))
                        Image(systemName: "music.note")
                            .font(.system(size: 18, weight: .medium))
                            .foregroundStyle(.tertiary)
                    }
                    .frame(width: 48, height: 48)

                    Text(trackingEnabled ? "Nothing playing right now" : "Sync is off")
                        .font(.system(size: 13))
                        .foregroundStyle(.tertiary)

                    Spacer()
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(nowPlayingAccessibilityLabel)
    }

    // MARK: - Integration Status Section

    @ViewBuilder
    private var integrationStatusSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "link")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                Text("Integrations")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
            }

            VStack(spacing: 6) {
                integrationRow(
                    icon: "bubble.left.fill",
                    iconColor: Color(red: 0.57, green: 0.27, blue: 1.0),
                    name: "Twitch",
                    connected: twitchConnected,
                    activeLabel: "Connected",
                    inactiveLabel: "Disconnected"
                )

                integrationRow(
                    icon: "headphones",
                    iconColor: Color(red: 0.35, green: 0.40, blue: 0.95),
                    name: "Discord",
                    connected: discordActive,
                    activeLabel: "Active",
                    inactiveLabel: "Idle"
                )

                integrationRow(
                    icon: "tv",
                    iconColor: .blue,
                    name: "Widget",
                    connected: widgetRunning,
                    activeLabel: "Running",
                    inactiveLabel: "Stopped"
                )
            }
        }
    }

    /// A single integration status row with icon, name, and colored dot indicator.
    private func integrationRow(
        icon: String,
        iconColor: Color,
        name: String,
        connected: Bool,
        activeLabel: String,
        inactiveLabel: String
    ) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 11))
                .foregroundStyle(iconColor)
                .frame(width: 16)

            Text(name)
                .font(.system(size: 12))

            Spacer()

            Circle()
                .fill(connected ? Color.green : Color(nsColor: .separatorColor))
                .frame(width: 6, height: 6)

            Text(connected ? activeLabel : inactiveLabel)
                .font(.system(size: 11))
                .foregroundStyle(connected ? .primary : .tertiary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(name): \(connected ? activeLabel : inactiveLabel)")
    }

    // MARK: - Computed Properties

    /// Accessibility label for the now-playing card.
    private var nowPlayingAccessibilityLabel: String {
        if let track = currentTrack {
            var label = "Now playing: \(track)"
            if let artist = currentArtist { label += " by \(artist)" }
            if let album = currentAlbum { label += " on \(album)" }
            return label
        }
        return trackingEnabled ? "No track playing" : "Tracking disabled"
    }

    // MARK: - Helpers

    /// Loads the current track info from AppDelegate.
    private func loadCurrentTrack() {
        if let appDelegate = AppDelegate.shared {
            currentTrack = appDelegate.currentSong
            currentArtist = appDelegate.currentArtist
            currentAlbum = appDelegate.currentAlbum
        }
    }

    /// Posts a notification when music tracking is toggled.
    private func notifyTrackingSettingChanged(enabled: Bool) {
        NotificationCenter.default.post(
            name: NSNotification.Name(AppConstants.Notifications.trackingSettingChanged),
            object: nil,
            userInfo: ["enabled": enabled]
        )
    }

    /// Checks whether the app has Apple Events permission for Apple Music.
    ///
    /// Uses a lightweight ScriptingBridge query to detect whether the system
    /// has denied Apple Events automation for `com.apple.Music`.
    private func checkMusicPermission() {
        let target = NSAppleEventDescriptor(bundleIdentifier: AppConstants.Music.bundleIdentifier)
        let status = AEDeterminePermissionToAutomateTarget(
            target.aeDesc, typeWildCard, typeWildCard, false
        )
        permissionDenied = (status == OSStatus(errAEEventNotPermitted))
    }

    /// Loads initial integration statuses from AppDelegate.
    private func loadIntegrationStatuses() {
        if let appDelegate = AppDelegate.shared {
            twitchConnected = appDelegate.twitchService?.isConnected ?? false
            discordActive = appDelegate.discordService?.state == .connected
            widgetRunning = appDelegate.websocketServer?.state == .listening
        }
    }
}

// MARK: - Preview

#Preview("Default State") {
    MusicMonitorSettingsView()
        .padding()
        .frame(width: 600)
}
#Preview("With Current Track") {
    let view = MusicMonitorSettingsView()
    return view
        .padding()
        .frame(width: 600)
        .onAppear {
            // Simulate a track playing
            NotificationCenter.default.post(
                name: NSNotification.Name(AppConstants.Notifications.nowPlayingChanged),
                object: nil,
                userInfo: [
                    "track": "Blinding Lights",
                    "artist": "The Weeknd",
                    "album": "After Hours"
                ]
            )
        }
}

#Preview("Permission Denied") {
    @Previewable @State var trackingEnabled = true
    
    struct PermissionDeniedView: View {
        var body: some View {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Music Playback Monitor")
                        .sectionHeader()
                    
                    Text("Automatically detect what's playing in Apple Music and share it with Twitch chat, Discord, and now-playing widgets.")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                
                // Permission warning
                HStack(spacing: 10) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(.orange)
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Apple Music access denied")
                            .font(.system(size: 12, weight: .semibold))
                        Text("WolfWave needs permission to read playback info from Apple Music. Open System Settings to grant access.")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    
                    Spacer()
                    
                    Button("Open Settings") { }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                }
                .padding(12)
                .background(Color.orange.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.orange.opacity(0.2), lineWidth: 1)
                )
            }
        }
    }
    
    return PermissionDeniedView()
        .padding()
        .frame(width: 600)
}

