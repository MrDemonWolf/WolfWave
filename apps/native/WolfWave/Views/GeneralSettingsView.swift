//
//  GeneralSettingsView.swift
//  WolfWave
//
//  Created by Nathanial Henniges on 2026-03-18.
//  Copyright © 2026 MrDemonWolf, Inc. All rights reserved.
//

import SwiftUI

/// General application settings interface: Music Sync (hero now-playing +
/// integrations dashboard), App Visibility, Appearance, and Notifications.
///
/// A single scrollable column of sections, top to bottom. Each sub-view supplies
/// its own section header, so no extra headings are layered on top. (This pane
/// has no jump-nav rail; it is short enough to scroll directly.)
struct GeneralSettingsView: View {

    var configure: (IntegrationDashboardView.Section) -> Void = { _ in }

    @AppStorage(AppConstants.UserDefaults.trackingEnabled)
    private var trackingEnabled = true

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppConstants.SettingsUI.sectionSpacing) {
                header

                MusicMonitorSettingsView(configure: configure)

                AppVisibilitySettingsView()

                AppearanceSettingsView()

                NotificationsSettingsView()
            }
            .frame(maxWidth: AppConstants.SettingsUI.maxContentWidth, alignment: .topLeading)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.horizontal, AppConstants.SettingsUI.contentPaddingH)
            .padding(.vertical, AppConstants.SettingsUI.contentPaddingV)
        }
    }

    // MARK: - Header

    private var header: some View {
        SectionHeaderWithStatus(
            title: "General",
            subtitle: "Manage how WolfWave tracks your music and where it shows up.",
            statusText: trackingEnabled ? "Music on" : "Music off",
            statusColor: trackingEnabled ? .green : .gray
        )
        .accessibilityIdentifier("generalSettings.header")
    }
}

#Preview("General Settings") {
    GeneralSettingsView()
        .frame(width: 820, height: 600)
        .background(Color(nsColor: .windowBackgroundColor))
}

#Preview("Dark Mode") {
    GeneralSettingsView()
        .frame(width: 820, height: 600)
        .preferredColorScheme(.dark)
        .background(Color(nsColor: .windowBackgroundColor))
}
