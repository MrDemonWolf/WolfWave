//
//  GeneralSettingsView.swift
//  wolfwave
//
//  Created by MrDemonWolf, Inc. on 3/16/26.
//

import SwiftUI

/// General application settings interface.
///
/// Provides controls for:
/// - Music Playback Monitor (tracking Apple Music)
/// - App Visibility (dock and menu bar presence)
///
/// These are the most common settings users will need to adjust for basic
/// functionality of WolfWave.
struct GeneralSettingsView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            // Section Header
            VStack(alignment: .leading, spacing: 6) {
                Text("General")
                    .sectionHeader()

                Text("Manage how WolfWave tracks your music and where it shows up.")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("General settings. Manage how WolfWave tracks your music and where it shows up.")

            // Music Monitor
            MusicMonitorSettingsView()

            Divider()
                .padding(.vertical, 4)

            // App Visibility
            AppVisibilitySettingsView()
        }
    }
}

// MARK: - Preview

#Preview("General Settings") {
    GeneralSettingsView()
        .padding()
        .frame(width: 700)
}
#Preview("With Current Track Playing") {
    let view = GeneralSettingsView()
    view
        .padding()
        .frame(width: 700)
        .onAppear {
            NotificationCenter.default.post(
                name: NSNotification.Name(AppConstants.Notifications.nowPlayingChanged),
                object: nil,
                userInfo: [
                    "track": "Starboy",
                    "artist": "The Weeknd feat. Daft Punk",
                    "album": "Starboy"
                ]
            )
        }
}

#Preview("Dark Mode") {
    GeneralSettingsView()
        .padding()
        .frame(width: 700)
        .preferredColorScheme(.dark)
}

