//
//  MusicMonitorSettingsView.swift
//  wolfwave
//
//  Created by MrDemonWolf, Inc. on 1/13/26.
//

import SwiftUI

/// Music playback monitoring settings interface.
struct MusicMonitorSettingsView: View {
    // MARK: - User Settings
    
    /// Whether music tracking is currently enabled
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
    
    private func notifyTrackingSettingChanged(enabled: Bool) {
        NotificationCenter.default.post(
            name: NSNotification.Name("TrackingSettingChanged"),
            object: nil,
            userInfo: ["enabled": enabled]
        )
    }
}
