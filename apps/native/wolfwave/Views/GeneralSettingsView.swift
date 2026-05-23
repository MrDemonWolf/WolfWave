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
            SectionHeaderWithStatus(
                title: "General",
                subtitle: "Manage how WolfWave tracks your music and where it shows up.",
                statusText: "All systems live",
                statusColor: .green
            )
            .accessibilityIdentifier("generalSettings.header")

            MusicMonitorSettingsView(configure: configure)

            Divider().padding(.vertical, DSSpace.s1)

            AppVisibilitySettingsView()

            Divider().padding(.vertical, DSSpace.s1)

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
