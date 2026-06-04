//
//  GeneralSettingsView.swift
//  WolfWave
//
//  Created by Nathanial Henniges on 2026-03-18.
//  Copyright © 2026 MrDemonWolf, Inc. All rights reserved.
//

import SwiftUI

/// General application settings interface: Music Sync (hero now-playing +
/// integrations dashboard) and App Visibility.
struct GeneralSettingsView: View {

    var configure: (IntegrationDashboardView.Section) -> Void = { _ in }

    @AppStorage(AppConstants.UserDefaults.trackingEnabled)
    private var trackingEnabled = true

    @State private var selectedTab: GeneralTab = .music

    /// In-pane sections, surfaced as a segmented control so Music, app
    /// appearance, and notifications each get a focused tab instead of one long
    /// stacked scroll.
    private enum GeneralTab: String, CaseIterable, Identifiable {
        case music = "Music"
        case lookDock = "Look & Dock"
        case notifications = "Notifications"
        var id: String { rawValue }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DSSpace.s8) {
            SectionHeaderWithStatus(
                title: "General",
                subtitle: "Manage how WolfWave tracks your music and where it shows up.",
                statusText: trackingEnabled ? "Music on" : "Music off",
                statusColor: trackingEnabled ? .green : .gray
            )
            .accessibilityIdentifier("generalSettings.header")

            Picker("Section", selection: $selectedTab) {
                ForEach(GeneralTab.allCases) { tab in
                    Text(tab.rawValue).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .accessibilityIdentifier("generalTabPicker")

            tabContent
        }
    }

    /// The settings shown for the selected tab. Each is the same sub-view the
    /// page rendered before; only their grouping into tabs is new.
    @ViewBuilder
    private var tabContent: some View {
        switch selectedTab {
        case .music:
            MusicMonitorSettingsView(configure: configure)
        case .lookDock:
            AppVisibilitySettingsView()
            AppearanceSettingsView()
        case .notifications:
            NotificationsSettingsView()
        }
    }
}

#Preview("General Settings") {
    GeneralSettingsView()
        .padding()
        .frame(width: 760)
        .background(Color(nsColor: .underPageBackgroundColor))
}

#Preview("Dark Mode") {
    GeneralSettingsView()
        .padding()
        .frame(width: 760)
        .preferredColorScheme(.dark)
        .background(Color(nsColor: .underPageBackgroundColor))
}
