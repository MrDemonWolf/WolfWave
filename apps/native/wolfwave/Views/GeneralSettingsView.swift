//
//  GeneralSettingsView.swift
//  wolfwave
//
//  Created by MrDemonWolf, Inc. on 3/16/26.
//

import SwiftUI

/// General application settings interface — Music Sync (hero now-playing +
/// integrations dashboard) and App Visibility.
struct GeneralSettingsView: View {

    var configure: (IntegrationDashboardView.Section) -> Void = { _ in }

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            // Section header
            HStack(alignment: .center, spacing: 10) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("General")
                        .sectionHeader()

                    Text("Manage how WolfWave tracks your music and where it shows up.")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                StatusChip(text: "All systems live", color: .green)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("General settings. All systems live.")
            .accessibilityIdentifier("generalSettings.header")

            MusicMonitorSettingsView(configure: configure)

            Divider().padding(.vertical, 4)

            AppVisibilitySettingsView()
        }
    }
}

#Preview("General Settings") {
    GeneralSettingsView()
        .padding()
        .frame(width: 760)
        .background(WallpaperBloomBackground())
}

#Preview("Dark Mode") {
    GeneralSettingsView()
        .padding()
        .frame(width: 760)
        .preferredColorScheme(.dark)
        .background(WallpaperBloomBackground())
}
