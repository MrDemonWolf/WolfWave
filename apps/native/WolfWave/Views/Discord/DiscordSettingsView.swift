//
//  DiscordSettingsView.swift
//  WolfWave
//
//  Created by Nathanial Henniges on 2026-02-07.
//  Copyright © 2026 MrDemonWolf, Inc. All rights reserved.
//

import AppKit
import SwiftUI

/// Settings for Discord Rich Presence integration.
///
/// Four cards, top to bottom:
///   1. **Connection** — enable toggle, connection status chip, test button.
///   2. **Buttons** — per-button toggle + label override + URL preview.
///   3. **Preview** — mock Discord activity card driven by current settings.
struct DiscordSettingsView: View {
    // MARK: - User Settings

    @AppStorage(AppConstants.UserDefaults.discordPresenceEnabled)
    private var presenceEnabled = false

    @AppStorage(AppConstants.UserDefaults.discordButtonsEnabled)
    private var buttonsEnabled = true

    @AppStorage(AppConstants.UserDefaults.discordButton1Enabled)
    private var button1Enabled = true

    @AppStorage(AppConstants.UserDefaults.discordButton2Enabled)
    private var button2Enabled = true

    @AppStorage(AppConstants.UserDefaults.discordPlaylistEnabled)
    private var playlistEnabled = false

    @AppStorage(AppConstants.UserDefaults.discordPlaylistShowName)
    private var playlistShowName = true

    @AppStorage(AppConstants.UserDefaults.discordPlaylistStyle)
    private var playlistStyle: DiscordPlaylistStyle = .default

    @AppStorage(AppConstants.UserDefaults.discordShowIdleStatus)
    private var showIdleStatus = false

    @AppStorage(AppConstants.UserDefaults.discordClearWhilePaused)
    private var clearWhilePaused = false

    // MARK: - State

    @State private var connectionState: DiscordRPCService.ConnectionState = .disconnected
    @State private var hasClientID = false
    @State private var nowPlaying: NowPlayingSnapshot = .sample
    /// What the preview card represents, driven by live playback notifications.
    /// Seeded from Apple Music's running state on appear, then kept in sync by
    /// `.nowPlayingChanged` (track present / paused / nil) and the Discord
    /// connection state.
    @State private var playbackMode: DiscordPreviewCard.Mode = .stopped
    @State private var settingsChangedTask: Task<Void, Never>?

    // MARK: - Body

    var body: some View {
        VStack(alignment: .leading, spacing: DSSpace.s6) {
            connectionSection
            if presenceEnabled && hasClientID {
                buttonsSection
                playlistSection
                behaviorSection
                previewSection
            }
        }
        .animation(.easeInOut(duration: DSMotion.Duration.base), value: presenceEnabled)
        .animation(.easeInOut(duration: DSMotion.Duration.base), value: playlistEnabled)
        .onAppear {
            hasClientID = DiscordRPCService.resolveClientID() != nil
            refreshConnectionState()
            // Seed an honest empty state immediately, then ask the active source
            // to rebroadcast so a live/paused track populates within a poll tick.
            playbackMode = isAppleMusicRunning() ? .stopped : .musicClosed
            AppDelegate.shared?.refreshNowPlaying()
        }
        .onReceive(
            NotificationCenter.default.publisher(
                for: Notification.Name.discordStateChanged
            )
        ) { notification in
            if let rawValue = notification.stateString {
                withAnimation(.easeInOut(duration: DSMotion.Duration.base)) {
                    switch rawValue {
                    case "connected":   connectionState = .connected
                    case "connecting":  connectionState = .connecting
                    default:            connectionState = .disconnected
                    }
                }
            }
        }
        .onReceive(
            NotificationCenter.default.publisher(
                for: Notification.Name.nowPlayingChanged
            )
        ) { notification in
            updateNowPlaying(from: notification)
        }
        .onChange(of: buttonsEnabled) { _, _ in scheduleSettingsResend() }
        .onChange(of: button1Enabled) { _, _ in scheduleSettingsResend() }
        .onChange(of: button2Enabled) { _, _ in scheduleSettingsResend() }
        .onChange(of: playlistEnabled) { _, _ in scheduleSettingsResend() }
        .onChange(of: playlistShowName) { _, _ in scheduleSettingsResend() }
        .onChange(of: playlistStyle) { _, _ in scheduleSettingsResend() }
    }

    // MARK: - Sections

    private var connectionSection: some View {
        VStack(alignment: .leading, spacing: DSSpace.s6) {
            SectionHeaderWithStatus(
                title: "Discord Status",
                subtitle: "Show your music on your Discord profile.",
                statusText: statusChipText,
                statusColor: statusChipColor
            )

            ToggleSettingRow(
                title: "Show on Discord",
                subtitle: "Displays the song and cover art on your profile",
                isOn: $presenceEnabled,
                isDisabled: !hasClientID,
                accessibilityLabel: "Enable Discord Status",
                accessibilityIdentifier: "discordPresenceToggle",
                accessibilityHint: "Toggle to enable or disable Discord Status",
                onChange: { newValue in
                    notifyPresenceSettingChanged(enabled: newValue)
                }
            )
            .cardStyle()

            if presenceEnabled && hasClientID {
                HStack(spacing: DSSpace.s3) {
                    ConnectionTestButton(
                        label: "Check Discord",
                        icon: "antenna.radiowaves.left.and.right"
                    ) { completion in
                        guard let service = AppDelegate.shared?.discordService else {
                            completion(false)
                            return
                        }
                        Task { @MainActor in
                            let success = await service.testConnection()
                            completion(success)
                        }
                    }
                    .help("Checks if Discord is open and ready.")
                    .accessibilityLabel("Test Discord connection")
                    .accessibilityHint("Checks if Discord is open and ready to receive status updates")
                    .accessibilityIdentifier("discordTestConnectionButton")

                    Spacer()
                }
                .transition(.opacity)
            }

            #if DEBUG
            if !hasClientID {
                CalloutBanner(
                    "Set DISCORD_CLIENT_ID in Config.xcconfig to enable this feature.",
                    style: .warning
                )
            }
            #endif
        }
    }

    private var buttonsSection: some View {
        VStack(alignment: .leading, spacing: DSSpace.s4) {
            SectionHeaderWithStatus(
                title: "Profile Buttons",
                subtitle: "Up to two buttons appear under your song on Discord.",
                statusText: buttonCountText,
                statusColor: .secondary
            )

            VStack(alignment: .leading, spacing: DSSpace.s6) {
                ToggleSettingRow(
                    title: "Show buttons",
                    subtitle: "Display action buttons on your Discord profile.",
                    isOn: $buttonsEnabled,
                    accessibilityLabel: "Show Discord profile buttons",
                    accessibilityIdentifier: "discordButtonsMasterToggle"
                )

                if buttonsEnabled {
                    Divider()

                    DiscordButtonConfigRow(
                        title: "Apple Music link",
                        resolvedURL: nowPlaying.appleMusicURL,
                        accessibilityPrefix: "discordButton1",
                        isEnabled: $button1Enabled
                    )

                    Divider()

                    DiscordButtonConfigRow(
                        title: "Cross-service link (song.link)",
                        resolvedURL: nowPlaying.songLinkURL,
                        accessibilityPrefix: "discordButton2",
                        isEnabled: $button2Enabled
                    )
                }
            }
            .cardStyle()
            .animation(.easeInOut(duration: DSMotion.Duration.base), value: buttonsEnabled)
        }
        .transition(.opacity)
    }

    private var playlistSection: some View {
        VStack(alignment: .leading, spacing: DSSpace.s4) {
            SectionHeaderWithStatus(
                title: "Playlist",
                subtitle: "Show the Apple Music playlist you're listening from.",
                statusText: playlistEnabled ? "On" : "Off",
                statusColor: playlistEnabled ? .green : .secondary
            )

            VStack(alignment: .leading, spacing: DSSpace.s6) {
                ToggleSettingRow(
                    title: "Show playlist",
                    subtitle: "Adds the current playlist to your Discord status",
                    isOn: $playlistEnabled,
                    accessibilityLabel: "Show playlist on Discord",
                    accessibilityIdentifier: "discordPlaylistToggle",
                    accessibilityHint: "Toggle to show or hide the current playlist"
                )

                if playlistEnabled {
                    Divider()

                    HStack {
                        VStack(alignment: .leading, spacing: DSSpace.s0) {
                            Text("Display style")
                                .font(.system(size: DSFont.Size.base, weight: .medium))
                            Text(playlistStyleSubtitle)
                                .font(.system(size: DSFont.Size.sm))
                                .foregroundStyle(.tertiary)
                        }
                        Spacer()
                        Picker("Display style", selection: $playlistStyle) {
                            Text("Artist + playlist line").tag(DiscordPlaylistStyle.artistLine)
                            Text("Playlist tooltip").tag(DiscordPlaylistStyle.iconTooltip)
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                        .fixedSize()
                        .accessibilityIdentifier("discordPlaylistStylePicker")
                    }

                    Divider()

                    ToggleSettingRow(
                        title: "Show playlist name",
                        subtitle: "Off shows a generic label so the name stays private",
                        isOn: $playlistShowName,
                        accessibilityLabel: "Show playlist name",
                        accessibilityIdentifier: "discordPlaylistShowNameToggle",
                        accessibilityHint: "Toggle to reveal or hide the playlist's name"
                    )
                }
            }
            .cardStyle()
        }
        .transition(.opacity)
    }

    private var behaviorSection: some View {
        VStack(alignment: .leading, spacing: DSSpace.s4) {
            SectionHeaderWithStatus(
                title: "When not playing",
                subtitle: "Control what your profile shows when music stops or pauses.",
                statusText: showIdleStatus ? "Idle shown" : "Cleared",
                statusColor: showIdleStatus ? .green : .secondary
            )

            VStack(alignment: .leading, spacing: DSSpace.s6) {
                ToggleSettingRow(
                    title: "Show idle status",
                    subtitle: "Keep \"Listening to WolfWave \u{00B7} Idle\" on your profile instead of clearing it",
                    isOn: $showIdleStatus,
                    accessibilityLabel: "Show idle status on Discord",
                    accessibilityIdentifier: "discordIdleStatusToggle",
                    accessibilityHint: "Toggle to keep an idle activity on your profile when nothing is playing"
                )

                Divider()

                ToggleSettingRow(
                    title: "Hide track while paused",
                    subtitle: "Clear the track when you pause, rather than leaving it on your profile",
                    isOn: $clearWhilePaused,
                    accessibilityLabel: "Hide track while paused",
                    accessibilityIdentifier: "discordClearWhilePausedToggle",
                    accessibilityHint: "Toggle to clear your Discord profile while playback is paused"
                )
            }
            .cardStyle()
        }
        .transition(.opacity)
    }

    private var previewSection: some View {
        VStack(alignment: .leading, spacing: DSSpace.s4) {
            SectionHeaderWithStatus(
                title: "Preview",
                subtitle: "How your profile will look on Discord.",
                statusText: previewStatusText,
                statusColor: previewStatusColor
            )

            DiscordPreviewCard(
                mode: previewMode,
                trackTitle: nowPlaying.track,
                artist: previewStateLine,
                album: nowPlaying.album,
                artworkURL: nowPlaying.artworkURL.flatMap(URL.init(string:)),
                button1: previewButton(
                    enabled: button1Enabled,
                    defaultLabel: AppConstants.Discord.defaultButton1Label,
                    url: nowPlaying.appleMusicURL ?? "https://music.apple.com/"
                ),
                button2: previewButton(
                    enabled: button2Enabled,
                    defaultLabel: AppConstants.Discord.defaultButton2Label,
                    url: nowPlaying.songLinkURL ?? "https://song.link/"
                ),
                playlistTooltip: previewPlaylistTooltip
            )
            .padding(.horizontal, DSSpace.s1)

            if previewMode.showsTrack, let tooltip = previewPlaylistTooltip {
                HStack(spacing: DSSpace.s1h) {
                    Image(systemName: "info.circle")
                    Text("Hover the app icon on Discord to see: \(tooltip)")
                }
                .font(.system(size: DSFont.Size.sm))
                .foregroundStyle(.secondary)
                .padding(.horizontal, DSSpace.s1)
            }
        }
        .transition(.opacity)
    }

    // MARK: - Preview State

    /// The mode the preview card renders. A disconnected Discord client wins
    /// over playback state — there's no profile to show music on. Otherwise the
    /// live playback mode is mapped through the two behavior toggles: a paused
    /// track can be hidden, and any "no track" state can fall back to the opt-in
    /// idle activity instead of an empty card.
    private var previewMode: DiscordPreviewCard.Mode {
        if connectionState == .disconnected { return .discordOffline }
        switch playbackMode {
        case .playing:
            return .playing
        case .paused:
            return clearWhilePaused ? clearedPreviewMode(whenMusicClosed: false) : .paused
        case .stopped:
            return clearedPreviewMode(whenMusicClosed: false)
        case .musicClosed:
            return clearedPreviewMode(whenMusicClosed: true)
        case .discordOffline, .idleActivity:
            return playbackMode
        }
    }

    /// What the profile shows with no track: the opt-in idle activity, or the
    /// matching empty state.
    private func clearedPreviewMode(whenMusicClosed: Bool) -> DiscordPreviewCard.Mode {
        if showIdleStatus { return .idleActivity }
        return whenMusicClosed ? .musicClosed : .stopped
    }

    private var previewStatusText: String {
        switch previewMode {
        case .playing:        return "Live"
        case .paused:         return "Paused"
        case .stopped:        return "Idle"
        case .musicClosed:    return "Idle"
        case .idleActivity:   return "Idle"
        case .discordOffline: return "Offline"
        }
    }

    private var previewStatusColor: Color {
        switch previewMode {
        case .playing:        return .green
        case .paused:         return .orange
        case .stopped,
             .musicClosed,
             .idleActivity,
             .discordOffline: return .secondary
        }
    }

    // MARK: - Playlist Preview Helpers

    /// Resolves the playlist for the preview using the same logic as the live presence.
    private var playlistDisplay: DiscordRPCService.PlaylistDisplay? {
        DiscordRPCService.resolvePlaylistDisplay(
            playlist: nowPlaying.playlist,
            album: nowPlaying.album,
            defaults: .standard
        )
    }

    /// The activity state line (line 2) as the live presence would render it.
    private var previewStateLine: String {
        DiscordRPCService.stateLine(
            artist: nowPlaying.artist,
            playlist: playlistDisplay,
            style: playlistStyle
        )
    }

    /// The small-icon tooltip text, or nil when the playlist isn't shown there.
    private var previewPlaylistTooltip: String? {
        guard playlistStyle == .iconTooltip, playlistDisplay != nil else { return nil }
        return DiscordRPCService.smallText(playlist: playlistDisplay, style: playlistStyle)
    }

    /// Caption describing where the chosen style surfaces the playlist.
    private var playlistStyleSubtitle: String {
        switch playlistStyle {
        case .artistLine:  return "Shown next to the artist"
        case .iconTooltip: return "Shown when hovering the app icon"
        }
    }

    // MARK: - Helpers

    private var statusChipText: String {
        switch connectionState {
        case .connected:    return "Connected"
        case .connecting:   return "Connecting"
        case .disconnected: return presenceEnabled ? "Discord not running" : "Disconnected"
        }
    }

    private var statusChipColor: Color {
        switch connectionState {
        case .connected:    return .green
        case .connecting:   return .orange
        case .disconnected: return .gray
        }
    }

    private var buttonCountText: String {
        guard buttonsEnabled else { return "Hidden" }
        let count = (button1Enabled ? 1 : 0) + (button2Enabled ? 1 : 0)
        return "\(count) of \(AppConstants.Discord.maxButtons) shown"
    }

    private func previewButton(
        enabled: Bool,
        defaultLabel: String,
        url: String
    ) -> DiscordPreviewCard.PreviewButton? {
        guard buttonsEnabled, enabled else { return nil }
        return .init(label: defaultLabel, url: url)
    }

    private func refreshConnectionState() {
        guard let service = AppDelegate.shared?.discordService else {
            connectionState = .disconnected
            return
        }
        Task { @MainActor in
            connectionState = await service.state
        }
    }

    private func updateNowPlaying(from notification: Notification) {
        let payload = notification.nowPlaying
        guard let track = payload.track, let artist = payload.artist else {
            // No track in the payload: playback stopped, or Apple Music quit.
            // Mirror the live presence, which clears the profile in both cases.
            withAnimation(.easeInOut(duration: DSMotion.Duration.base)) {
                playbackMode = isAppleMusicRunning() ? .stopped : .musicClosed
            }
            return
        }
        let album = payload.album ?? ""
        let playlist = payload.playlist ?? ""
        let links = ArtworkService.shared.cachedTrackLinks(track: track, artist: artist)
        nowPlaying = NowPlayingSnapshot(
            track: track,
            artist: artist,
            album: album,
            playlist: playlist,
            artworkURL: links.artworkURL,
            appleMusicURL: links.trackViewURL,
            songLinkURL: links.songLinkURL,
            isLive: true
        )
        withAnimation(.easeInOut(duration: DSMotion.Duration.base)) {
            playbackMode = payload.isPaused ? .paused : .playing
        }
    }

    /// `true` when Apple Music is currently running, used to tell a stopped
    /// track apart from a quit app for the preview's empty state.
    private func isAppleMusicRunning() -> Bool {
        NSWorkspace.shared.runningApplications.contains {
            $0.bundleIdentifier == "com.apple.Music"
        }
    }

    private func notifyPresenceSettingChanged(enabled: Bool) {
        NotificationCenter.default.postEnabled(.discordPresenceChanged, enabled: enabled)
    }

    /// Debounce notification by 300ms so rapid typing/toggling doesn't spam the socket.
    private func scheduleSettingsResend() {
        settingsChangedTask?.cancel()
        settingsChangedTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            NotificationCenter.default.post(
                name: Notification.Name.discordPresenceSettingsChanged,
                object: nil
            )
        }
    }
}

// MARK: - NowPlayingSnapshot

/// Lightweight view-local snapshot of the currently playing track for previewing.
private struct NowPlayingSnapshot {
    let track: String
    let artist: String
    let album: String
    let playlist: String
    let artworkURL: String?
    let appleMusicURL: String?
    let songLinkURL: String?
    let isLive: Bool

    static let sample = NowPlayingSnapshot(
        track: "Smooth Operator",
        artist: "Sade",
        album: "Diamond Life",
        playlist: "Chill Saturday",
        artworkURL: nil,
        appleMusicURL: nil,
        songLinkURL: nil,
        isLive: false
    )
}

// MARK: - Preview

#Preview("Disconnected") {
    DiscordSettingsView()
        .padding()
        .frame(width: 600)
}

#Preview("Connected") {
    let view = DiscordSettingsView()
    return view
        .padding()
        .frame(width: 600)
        .onAppear {
            NotificationCenter.default.postDiscordState("connected")
        }
}
