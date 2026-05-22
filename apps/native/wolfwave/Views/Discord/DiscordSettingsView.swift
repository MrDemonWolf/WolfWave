//
//  DiscordSettingsView.swift
//  wolfwave
//
//  Created by MrDemonWolf, Inc. on 2/7/26.
//

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

    @AppStorage(AppConstants.UserDefaults.discordButton1Enabled)
    private var button1Enabled = true

    @AppStorage(AppConstants.UserDefaults.discordButton1Label)
    private var button1Label = ""

    @AppStorage(AppConstants.UserDefaults.discordButton2Enabled)
    private var button2Enabled = true

    @AppStorage(AppConstants.UserDefaults.discordButton2Label)
    private var button2Label = ""

    @AppStorage(AppConstants.UserDefaults.discordPlaylistEnabled)
    private var playlistEnabled = false

    @AppStorage(AppConstants.UserDefaults.discordPlaylistShowName)
    private var playlistShowName = true

    @AppStorage(AppConstants.UserDefaults.discordPlaylistStyle)
    private var playlistStyle: DiscordPlaylistStyle = .default

    // MARK: - State

    @State private var connectionState: DiscordRPCService.ConnectionState = .disconnected
    @State private var hasClientID = false
    @State private var nowPlaying: NowPlayingSnapshot = .sample
    @State private var settingsChangedWork: DispatchWorkItem?

    // MARK: - Body

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            connectionSection
            if presenceEnabled && hasClientID {
                buttonsSection
                playlistSection
                previewSection
            }
        }
        .animation(.easeInOut(duration: 0.2), value: presenceEnabled)
        .animation(.easeInOut(duration: 0.2), value: playlistEnabled)
        .onAppear {
            hasClientID = DiscordRPCService.resolveClientID() != nil
            refreshConnectionState()
            refreshNowPlaying()
        }
        .onReceive(
            NotificationCenter.default.publisher(
                for: NSNotification.Name(AppConstants.Notifications.discordStateChanged)
            )
        ) { notification in
            if let rawValue = notification.userInfo?["state"] as? String {
                withAnimation(.easeInOut(duration: 0.2)) {
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
                for: NSNotification.Name(AppConstants.Notifications.nowPlayingChanged)
            )
        ) { notification in
            updateNowPlaying(from: notification.userInfo)
        }
        .onChange(of: button1Enabled) { _, _ in scheduleSettingsResend() }
        .onChange(of: button1Label) { _, newValue in
            let max = AppConstants.Discord.buttonLabelMaxLength
            if newValue.count > max {
                button1Label = String(newValue.prefix(max))
                return
            }
            scheduleSettingsResend()
        }
        .onChange(of: button2Enabled) { _, _ in scheduleSettingsResend() }
        .onChange(of: button2Label) { _, newValue in
            let max = AppConstants.Discord.buttonLabelMaxLength
            if newValue.count > max {
                button2Label = String(newValue.prefix(max))
                return
            }
            scheduleSettingsResend()
        }
        .onChange(of: playlistEnabled) { _, _ in scheduleSettingsResend() }
        .onChange(of: playlistShowName) { _, _ in scheduleSettingsResend() }
        .onChange(of: playlistStyle) { _, _ in scheduleSettingsResend() }
    }

    // MARK: - Sections

    private var connectionSection: some View {
        VStack(alignment: .leading, spacing: 16) {
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
                HStack(spacing: 10) {
                    ConnectionTestButton(
                        label: "Check Discord",
                        icon: "antenna.radiowaves.left.and.right"
                    ) { completion in
                        guard let service = AppDelegate.shared?.discordService else {
                            completion(false)
                            return
                        }
                        service.testConnection(completion: completion)
                    }
                    .help("Checks if Discord is open and ready.")
                    .accessibilityLabel("Test Discord connection")
                    .accessibilityHint("Checks if Discord is open and ready to receive status updates")
                    .accessibilityIdentifier("discordTestConnectionButton")

                    Spacer()
                }
                .transition(.opacity)
            }

            if !hasClientID {
                ConfigRequiredBanner(message: "Set DISCORD_CLIENT_ID in Config.xcconfig to enable this feature.")
            }
        }
    }

    private var buttonsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeaderWithStatus(
                title: "Profile Buttons",
                subtitle: "Up to two buttons appear under your song on Discord.",
                statusText: buttonCountText,
                statusColor: .secondary
            )

            VStack(alignment: .leading, spacing: 16) {
                DiscordButtonConfigRow(
                    title: "Apple Music link",
                    defaultLabel: AppConstants.Discord.defaultButton1Label,
                    resolvedURL: nowPlaying.appleMusicURL,
                    accessibilityPrefix: "discordButton1",
                    isEnabled: $button1Enabled,
                    customLabel: $button1Label
                )

                Divider()

                DiscordButtonConfigRow(
                    title: "Cross-service link (song.link)",
                    defaultLabel: AppConstants.Discord.defaultButton2Label,
                    resolvedURL: nowPlaying.songLinkURL,
                    accessibilityPrefix: "discordButton2",
                    isEnabled: $button2Enabled,
                    customLabel: $button2Label
                )
            }
            .cardStyle()
        }
        .transition(.opacity)
    }

    private var playlistSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeaderWithStatus(
                title: "Playlist",
                subtitle: "Show the Apple Music playlist you're listening from.",
                statusText: playlistEnabled ? "On" : "Off",
                statusColor: playlistEnabled ? .green : .secondary
            )

            VStack(alignment: .leading, spacing: 16) {
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
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Display style")
                                .font(.system(size: 13, weight: .medium))
                            Text(playlistStyleSubtitle)
                                .font(.system(size: 11))
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

    private var previewSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeaderWithStatus(
                title: "Preview",
                subtitle: "How your profile will look on Discord.",
                statusText: nowPlaying.isLive ? "Live" : "Sample",
                statusColor: nowPlaying.isLive ? .green : .secondary
            )

            DiscordPreviewCard(
                trackTitle: nowPlaying.track,
                artist: previewStateLine,
                album: nowPlaying.album,
                artworkURL: nowPlaying.artworkURL.flatMap(URL.init(string:)),
                button1: previewButton(
                    enabled: button1Enabled,
                    label: button1Label,
                    defaultLabel: AppConstants.Discord.defaultButton1Label,
                    url: nowPlaying.appleMusicURL ?? "https://music.apple.com/"
                ),
                button2: previewButton(
                    enabled: button2Enabled,
                    label: button2Label,
                    defaultLabel: AppConstants.Discord.defaultButton2Label,
                    url: nowPlaying.songLinkURL ?? "https://song.link/"
                ),
                playlistTooltip: previewPlaylistTooltip
            )
            .padding(.horizontal, 4)

            if let tooltip = previewPlaylistTooltip {
                HStack(spacing: 6) {
                    Image(systemName: "info.circle")
                    Text("Hover the app icon on Discord to see: \(tooltip)")
                }
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 4)
            }
        }
        .transition(.opacity)
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
        let count = (button1Enabled ? 1 : 0) + (button2Enabled ? 1 : 0)
        return "\(count) of \(AppConstants.Discord.maxButtons) shown"
    }

    private func previewButton(
        enabled: Bool,
        label: String,
        defaultLabel: String,
        url: String
    ) -> DiscordPreviewCard.PreviewButton? {
        guard enabled else { return nil }
        let trimmed = label.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolved = trimmed.isEmpty ? defaultLabel : trimmed
        let truncated = String(resolved.prefix(AppConstants.Discord.buttonLabelMaxLength))
        guard !truncated.isEmpty else { return nil }
        return .init(label: truncated, url: url)
    }

    private func refreshConnectionState() {
        if let appDelegate = AppDelegate.shared {
            connectionState = appDelegate.discordService?.state ?? .disconnected
        }
    }

    private func refreshNowPlaying() {
        // Best-effort: try to seed live data via the artwork cache if a track is active.
        // The nowPlayingChanged notification takes over once a track changes.
    }

    private func updateNowPlaying(from userInfo: [AnyHashable: Any]?) {
        guard let info = userInfo,
              let track = info["track"] as? String,
              let artist = info["artist"] as? String else { return }
        let album = (info["album"] as? String) ?? ""
        let playlist = (info["playlist"] as? String) ?? ""
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
    }

    private func notifyPresenceSettingChanged(enabled: Bool) {
        NotificationCenter.default.post(
            name: NSNotification.Name(AppConstants.Notifications.discordPresenceChanged),
            object: nil,
            userInfo: ["enabled": enabled]
        )
    }

    /// Debounce notification by 300ms so rapid typing/toggling doesn't spam the socket.
    private func scheduleSettingsResend() {
        settingsChangedWork?.cancel()
        let work = DispatchWorkItem {
            NotificationCenter.default.post(
                name: NSNotification.Name(AppConstants.Notifications.discordPresenceSettingsChanged),
                object: nil
            )
        }
        settingsChangedWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: work)
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
            NotificationCenter.default.post(
                name: NSNotification.Name(AppConstants.Notifications.discordStateChanged),
                object: nil,
                userInfo: ["state": "connected"]
            )
        }
}
