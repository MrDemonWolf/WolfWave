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
/// Hosts developer tooling cards as a flat list of independently collapsible
/// sections: state inspectors, performance metrics, logs/events, UI previews,
/// and service controls. Each section is its own `DisclosureGroup`, so SwiftUI
/// only builds a card's body once its section is opened — collapsed sections
/// cost nothing, which keeps first paint fast and stops the metrics polling
/// loop from running while hidden. The entire view (and its sibling cards)
/// compiles only in DEBUG builds — there is zero footprint in release.
struct DebugSettingsView: View {
    // Per-section expansion, persisted so the dev's open/closed layout survives
    // tab switches and relaunches. Only State Inspectors opens by default so the
    // tab paints instantly; everything else builds lazily on first open. Keys are
    // DEBUG-only UI state, deliberately kept out of AppConstants.allKeys so they
    // don't show in the UserDefaults inspector or get wiped by reset ops.
    @AppStorage("debug.section.inspectors.expanded") private var inspectorsExpanded = true
    @AppStorage("debug.section.metrics.expanded") private var metricsExpanded = false
    @AppStorage("debug.section.logs.expanded") private var logsExpanded = false
    @AppStorage("debug.section.previews.expanded") private var previewsExpanded = false
    @AppStorage("debug.section.controls.expanded") private var controlsExpanded = false

    @AppStorage(AppConstants.UserDefaults.trackingEnabled) private var musicTrackingEnabled = true
    @AppStorage(AppConstants.UserDefaults.discordPresenceEnabled) private var discordPresenceEnabled = false
    @AppStorage(AppConstants.UserDefaults.widgetHTTPEnabled) private var widgetHTTPEnabled = false

    var body: some View {
        VStack(alignment: .leading, spacing: AppConstants.SettingsUI.sectionSpacing) {
            header

            groupLabel("State & Diagnostics")

            DebugDisclosure(title: "State Inspectors", isExpanded: $inspectorsExpanded) {
                DebugInspectorsCard()
            }

            DebugDisclosure(title: "Performance", isExpanded: $metricsExpanded) {
                DebugMetricsCard()
            }

            DebugDisclosure(title: "Logs & Events", isExpanded: $logsExpanded) {
                DebugLogsAndEventsCard()
            }

            groupLabel("Active Controls")
            warningBanner

            DebugDisclosure(title: "UI Previews", isExpanded: $previewsExpanded) {
                DebugUIPreviewsCard()
            }

            DebugDisclosure(title: "Service Controls", isExpanded: $controlsExpanded) {
                DebugServiceControlsCard()
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: DSSpace.s1) {
                Text("Debug Tools")
                    .sectionHeader()
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
        CalloutBanner(
            "These tools mutate live state. Use at your own risk.",
            strokeVisible: true
        )
    }

    // MARK: - Group label

    private func groupLabel(_ title: String) -> some View {
        Text(title)
            .sectionEyebrow()
            .padding(.top, DSSpace.s2)
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
        Pasteboard.copy(markdown)
        Log.info("Copied diagnostics snapshot to pasteboard", category: "DevTools")
    }
}

// MARK: - Debug Disclosure

/// A single collapsible debug section. Content is built lazily by the wrapped
/// `DisclosureGroup` — a collapsed section never instantiates its card body.
private struct DebugDisclosure<Content: View>: View {
    let title: String
    @Binding var isExpanded: Bool
    @ViewBuilder var content: () -> Content

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            content()
                .padding(.top, DSSpace.s3)
        } label: {
            Text(title)
                .sectionSubHeader()
                .contentShape(Rectangle())
        }
    }
}

#Preview {
    ScrollView {
        DebugSettingsView()
            .padding()
    }
}
#endif
