//
//  GeneralSettingsView.swift
//  WolfWave
//
//  Created by Nathanial Henniges on 2026-03-18.
//  Copyright © 2026 MrDemonWolf, Inc. All rights reserved.
//

import SwiftUI

/// General application settings interface — Music Sync (hero now-playing +
/// integrations dashboard) and App Visibility.
struct GeneralSettingsView: View {

    var configure: (IntegrationDashboardView.Section) -> Void = { _ in }

    var body: some View {
        VStack(alignment: .leading, spacing: DSSpace.s8) {
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
