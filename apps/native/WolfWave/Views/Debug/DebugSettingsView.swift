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
/// Lays out developer tooling as a two-column page: a fixed jump-nav rail on the
/// left and an always-visible, scrollable column of section cards on the right:
/// state inspectors, performance metrics, logs/events, UI previews, and service
/// controls. Sections no longer collapse; the rail lets you jump straight to any
/// one because the full page is long. Clicking a rail row scrolls its section to
/// the top via `ScrollViewReader`, and the rail highlights wherever you are.
///
/// Because every section is mounted at once, the `DebugMetricsCard` polling loop
/// runs the whole time the Debug tab is on-screen (it cancels on tab switch via
/// structured concurrency). That's an accepted cost for a DEBUG-only tab that
/// ships zero footprint in release. The entire view compiles out under
/// `#if DEBUG`.
struct DebugSettingsView: View {
    @AppStorage(AppConstants.UserDefaults.trackingEnabled) private var musicTrackingEnabled = true
    @AppStorage(AppConstants.UserDefaults.discordPresenceEnabled) private var discordPresenceEnabled = false
    @AppStorage(AppConstants.UserDefaults.widgetHTTPEnabled) private var widgetHTTPEnabled = false

    /// Rail selection + scroll target. Drives the highlight and the jump.
    @State private var selected: DebugSection = .inspectors

    var body: some View {
        SettingsNavRail(
            selection: $selected,
            groups: [
                SettingsRailGroup(title: "State & Diagnostics", sections: [.inspectors, .metrics, .logs]),
                SettingsRailGroup(title: "Active Controls", sections: [.previews, .controls]),
            ],
            accessibilityIDPrefix: "debugNav"
        ) {
            header

            groupLabel("State & Diagnostics")
            sectionBlock(.inspectors) { DebugInspectorsCard() }
            sectionBlock(.metrics) { DebugMetricsCard() }
            sectionBlock(.logs) { DebugLogsAndEventsCard() }

            groupLabel("Active Controls")
            warningBanner
            sectionBlock(.previews) { DebugUIPreviewsCard() }
            sectionBlock(.controls) { DebugServiceControlsCard() }
        }
    }

    // MARK: - Section Block

    /// Wraps a card with its section heading and tags it as the rail's scroll
    /// anchor for `section`. Content is built once and stays mounted.
    @ViewBuilder
    private func sectionBlock<Content: View>(
        _ section: DebugSection,
        @ViewBuilder _ content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: DSSpace.s3) {
            Text(section.title)
                .sectionSubHeader()
            content()
        }
        .railSection(section)
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
            appVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "N/A",
            build: Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "N/A",
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

// MARK: - Debug Section

/// The Debug tab's jump-nav sections, in display order. `title` labels both the
/// rail row and the section heading; the enum case doubles as the
/// `ScrollViewReader` anchor attached via `.railSection(_:)`.
private enum DebugSection: String, SettingsRailSection {
    case inspectors
    case metrics
    case logs
    case previews
    case controls

    var title: String {
        switch self {
        case .inspectors: return "State Inspectors"
        case .metrics: return "Performance"
        case .logs: return "Logs & Events"
        case .previews: return "UI Previews"
        case .controls: return "Service Controls"
        }
    }

    var icon: String {
        switch self {
        case .inspectors: return "magnifyingglass"
        case .metrics: return "speedometer"
        case .logs: return "doc.text"
        case .previews: return "rectangle.on.rectangle"
        case .controls: return "slider.horizontal.3"
        }
    }
}

#Preview {
    DebugSettingsView()
        .frame(width: 820, height: 600)
}
#endif
