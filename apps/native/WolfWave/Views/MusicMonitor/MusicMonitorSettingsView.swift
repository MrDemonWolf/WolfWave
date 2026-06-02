//
//  MusicMonitorSettingsView.swift
//  WolfWave
//
//  Created by Nathanial Henniges on 2026-01-13.
//  Copyright © 2026 MrDemonWolf, Inc. All rights reserved.
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
    @State private var isRechecking = false
    @State private var recheckConfirmed = false

    // MARK: - Now playing

    @State private var currentTrack: String?
    @State private var currentArtist: String?
    @State private var currentAlbum: String?
    @State private var currentArtworkURL: URL?
    @State private var currentIsPaused: Bool = false

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

                // When access is denied the recovery card above already owns the
                // explanation + CTA, so hide this row to avoid repeating it.
                // Granted/unknown keep it inline (status + in-context Allow).
                if permissionState != .denied {
                    Divider().padding(.horizontal, AppConstants.SettingsUI.cardPadding)

                    permissionStatusRow
                        .padding(AppConstants.SettingsUI.cardPadding)
                }
            }
            .cardStyleUnpadded()

            // Hero now-playing
            VStack(alignment: .leading, spacing: DSSpace.s2) {
                Text("Live from Apple Music")
                    .sectionEyebrow()
                    .accessibilityAddTraits(.isHeader)

                if permissionState == .denied {
                    PermissionPausedNowPlayingCard()
                } else {
                    NowPlayingHeroCard(
                        track: currentTrack,
                        artist: currentArtist,
                        album: currentAlbum,
                        artworkURL: currentArtworkURL,
                        trackingEnabled: trackingEnabled,
                        isPaused: currentIsPaused
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
            if permissionState == .granted {
                AppDelegate.shared?.refreshNowPlaying()
            }
            loadIntegrationStatuses()
        }
        .onReceive(notif(AppConstants.Notifications.nowPlayingChanged)) { notification in
            withAnimation(.easeInOut(duration: DSMotion.Duration.base)) {
                let payload = notification.nowPlaying
                currentTrack = payload.track
                currentArtist = payload.artist
                currentAlbum = payload.album
                currentIsPaused = payload.isPaused
                currentArtworkURL = nil
            }
            // A successful track read implies the user has granted access.
            if currentTrack != nil, permissionState == .denied {
                MusicPermissionCache.write(.granted)
                permissionState = .granted
            }
            fetchArtwork()
        }
        .onReceive(notif(AppConstants.Notifications.twitchConnectionStateChanged)) { notification in
            withAnimation(.easeInOut(duration: DSMotion.Duration.base)) {
                twitchConnected = notification.isConnectedFlag ?? false
            }
        }
        .onReceive(notif(AppConstants.Notifications.discordStateChanged)) { notification in
            withAnimation(.easeInOut(duration: DSMotion.Duration.base)) {
                discordActive = (notification.stateString ?? "") == "connected"
            }
        }
        .onReceive(notif(AppConstants.Notifications.websocketServerStateChanged)) { notification in
            withAnimation(.easeInOut(duration: DSMotion.Duration.base)) {
                widgetRunning = (notification.stateString ?? "") == "listening"
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            refreshPermission()
        }
        .onReceive(notif(AppConstants.Notifications.musicPermissionDenied)) { _ in
            // The data path detected that Music.app is running but ScriptingBridge
            // reads return nil — the canonical TCC Automation denial. Flip the
            // banner immediately and persist so other tabs see it too.
            MusicPermissionCache.write(.denied)
            withAnimation(.easeInOut(duration: DSMotion.Duration.base)) {
                permissionState = .denied
            }
        }
    }

    // MARK: - Permission status row

    @ViewBuilder
    private var permissionStatusRow: some View {
        HStack(spacing: DSSpace.s4) {
            Image(systemName: permissionIconName)
                .font(.system(size: DSFont.Size.md, weight: .semibold))
                .foregroundStyle(permissionIconColor)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: DSSpace.s0) {
                Text(permissionTitle)
                    .font(.system(size: DSFont.Size.base, weight: .medium))
                if let subtitle = permissionSubtitle {
                    Text(subtitle)
                        .font(.system(size: DSFont.Size.sm))
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
            grantedRecheckControl

        case .denied:
            Button("Open System Settings") {
                MusicPermissionChecker.openAutomationSettings()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .accessibilityLabel("Open System Settings")
            .accessibilityHint("Opens Privacy and Security to grant Apple Music access")
            .accessibilityIdentifier("musicMonitor.openSystemSettingsButton")

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
                .accessibilityLabel("Allow Apple Music access")
                .accessibilityHint("Prompts macOS for automation permission so the current track can be read")
                .accessibilityIdentifier("musicMonitor.allowButton")

                Button("Open Settings") {
                    MusicPermissionChecker.openAutomationSettings()
                }
                .buttonStyle(.borderless)
                .controlSize(.small)
                .foregroundStyle(.secondary)
                .accessibilityLabel("Open System Settings")
                .accessibilityHint("Opens Privacy and Security to grant Apple Music access manually")
                .accessibilityIdentifier("musicMonitor.openSettingsButton")
            }
        }
    }

    @ViewBuilder
    private var grantedRecheckControl: some View {
        if isRechecking {
            ProgressView()
                .progressViewStyle(.circular)
                .controlSize(.small)
                .accessibilityLabel("Rechecking Apple Music access")
                .accessibilityIdentifier("musicMonitor.recheckSpinner")
        } else if recheckConfirmed {
            HStack(spacing: DSSpace.s1) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: DSFont.Size.md, weight: .semibold))
                    .foregroundStyle(.green)
                Text("Checked")
                    .font(.system(size: DSFont.Size.sm))
                    .foregroundStyle(.secondary)
            }
            .transition(.opacity)
            .accessibilityLabel("Recheck complete")
            .accessibilityIdentifier("musicMonitor.recheckConfirmation")
        } else {
            Button("Recheck", action: recheckTapped)
                .buttonStyle(.borderless)
                .controlSize(.small)
                .foregroundStyle(.secondary)
                .accessibilityLabel("Recheck Apple Music access")
                .accessibilityHint("Re-queries macOS for the current automation permission state")
                .accessibilityIdentifier("musicMonitor.recheckButton")
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
        case .unknown: return "macOS will ask once. We only read the track, never play, pause, or change your library."
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

    /// Button-driven recheck. Wraps the off-main probe with a brief spinner
    /// + checkmark so the user gets unambiguous feedback even when the
    /// permission state doesn't change (the common already-granted case).
    private func recheckTapped() {
        guard !isRechecking else { return }
        withAnimation(.easeInOut(duration: DSMotion.Duration.fast)) {
            isRechecking = true
            recheckConfirmed = false
        }
        Task {
            let start = Date()
            // Apple Events probe can take tens of milliseconds — dispatch off
            // the main actor so the spinner can actually animate while we wait.
            let next = await Task.detached(priority: .userInitiated) {
                MusicPermissionChecker.currentState()
            }.value
            // Minimum visible spinner duration so the probe doesn't blink invisibly.
            let elapsed = Date().timeIntervalSince(start)
            let minSpin: TimeInterval = 0.25
            if elapsed < minSpin {
                try? await Task.sleep(nanoseconds: UInt64((minSpin - elapsed) * 1_000_000_000))
            }
            await MainActor.run {
                MusicPermissionCache.write(next)
                withAnimation(.easeInOut(duration: DSMotion.Duration.base)) {
                    permissionState = next
                    isRechecking = false
                    recheckConfirmed = (next == .granted)
                }
                if next == .granted {
                    loadCurrentTrack()
                    AppDelegate.shared?.refreshNowPlaying()
                }
            }
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            await MainActor.run {
                withAnimation(.easeInOut(duration: DSMotion.Duration.base)) {
                    recheckConfirmed = false
                }
            }
        }
    }

    /// Re-queries Apple Music automation permission off the main actor, caches
    /// the result, and reloads the current track if permission is now granted.
    /// The Apple Events probe can take tens of milliseconds — keep it off main.
    private func refreshPermission() {
        Task.detached(priority: .userInitiated) {
            let next = MusicPermissionChecker.currentState()
            await MainActor.run {
                MusicPermissionCache.write(next)
                withAnimation(.easeInOut(duration: DSMotion.Duration.base)) {
                    permissionState = next
                }
                // If we're now granted, try to get the current track again.
                if next == .granted {
                    loadCurrentTrack()
                    // Cached snap first so the UI doesn't briefly clear, then ask
                    // the source for a fresh ScriptingBridge read.
                    AppDelegate.shared?.refreshNowPlaying()
                }
            }
        }
    }

    /// Prompts the user for Apple Music automation permission, animates the
    /// resolution, and pulls the current track on success.
    private func requestPermission() {
        isRequesting = true
        Task {
            let resolved = await MusicPermissionChecker.requestAccess()
            await MainActor.run {
                // Refresh the process-local cache so re-entering the pane within
                // the TTL reflects the just-granted/denied result, not a stale
                // earlier probe.
                MusicPermissionCache.write(resolved)
                withAnimation(.easeInOut(duration: DSMotion.Duration.base)) {
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
            currentIsPaused = appDelegate.currentIsPaused
        }
        fetchArtwork()
    }

    /// Fetches artwork for the current track from `ArtworkService` and stores
    /// the resolved URL. Called on initial load and on every track change.
    private func fetchArtwork() {
        guard let track = currentTrack, let artist = currentArtist else {
            currentArtworkURL = nil
            return
        }
        ArtworkService.shared.fetchTrackLinks(track: track, artist: artist) { links in
            DispatchQueue.main.async {
                currentArtworkURL = links.artworkURL.flatMap(URL.init(string:))
            }
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
        NotificationCenter.default.postEnabled(.trackingSettingChanged, enabled: enabled)
    }
}

// MARK: - Permission cache

/// Process-lifetime cache for the Music automation permission result.
///
/// `MusicPermissionChecker.currentState()` issues an Apple Events probe that can take tens of
/// milliseconds — measurable when switching back to the General settings pane. Cache the result
/// for a short window so re-entering the pane within the same session is instant. The cache is
/// invalidated by `NSApplication.didBecomeActiveNotification` and by explicit refresh calls.
enum MusicPermissionCache {
    nonisolated private static let ttl: TimeInterval = 30
    nonisolated(unsafe) private static var value: MusicPermissionState?
    nonisolated(unsafe) private static var storedAt: Date?

    nonisolated static func read() -> MusicPermissionState? {
        guard let value, let storedAt, Date().timeIntervalSince(storedAt) < ttl else { return nil }
        return value
    }

    nonisolated static func write(_ state: MusicPermissionState) {
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
            NotificationCenter.default.postNowPlaying(
                track: "Anti-Hero",
                artist: "Taylor Swift",
                album: "Midnights"
            )
        }
}

#Preview("Empty") {
    MusicMonitorSettingsView()
        .padding()
        .frame(width: 720)
}
