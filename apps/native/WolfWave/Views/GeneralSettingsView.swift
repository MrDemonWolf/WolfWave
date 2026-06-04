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
/// Laid out with the shared ``SettingsNavRail``: a fixed jump-nav rail on the
/// left and one always-mounted, scrollable column of sections on the right. The
/// old in-pane segmented tabs are gone. Clicking a rail row scrolls its section
/// to the top; scrolling manually moves the highlight. Each sub-view supplies its
/// own section header, so no extra headings are layered on top; the Music anchor
/// sits on the page header so jumping to Music scrolls all the way to the top.
struct GeneralSettingsView: View {

    var configure: (IntegrationDashboardView.Section) -> Void = { _ in }

    @AppStorage(AppConstants.UserDefaults.trackingEnabled)
    private var trackingEnabled = true

    /// Rail selection + scroll target. Drives the highlight and the jump.
    @State private var selected: GeneralSection = .music

    var body: some View {
        SettingsNavRail(
            selection: $selected,
            groups: [SettingsRailGroup(sections: GeneralSection.allCases)],
            accessibilityIDPrefix: "generalNav"
        ) {
            header

            MusicMonitorSettingsView(configure: configure)

            AppVisibilitySettingsView()
                .railSection(GeneralSection.visibility)

            AppearanceSettingsView()
                .railSection(GeneralSection.appearance)

            NotificationsSettingsView()
                .railSection(GeneralSection.notifications)
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
        .railSection(GeneralSection.music)
    }
}

// MARK: - General Section

/// The General tab's jump-nav sections, in display order. `title` labels the
/// rail row; the enum case itself doubles as the `ScrollViewReader` anchor
/// attached to each sub-view via `.railSection(_:)`. The Music anchor sits on the
/// page header so jumping to Music scrolls all the way to the top.
private enum GeneralSection: String, CaseIterable, SettingsRailSection {
    case music
    case visibility
    case appearance
    case notifications

    var title: String {
        switch self {
        case .music: return "Music"
        case .visibility: return "App Visibility"
        case .appearance: return "Appearance"
        case .notifications: return "Notifications"
        }
    }

    var icon: String {
        switch self {
        case .music: return "music.note"
        case .visibility: return "macwindow"
        case .appearance: return "circle.lefthalf.filled"
        case .notifications: return "bell"
        }
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
