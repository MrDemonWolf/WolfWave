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
/// - Menu bar display with current song/artist/album
/// - Twitch chat bot command responses (!song, !last)
/// - External WebSocket endpoints (if configured)
///
/// State:
/// - Uses @AppStorage to sync with UserDefaults
/// - Changes are posted via NotificationCenter for app-wide updates
///
/// UI:
/// - Simple toggle switch
/// - Descriptive explanation of functionality
/// - Accessibility labels for screen readers
struct MusicMonitorSettingsView: View {
    // MARK: - User Settings
    
    /// Whether music tracking is currently enabled.
    ///
    /// When toggled:
    /// 1. Starts or stops MusicPlaybackMonitor
    /// 2. Posts trackingSettingChanged notification
    /// 3. Updates menu bar display ("Tracking disabled" or current song)
    @AppStorage(AppConstants.UserDefaults.trackingEnabled)
    private var trackingEnabled = true
    
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
        }
    }
    
    // MARK: - Helpers
    
    /// Posts a notification when music tracking is toggled.
    ///
    /// The AppDelegate listens for this notification and starts/stops the MusicPlaybackMonitor.
    ///
    /// - Parameter enabled: Whether tracking is now enabled.
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
