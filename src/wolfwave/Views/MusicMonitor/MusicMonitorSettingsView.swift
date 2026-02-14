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
/// Also displays a live now-playing preview card styled after Apple Music.
///
/// State:
/// - Uses @AppStorage to sync with UserDefaults
/// - Observes NowPlayingChanged notifications for live track updates
///
/// UI:
/// - Toggle switch for enabling/disabling tracking
/// - Apple Music-styled now-playing preview card
/// - Accessibility labels for screen readers
struct MusicMonitorSettingsView: View {
    // MARK: - User Settings

    /// Whether music tracking is currently enabled.
    @AppStorage(AppConstants.UserDefaults.trackingEnabled)
    private var trackingEnabled = true

    // MARK: - Now Playing State

    @State private var currentTrack: String?
    @State private var currentArtist: String?
    @State private var currentAlbum: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Section Header
            VStack(alignment: .leading, spacing: 6) {
                Text("Music Playback Monitor")
                    .font(.system(size: 17, weight: .semibold))
                    .accessibilityLabel("Music Playback Monitor")

                Text("Automatically detect what's playing in Apple Music and share it with Twitch chat, Discord, and stream overlays.")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            // Toggle Card
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Apple Music Tracking")
                        .font(.system(size: 13, weight: .medium))
                    Text("Detects song changes in real time and updates your integrations")
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                }
                Spacer()
                Toggle("", isOn: $trackingEnabled)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .pointerCursor()
                    .accessibilityLabel("Enable Apple Music monitoring")
                    .accessibilityHint("Toggle to enable or disable Apple Music monitoring")
                    .accessibilityIdentifier("musicTrackingToggle")
                    .onChange(of: trackingEnabled) { _, newValue in
                        notifyTrackingSettingChanged(enabled: newValue)
                    }
            }
            .cardStyle()

            // Now Playing Preview
            nowPlayingCard
                .animation(.easeInOut(duration: 0.25), value: currentTrack)
        }
        .onAppear {
            loadCurrentTrack()
        }
        .onReceive(
            NotificationCenter.default.publisher(
                for: NSNotification.Name(AppConstants.Notifications.nowPlayingChanged)
            )
        ) { notification in
            currentTrack = notification.userInfo?["track"] as? String
            currentArtist = notification.userInfo?["artist"] as? String
            currentAlbum = notification.userInfo?["album"] as? String
        }
    }

    // MARK: - Now Playing Card

    @ViewBuilder
    private var nowPlayingCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack(spacing: 6) {
                Image(systemName: "music.note")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
                Text("Now Playing")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
            }

            if let track = currentTrack {
                // Track info
                HStack(spacing: 12) {
                    // Album art placeholder
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
                // Empty state
                HStack(spacing: 12) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color(nsColor: .separatorColor).opacity(0.3))
                        Image(systemName: "music.note")
                            .font(.system(size: 18, weight: .medium))
                            .foregroundStyle(.tertiary)
                    }
                    .frame(width: 48, height: 48)

                    Text(trackingEnabled ? "No track playing" : "Tracking disabled")
                        .font(.system(size: 13))
                        .foregroundStyle(.tertiary)

                    Spacer()
                }
            }
        }
        .cardStyle()
        .accessibilityElement(children: .combine)
        .accessibilityLabel(nowPlayingAccessibilityLabel)
    }

    // MARK: - Helpers

    /// Accessibility label for the now playing card.
    private var nowPlayingAccessibilityLabel: String {
        if let track = currentTrack {
            var label = "Now playing: \(track)"
            if let artist = currentArtist { label += " by \(artist)" }
            if let album = currentAlbum { label += " on \(album)" }
            return label
        }
        return trackingEnabled ? "No track playing" : "Tracking disabled"
    }

    /// Loads the current track from AppDelegate on view appear.
    private func loadCurrentTrack() {
        guard let appDelegate = AppDelegate.shared else { return }
        // Access the stored track info via the delegate's public accessors
        currentTrack = appDelegate.currentSong
        currentArtist = appDelegate.currentArtist
        currentAlbum = appDelegate.currentAlbum
    }

    /// Posts a notification when music tracking is toggled.
    private func notifyTrackingSettingChanged(enabled: Bool) {
        NotificationCenter.default.post(
            name: NSNotification.Name(AppConstants.Notifications.trackingSettingChanged),
            object: nil,
            userInfo: ["enabled": enabled]
        )
    }
}

// MARK: - Preview

#Preview {
    MusicMonitorSettingsView()
        .padding()
}
