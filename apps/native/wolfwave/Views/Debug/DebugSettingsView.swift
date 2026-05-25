//
//  DebugSettingsView.swift
//  wolfwave
//
//  Created by MrDemonWolf, Inc. on 5/16/26.
//

#if DEBUG
import SwiftUI

/// Root detail pane for the DEBUG-only "Debug" settings tab.
///
/// Hosts developer tooling cards: UI previews, state inspectors, service controls,
/// and logs/notification utilities. The entire view (and its sibling cards) compiles
/// only in DEBUG builds — there is zero footprint in release.
struct DebugSettingsView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: AppConstants.SettingsUI.sectionSpacing) {
            header
            warningBanner
            DebugUIPreviewsCard()
            DebugInspectorsCard()
            DebugMetricsCard()
            DebugServiceControlsCard()
            DebugLogsAndEventsCard()
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: DSSpace.s2) {
                Image(systemName: "ladybug.fill")
                    .font(.system(size: DSFont.Size.x18))
                    .foregroundStyle(.orange)
                Text("Debug Tools")
                    .sectionHeader()
            }
            Text("Developer-only tools. Not shipped in release builds.")
                .font(.system(size: DSFont.Size.base))
                .foregroundStyle(.secondary)
        }
    }

    private var warningBanner: some View {
        HStack(spacing: DSSpace.s2) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text("These tools mutate live state. Use at your own risk.")
                .font(.system(size: DSFont.Size.body))
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.horizontal, DSSpace.s4)
        .padding(.vertical, DSSpace.s2)
        .background(Color.orange.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: AppConstants.SettingsUI.cardCornerRadius))
        .overlay(
            RoundedRectangle(cornerRadius: AppConstants.SettingsUI.cardCornerRadius)
                .stroke(Color.orange.opacity(0.25), lineWidth: 1)
        )
    }
}

#Preview {
    ScrollView {
        DebugSettingsView()
            .padding()
    }
}
#endif
