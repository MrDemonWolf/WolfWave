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
            groups: DebugSection.railGroups,
            accessibilityIDPrefix: "debugNav"
        ) {
            header

            groupLabel("State & Diagnostics")
            sectionBlock(.inspectors) { DebugInspectorsCard() }
            sectionBlock(.metrics) { DebugMetricsCard() }
            sectionBlock(.logViewer) { DebugLogViewerCard() }
            sectionBlock(.logs) { DebugLogsAndEventsCard() }

            groupLabel("Active Controls")
            warningBanner
            sectionBlock(.previews) { DebugUIPreviewsCard() }
            sectionBlock(.controls) { DebugServiceControlsCard() }

            groupLabel("Design System")
            sectionBlock(.components) { DebugComponentGalleryCard() }
            sectionBlock(.tokens) { DebugTokenGalleryCard() }
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
                .sectionHeader()
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

    /// Builds the diagnostics blob and puts it on the pasteboard.
    ///
    /// The slow reads run off the main actor. `Log.logLineCount()` streams the
    /// whole log under `fileQueue.sync` and `KeychainService.loadTwitchToken()`
    /// is a synchronous `SecItemCopyMatching`; doing both on `@MainActor` beach-
    /// balled the pane on a large log, which is the exact stall
    /// `DebugLogsAndEventsCard` already documents moving off-main to avoid.
    private func copyDiagnostics() {
        // Live connection state, read on the main actor where the services live.
        let twitchConnected = AppDelegate.shared?.twitchService?.currentlyConnected == true
        let discordConnection = (AppDelegate.shared?.discordService?.stateSnapshot
            ?? .disconnected).rawValue
        let preferences = (
            music: musicTrackingEnabled,
            discord: discordPresenceEnabled,
            widget: widgetHTTPEnabled
        )

        Task {
            let heavy = await Task.detached(priority: .userInitiated) {
                (
                    size: Log.logFileSize(),
                    lines: Log.logLineCount(),
                    tokenStored: KeychainService.loadTwitchToken() != nil
                )
            }.value

            let snapshot = DebugDiagnostics.Snapshot(
                appVersion: AppConstants.AppInfo.shortVersion,
                build: AppConstants.AppInfo.buildNumber,
                osVersion: ProcessInfo.processInfo.operatingSystemVersionString,
                arch: BugReportURL.currentArch(),
                installMethod: Bundle.main.isHomebrewInstall ? "Homebrew" : "DMG",
                logSizeBytes: heavy.size,
                logLineCount: heavy.lines,
                musicTrackingEnabled: preferences.music,
                discordPresenceEnabled: preferences.discord,
                widgetHTTPEnabled: preferences.widget,
                twitchConnected: twitchConnected,
                discordConnection: discordConnection,
                twitchTokenStored: heavy.tokenStored
            )
            Pasteboard.copy(DebugDiagnostics.markdown(snapshot))
            Log.info("Copied diagnostics snapshot to pasteboard", category: .devTools)
        }
    }
}

// MARK: - Debug Section

/// The Debug tab's jump-nav sections, in display order. `title` labels both the
/// rail row and the section heading; the enum case doubles as the
/// `ScrollViewReader` anchor attached via `.railSection(_:)`.
enum DebugSection: String, SettingsRailSection, CaseIterable {

    /// Rail layout. Hand-ordered because the grouping is editorial, but
    /// `DebugSectionCoverageTests` asserts every case appears exactly once, so
    /// adding a case without placing it here fails the suite instead of
    /// silently dropping the section out of the rail.
    static let railGroups: [SettingsRailGroup<DebugSection>] = [
        SettingsRailGroup(
            title: "State & Diagnostics",
            sections: [.inspectors, .metrics, .logViewer, .logs]),
        SettingsRailGroup(
            title: "Active Controls",
            sections: [.previews, .controls]),
        SettingsRailGroup(
            title: "Design System",
            sections: [.components, .tokens])
    ]

    case inspectors
    case metrics
    case logViewer
    case logs
    case previews
    case controls
    case components
    case tokens

    var title: String {
        switch self {
        case .inspectors: return "State Inspectors"
        case .metrics: return "Performance"
        case .logViewer: return "Log Viewer"
        case .logs: return "Logs & Events"
        case .previews: return "UI Previews"
        case .controls: return "Service Controls"
        case .components: return "Components"
        case .tokens: return "Tokens"
        }
    }

    var icon: String {
        switch self {
        case .inspectors: return "magnifyingglass"
        case .metrics: return "speedometer"
        case .logViewer: return "text.viewfinder"
        case .logs: return "doc.text"
        case .previews: return "rectangle.on.rectangle"
        case .controls: return "slider.horizontal.3"
        case .components: return "square.grid.2x2"
        case .tokens: return "paintpalette"
        }
    }
}

#Preview {
    DebugSettingsView()
        .frame(width: 820, height: 600)
}
#endif
