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
    @AppStorage("trackingEnabled")
    private var trackingEnabled = true
    
    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Image(systemName: "music.note")
                        .font(.title3)
                    Text("Music Playback Monitor")
                        .font(.title2)
                        .fontWeight(.semibold)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Music Playback Monitor")
                
                Text("Monitor your Apple Music playback to display in the menu bar and share with external services like Twitch or custom WebSocket endpoints.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            
            Divider()
            
            HStack {
                Text("Enable Apple Music monitoring")
                    .font(.body)
                Spacer()
                Toggle("", isOn: $trackingEnabled)
                    .labelsHidden()
                    .toggleStyle(.switch)
                        .accessibilityLabel("Enable Apple Music monitoring")
                        .accessibilityHint("Toggle to enable or disable Apple Music monitoring")
                        .accessibilityIdentifier("musicTrackingToggle")
                    .onChange(of: trackingEnabled) { _, newValue in
                        notifyTrackingSettingChanged(enabled: newValue)
                    }
            }
            .padding(12)
            .background(Color(nsColor: .controlBackgroundColor))
            .cornerRadius(8)
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
