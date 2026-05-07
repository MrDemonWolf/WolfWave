//
//  MusicMonitorSettingsView.swift
//  wolfwave
//
//  Created by MrDemonWolf, Inc. on 1/17/26.
//

import SwiftUI
import AppKit

/// Music Sync (General tab) — hero now-playing card + integration dashboard.
///
/// This is the home tab of the redesigned Settings (Screen B in the
/// `WolfWave Redesign.html` design bundle). When Apple Events automation has
/// been denied for `com.apple.Music` we surface `PermissionDeniedBanner`
/// instead of the unified panel and route Configure rows to the right
/// settings pane.
struct MusicMonitorSettingsView: View {

    // MARK: - User Settings

    @AppStorage(AppConstants.UserDefaults.trackingEnabled)
    private var trackingEnabled = true

    // MARK: - Music permission

    @State private var permissionState: MusicPermissionState = .unknown
    @State private var showInstructionSheet = false

    // MARK: - Now playing

    @State private var currentTrack: String?
    @State private var currentArtist: String?
    @State private var currentAlbum: String?

    // MARK: - Integration status

    @State private var twitchConnected = false
    @State private var twitchChannel: String?
    @State private var discordActive = false
    @State private var widgetRunning = false

    // MARK: - Inputs

    var configure: (IntegrationDashboardView.Section) -> Void = { _ in }

    // MARK: - Body

    var body: some View {
        VStack(alignment: .leading, spacing: AppConstants.SettingsUI.sectionSpacing) {

            if permissionState == .denied {
                PermissionDeniedBanner(
                    onOpenSystemSettings: { MusicPermissionChecker.openAutomationSettings() },
                    onTryAgain: refreshPermission,
                    onShowInstructions: { showInstructionSheet = true }
                )
            }

            // Master toggle + permission row
            VStack(alignment: .leading, spacing: 0) {
                ToggleSettingRow(
                    title: "Track what I'm playing",
                    subtitle: "When this is on, your Apple Music shows up in chat, on Discord, and in your stream.",
                    isOn: $trackingEnabled,
                    accessibilityLabel: "Toggle music tracking",
                    accessibilityIdentifier: "musicTrackingToggle",
                    onChange: { newValue in
                        notifyTrackingSettingChanged(enabled: newValue)
                    }
                )
                .padding(AppConstants.SettingsUI.cardPadding)

                Divider().padding(.horizontal, AppConstants.SettingsUI.cardPadding)

                permissionStatusRow
                    .padding(AppConstants.SettingsUI.cardPadding)
            }
            .cardStyleUnpadded()

            // Hero now-playing
            if permissionState == .denied {
                PermissionPausedNowPlayingCard()
            } else {
                NowPlayingHeroCard(
                    track: currentTrack,
                    artist: currentArtist,
                    album: currentAlbum,
                    trackingEnabled: trackingEnabled
                )
            }

            // Integration dashboard
            IntegrationDashboardView(
                twitchConnected: twitchConnected,
                twitchChannel: twitchChannel,
                twitchViewerCount: nil,
                discordConnected: discordActive,
                widgetRunning: widgetRunning,
                widgetURL: widgetRunning ? "http://localhost:\(widgetPort)" : nil,
                remoteSendingEnabled: false,
                permissionPaused: permissionState == .denied,
                configure: configure
            )
        }
        .sheet(isPresented: $showInstructionSheet) {
            PermissionInstructionSheet(
                onOpenSystemSettings: {
                    MusicPermissionChecker.openAutomationSettings()
                },
                onTryAgain: refreshPermission
            )
        }
        .onAppear {
            refreshPermission()
            loadCurrentTrack()
            loadIntegrationStatuses()
        }
        .onReceive(notif(AppConstants.Notifications.nowPlayingChanged)) { notification in
            withAnimation(.easeInOut(duration: 0.25)) {
                currentTrack = notification.userInfo?["track"] as? String
                currentArtist = notification.userInfo?["artist"] as? String
                currentAlbum = notification.userInfo?["album"] as? String
            }
            // A successful track read implies the user has granted access.
            if currentTrack != nil, permissionState == .denied {
                permissionState = .granted
            }
        }
        .onReceive(notif(AppConstants.Notifications.twitchConnectionStateChanged)) { notification in
            withAnimation(.easeInOut(duration: 0.2)) {
                twitchConnected = notification.userInfo?["isConnected"] as? Bool ?? false
            }
        }
        .onReceive(notif(AppConstants.Notifications.discordStateChanged)) { notification in
            withAnimation(.easeInOut(duration: 0.2)) {
                let state = notification.userInfo?["state"] as? String ?? ""
                discordActive = state == "connected"
            }
        }
        .onReceive(notif(AppConstants.Notifications.websocketServerStateChanged)) { notification in
            withAnimation(.easeInOut(duration: 0.2)) {
                let state = notification.userInfo?["state"] as? String ?? ""
                widgetRunning = state == "listening"
            }
        }
    }

    // MARK: - Permission status row

    @ViewBuilder
    private var permissionStatusRow: some View {
        HStack(spacing: 12) {
            Image(systemName: permissionIconName)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(permissionIconColor)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 2) {
                Text(permissionTitle)
                    .font(.system(size: 13, weight: .medium))
                Text(permissionSubtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 8)

            Button("Change in System Settings") {
                MusicPermissionChecker.openAutomationSettings()
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
    }

    private var permissionIconName: String {
        switch permissionState {
        case .granted: return "checkmark.shield.fill"
        case .denied: return "lock.fill"
        case .unknown: return "questionmark.circle"
        }
    }

    private var permissionIconColor: Color {
        switch permissionState {
        case .granted: return .green
        case .denied: return .red
        case .unknown: return .secondary
        }
    }

    private var permissionTitle: String {
        switch permissionState {
        case .granted: return "Music app — allowed"
        case .denied: return "Music app — denied"
        case .unknown: return "Checking Music app permission…"
        }
    }

    private var permissionSubtitle: String {
        switch permissionState {
        case .granted: return "WolfWave can see what's playing. You're good."
        case .denied: return "Turn on Automation → Music in System Settings."
        case .unknown: return "We're asking the system."
        }
    }

    // MARK: - Helpers

    private var widgetPort: UInt16 {
        UInt16(UserDefaults.standard.integer(forKey: AppConstants.UserDefaults.widgetPort))
            .nonZeroOrDefault(AppConstants.WebSocketServer.widgetDefaultPort)
    }

    private func notif(_ name: String) -> NotificationCenter.Publisher {
        NotificationCenter.default.publisher(for: NSNotification.Name(name))
    }

    private func refreshPermission() {
        let next = MusicPermissionChecker.currentState()
        withAnimation(.easeInOut(duration: 0.2)) {
            permissionState = next
        }
        // If we're now granted, try to get the current track again.
        if next == .granted {
            loadCurrentTrack()
        }
    }

    private func loadCurrentTrack() {
        if let appDelegate = AppDelegate.shared {
            currentTrack = appDelegate.currentSong
            currentArtist = appDelegate.currentArtist
            currentAlbum = appDelegate.currentAlbum
        }
    }

    private func loadIntegrationStatuses() {
        if let appDelegate = AppDelegate.shared {
            twitchConnected = appDelegate.twitchService?.isConnected ?? false
            // Reads the persisted channel name (set during sign-in).
            twitchChannel = UserDefaults.standard.string(forKey: "twitchChannelName")
            discordActive = appDelegate.discordService?.state == .connected
            widgetRunning = appDelegate.websocketServer?.state == .listening
        }
    }

    private func notifyTrackingSettingChanged(enabled: Bool) {
        NotificationCenter.default.post(
            name: NSNotification.Name(AppConstants.Notifications.trackingSettingChanged),
            object: nil,
            userInfo: ["enabled": enabled]
        )
    }
}

// MARK: - UInt16 helper

private extension UInt16 {
    func nonZeroOrDefault(_ fallback: UInt16) -> UInt16 {
        self == 0 ? fallback : self
    }
}

// MARK: - Preview

#Preview("Granted — playing") {
    MusicMonitorSettingsView()
        .padding()
        .frame(width: 720)
        .onAppear {
            NotificationCenter.default.post(
                name: NSNotification.Name(AppConstants.Notifications.nowPlayingChanged),
                object: nil,
                userInfo: [
                    "track": "Anti-Hero",
                    "artist": "Taylor Swift",
                    "album": "Midnights"
                ]
            )
        }
}

#Preview("Empty") {
    MusicMonitorSettingsView()
        .padding()
        .frame(width: 720)
}
