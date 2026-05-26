//
//  DebugSettingsView.swift
//  WolfWave
//
//  Created by Nathanial Henniges on 2026-05-16.
//  Copyright © 2026 MrDemonWolf, Inc. All rights reserved.
//

#if DEBUG
import AppKit
import SwiftUI

/// Root detail pane for the DEBUG-only "Debug" settings tab.
///
/// Hosts developer tooling cards: UI previews, state inspectors, service controls,
/// and logs/notification utilities. The entire view (and its sibling cards) compiles
/// only in DEBUG builds — there is zero footprint in release.
struct DebugSettingsView: View {
    @State private var stateExpanded = true
    @State private var controlsExpanded = false

    @AppStorage(AppConstants.UserDefaults.trackingEnabled) private var musicTrackingEnabled = true
    @AppStorage(AppConstants.UserDefaults.discordPresenceEnabled) private var discordPresenceEnabled = false
    @AppStorage(AppConstants.UserDefaults.widgetHTTPEnabled) private var widgetHTTPEnabled = false

    var body: some View {
        VStack(alignment: .leading, spacing: AppConstants.SettingsUI.sectionSpacing) {
            header

            DisclosureGroup(isExpanded: $stateExpanded) {
                VStack(alignment: .leading, spacing: AppConstants.SettingsUI.sectionSpacing) {
                    DebugInspectorsCard()
                    DebugMetricsCard()
                    DebugLogsAndEventsCard()
                }
                .padding(.top, DSSpace.s3)
            } label: {
                groupLabel("State & Diagnostics", systemImage: "scope", tint: .blue)
            }

            DisclosureGroup(isExpanded: $controlsExpanded) {
                VStack(alignment: .leading, spacing: AppConstants.SettingsUI.sectionSpacing) {
                    warningBanner
                    DebugUIPreviewsCard()
                    DebugServiceControlsCard()
                }
                .padding(.top, DSSpace.s3)
            } label: {
                groupLabel("Active Controls", systemImage: "bolt.fill", tint: .orange)
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: DSSpace.s1) {
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
            Spacer()
            Button {
                copyDiagnostics()
            } label: {
                Label("Copy Diagnostics", systemImage: "doc.on.doc")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .pointerCursor()
            .help("Copy environment + service state as markdown for a GitHub issue.")
        }
    }

    // MARK: - Warning Banner

    private var warningBanner: some View {
        WarningBanner(
            text: "These tools mutate live state. Use at your own risk.",
            strokeVisible: true
        )
    }

    // MARK: - Group label

    private func groupLabel(_ title: String, systemImage: String, tint: Color) -> some View {
        HStack(spacing: DSSpace.s2) {
            Image(systemName: systemImage)
                .foregroundStyle(tint)
            Text(title)
                .sectionSubHeader()
        }
    }

    // MARK: - Copy Diagnostics

    private func copyDiagnostics() {
        let snapshot = DebugDiagnostics.Snapshot(
            appVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—",
            build: Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "—",
            osVersion: ProcessInfo.processInfo.operatingSystemVersionString,
            arch: BugReportURL.currentArch(),
            installMethod: Bundle.main.isHomebrewInstall ? "Homebrew" : "DMG",
            logSizeBytes: Log.logFileSize(),
            logLineCount: Log.logLineCount(),
            twitchConnected: KeychainService.loadTwitchToken() != nil,
            discordConnected: discordPresenceEnabled,
            widgetEnabled: widgetHTTPEnabled,
            musicTrackingEnabled: musicTrackingEnabled
        )
        let markdown = DebugDiagnostics.markdown(snapshot)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(markdown, forType: .string)
        Log.info("Copied diagnostics snapshot to pasteboard", category: "DevTools")
    }
}

#Preview {
    ScrollView {
        DebugSettingsView()
            .padding()
    }
}
#endif
