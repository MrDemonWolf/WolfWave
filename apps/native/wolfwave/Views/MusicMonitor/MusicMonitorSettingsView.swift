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
    @State private var isRequesting = false

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
                    title: "Sync Music",
                    subtitle: "When this is on, your Apple Music shows up in chat, on Discord, and in your stream.",
                    isOn: $trackingEnabled,
                    accessibilityLabel: "Toggle Sync Music",
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
            VStack(alignment: .leading, spacing: 8) {
                Text("Live from Apple Music")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                    .tracking(0.6)
                    .accessibilityAddTraits(.isHeader)

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
        .task {
            // Yield so the first frame paints before we read services / system state.
            await Task.yield()
            // Permission check is the costliest read — reuse the session cache when fresh.
            if let cached = MusicPermissionCache.read() {
                permissionState = cached
            } else {
                refreshPermission()
            }
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
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            refreshPermission()
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
                if let subtitle = permissionSubtitle {
                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer(minLength: 8)

            permissionTrailingControl
        }
    }

    @ViewBuilder
    private var permissionTrailingControl: some View {
        switch permissionState {
        case .granted:
            Button("Recheck", action: refreshPermission)
                .buttonStyle(.borderless)
                .controlSize(.small)
                .foregroundStyle(.secondary)

        case .denied:
            Button("Open System Settings") {
                MusicPermissionChecker.openAutomationSettings()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)

        case .unknown:
            HStack(spacing: 6) {
                Button(action: requestPermission) {
                    HStack(spacing: 6) {
                        if isRequesting {
                            ProgressView()
                                .progressViewStyle(.circular)
                                .controlSize(.small)
                        }
                        Text("Allow")
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(isRequesting)

                Button("Open Settings") {
                    MusicPermissionChecker.openAutomationSettings()
                }
                .buttonStyle(.borderless)
                .controlSize(.small)
                .foregroundStyle(.secondary)
            }
        }
    }

    private var permissionIconName: String {
        switch permissionState {
        case .granted: return "music.note"
        case .denied: return "lock.fill"
        case .unknown: return "music.note"
        }
    }

    private var permissionIconColor: Color {
        switch permissionState {
        case .granted: return AppConstants.Brand.appleMusicGradientEnd
        case .denied: return .red
        case .unknown: return .accentColor
        }
    }

    private var permissionTitle: String {
        switch permissionState {
        case .granted: return "Music access on"
        case .denied: return "Music access off"
        case .unknown: return "Allow Music access"
        }
    }

    private var permissionSubtitle: String? {
        switch permissionState {
        case .granted: return nil
        case .denied: return "Turn on Automation → Music in System Settings."
        case .unknown: return "macOS will ask once. We only read the track — never play, pause, or change your library."
        }
    }

    // MARK: - Helpers

    private var widgetPort: UInt16 {
        UInt16(UserDefaults.standard.integer(forKey: AppConstants.UserDefaults.widgetPort))
            .nonZeroOrDefault(AppConstants.WebSocketServer.widgetDefaultPort)
    }

    /// Convenience wrapper around `NotificationCenter.default.publisher(for:)`
    /// that builds the `NSNotification.Name` from a string constant.
    ///
    /// - Parameter name: Notification name string (from `AppConstants.Notifications`).
    /// - Returns: A publisher emitting that notification.
    private func notif(_ name: String) -> NotificationCenter.Publisher {
        NotificationCenter.default.publisher(for: NSNotification.Name(name))
    }

    /// Re-queries Apple Music automation permission, caches the result, and
    /// reloads the current track if permission is now granted.
    private func refreshPermission() {
        let next = MusicPermissionChecker.currentState()
        MusicPermissionCache.write(next)
        withAnimation(.easeInOut(duration: 0.2)) {
            permissionState = next
        }
        // If we're now granted, try to get the current track again.
        if next == .granted {
            loadCurrentTrack()
        }
    }

    /// Prompts the user for Apple Music automation permission, animates the
    /// resolution, and pulls the current track on success.
    private func requestPermission() {
        isRequesting = true
        Task {
            let resolved = MusicPermissionChecker.requestAccess()
            await MainActor.run {
                withAnimation(.easeInOut(duration: 0.2)) {
                    permissionState = resolved
                }
                isRequesting = false
                if resolved == .granted {
                    loadCurrentTrack()
                }
            }
        }
    }

    /// Snapshots the currently-playing track from `AppDelegate` into the
    /// view's state so the "Now Playing" preview reflects live playback.
    private func loadCurrentTrack() {
        if let appDelegate = AppDelegate.shared {
            currentTrack = appDelegate.currentSong
            currentArtist = appDelegate.currentArtist
            currentAlbum = appDelegate.currentAlbum
        }
    }

    /// Loads connection status for Twitch / Discord / overlay from the
    /// running services so the integration row chips reflect reality.
    private func loadIntegrationStatuses() {
        if let appDelegate = AppDelegate.shared {
            twitchConnected = appDelegate.twitchService?.isConnectedSnapshot.value ?? false
            // Reads the persisted channel name (set during sign-in).
            twitchChannel = UserDefaults.standard.string(forKey: "twitchChannelName")
            widgetRunning = appDelegate.websocketServer?.state == .listening
            if let discordService = appDelegate.discordService {
                Task { @MainActor in
                    discordActive = await discordService.state == .connected
                }
            } else {
                discordActive = false
            }
        }
    }

    /// Posts a `trackingSettingChanged` notification so the music monitor
    /// starts or stops based on the user's toggle.
    ///
    /// - Parameter enabled: New tracking value.
    private func notifyTrackingSettingChanged(enabled: Bool) {
        NotificationCenter.default.post(
            name: NSNotification.Name(AppConstants.Notifications.trackingSettingChanged),
            object: nil,
            userInfo: ["enabled": enabled]
        )
    }
}

// MARK: - Permission cache

/// Process-lifetime cache for the Music automation permission result.
///
/// `MusicPermissionChecker.currentState()` issues an Apple Events probe that can take tens of
/// milliseconds — measurable when switching back to the General settings pane. Cache the result
/// for a short window so re-entering the pane within the same session is instant. The cache is
/// invalidated by `NSApplication.didBecomeActiveNotification` and by explicit refresh calls.
private enum MusicPermissionCache {
    private static let ttl: TimeInterval = 30
    nonisolated(unsafe) private static var value: MusicPermissionState?
    nonisolated(unsafe) private static var storedAt: Date?

    static func read() -> MusicPermissionState? {
        guard let value, let storedAt, Date().timeIntervalSince(storedAt) < ttl else { return nil }
        return value
    }

    static func write(_ state: MusicPermissionState) {
        value = state
        storedAt = Date()
    }
}

// MARK: - UInt16 helper

private extension UInt16 {
    /// Returns `self` if non-zero, otherwise `fallback`. Used to coerce
    /// `UserDefaults.integer(forKey:)`'s zero-default into the app's real
    /// default port when the user has never customized it.
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
