//
//  SettingsView.swift
//  WolfWave
//
//  Created by Nathanial Henniges on 2026-01-08.
//  Copyright © 2026 MrDemonWolf, Inc. All rights reserved.
//

import AppKit
import SwiftUI

/// Main settings UI for WolfWave application.
///
/// Provides a split-view interface with sidebar navigation and detail panes for:
/// - Music Playback Monitoring configuration
/// - App Visibility (dock/menu bar modes)
/// - WebSocket integration settings
/// - Twitch bot authentication and commands
/// - Advanced options (reset, debugging)
///
/// Architecture:
/// - NavigationSplitView with sidebar and detail columns
/// - Settings section enum for sidebar navigation
/// - Detail views composed from separate view components
/// - Sidebar toggle button in toolbar
/// - Reset alert confirmation
///
/// State Management:
/// - @State for TwitchViewModel (Twitch integration state, @Observable)
/// - @AppStorage for user preferences (synced to UserDefaults)
/// - @State for UI state (section selection, sidebar visibility)
///
/// Key Features:
/// - Smooth sidebar toggle animation
/// - Keyboard shortcuts (Esc or Cmd+W to close)
/// - Integration with AppDelegate services
/// - Responsive to notifications from other parts of the app
/// - Reset all settings with confirmation dialog
struct SettingsView: View {
    // MARK: - Constants

    // MARK: - Settings Section Enum
    
    /// Navigation sections in the settings sidebar.
    enum SettingsSection: String, CaseIterable, Identifiable {
        case general = "General"
        case songRequests = "Song Requests"
        case websocket = "Stream Widgets"
        case historyStats = "History & Stats"
        case twitchIntegration = "Twitch"
        case discord = "Discord"
        case softwareUpdate = "Software Update"
        case advanced = "Advanced"
        case about = "About"
        #if DEBUG
        case debug = "Debug"
        #endif

        var id: Self { self }

        /// Cases: `.debug` only present in DEBUG builds.
        static var allCases: [SettingsSection] {
            var cases: [SettingsSection] = [
                .general, .songRequests, .websocket, .historyStats, .twitchIntegration, .discord, .softwareUpdate, .advanced, .about,
            ]
            #if DEBUG
            cases.append(.debug)
            #endif
            return cases
        }

        /// SF Symbol name for the sidebar icon (used as fallback when no brand icon exists).
        var systemIcon: String {
            switch self {
            case .general: return "gear"
            case .songRequests: return "music.note.list"
            case .websocket: return "tv.badge.wifi"
            case .historyStats: return "chart.bar.xaxis"
            case .twitchIntegration: return "message.badge.waveform"
            case .discord: return "headphones"
            case .softwareUpdate: return "arrow.down.circle"
            case .advanced: return "gearshape.2"
            case .about: return "info.circle"
            #if DEBUG
            case .debug: return "ladybug.fill"
            #endif
            }
        }

        /// Asset catalog name for brand icons, `nil` for sections using SF Symbols.
        var brandIcon: String? {
            switch self {
            case .twitchIntegration: return "TwitchLogo"
            case .discord: return "DiscordLogo"
            default: return nil
            }
        }
    }

    // MARK: - State

    /// Twitch settings view model
    @State private var twitchViewModel = TwitchViewModel()

    /// Shared Twitch service from the app delegate.
    private var appDelegate: AppDelegate? {
        NSApplication.shared.delegate as? AppDelegate
    }

    /// Controls the display of the reset confirmation alert
    @State private var showingResetAlert = false

    /// Type-to-confirm text for the reset alert. The destructive "Reset" button
    /// stays disabled until this matches `resetConfirmWord` exactly, so wiping
    /// everything takes a deliberate keystroke, not a stray click. Cleared on
    /// both alert exits.
    @State private var resetConfirmText = ""

    /// The exact (case-sensitive) word the user must type to enable Reset.
    private let resetConfirmWord = "RESET"

    /// Currently selected settings section
    @State private var selectedSection: SettingsSection = .general

    /// Sidebar column visibility. Bound into `NavigationSplitView` so the
    /// automatic title-bar toggle (and any future programmatic show/hide) drives
    /// a single source of truth.
    @State private var columnVisibility: NavigationSplitViewVisibility = .all

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            SettingsSidebarView(selection: $selectedSection, groups: Self.sidebarGroups)
                .navigationSplitViewColumnWidth(min: 200, ideal: 230, max: 280)
                // Remove SwiftUI's automatic sidebar toggle here, on the sidebar
                // column it belongs to. Removing it from the outer split chain
                // left it in place (two toggles); our detail-toolbar toggle is
                // the only one we want.
                .toolbar(removing: .sidebarToggle)
        } detail: {
            detailPane
            .scrollEdgeEffectStyle(.hard, for: .top)
            .transaction(value: selectedSection) { $0.disablesAnimations = true }
            .onChange(of: selectedSection) { _, newSection in
                // Cancel in-progress Twitch OAuth if user navigates away
                if newSection != .twitchIntegration, twitchViewModel.authState.isInProgress {
                    twitchViewModel.cancelOAuth()
                }
            }
            .padding(.top, DSSpace.s2)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(nsColor: .windowBackgroundColor))
            .onAppear {
                if let requestedSection = Preferences.selectedSettingsSection {
                    if requestedSection == AppConstants.Twitch.settingsSection {
                        selectedSection = .twitchIntegration
                    }
                    UserDefaults.standard.removeObject(forKey: AppConstants.UserDefaults.selectedSettingsSection)
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .openSettingsSection)) { note in
                guard let raw = note.sectionString,
                      let section = SettingsSection(rawValue: raw) else { return }
                selectedSection = section
            }
            // The sidebar toggle lives on the DETAIL toolbar, not the sidebar's.
            // SwiftUI's automatic toggle sits in the leading (sidebar) toolbar
            // segment; while the column animates to zero width that segment can't
            // fit the toggle for a frame or two, so AppKit paints the segment's
            // overflow `>>` chevron at the divider. Hosting our own toggle in the
            // detail segment (right of the sidebar tracking separator) leaves the
            // collapsing sidebar segment with no item to overflow, and matches
            // the native reference, which shows the toggle at the detail's leading
            // edge.
            .toolbar {
                ToolbarItem(placement: .navigation) {
                    Button(action: toggleSidebar) {
                        Image(systemName: "sidebar.leading")
                    }
                    .help("Toggle Sidebar")
                    .accessibilityLabel("Toggle Sidebar")
                    .accessibilityIdentifier("sidebarToggleButton")
                }
            }
        }
        .onAppear {
            // Link the view model to the app delegate's service (without reconnecting)
            twitchViewModel.twitchService = appDelegate?.twitchService

            // Initialize the view model's connection state from the service so the UI
            // reflects whether we are already joined (prevents missed callbacks).
            twitchViewModel.channelConnected = appDelegate?.twitchService?.currentlyConnected ?? false
        }
        // `SettingsWindowConfigurator` hides the window title and makes the title
        // bar transparent for the clean full-height-sidebar look. The automatic
        // sidebar toggle is removed on the sidebar column itself (above); our
        // detail-toolbar toggle replaces it. `columnVisibility` is threaded in so
        // every sidebar toggle re-asserts the chrome (the toggle re-themes the
        // title bar back to the default visible-title / opaque look otherwise).
        .background(SettingsWindowConfigurator(columnVisibility: columnVisibility))
        .frame(
            minWidth: AppConstants.SettingsUI.minWidth,
            idealWidth: AppConstants.SettingsUI.idealWidth,
            minHeight: AppConstants.SettingsUI.minHeight,
            idealHeight: AppConstants.SettingsUI.idealHeight
        )
        .navigationSplitViewStyle(.automatic)
        .alert("Erase everything?", isPresented: $showingResetAlert) {
            TextField("Type \(resetConfirmWord) to confirm", text: $resetConfirmText)
                .accessibilityLabel("Type \(resetConfirmWord) to confirm reset")
                .accessibilityIdentifier("resetSettingsConfirmField")

            Button("Cancel", role: .cancel) { resetConfirmText = "" }
            .accessibilityLabel("Cancel reset")
            .accessibilityHint("Cancels the reset and keeps current settings")
            .accessibilityIdentifier("resetSettingsCancelButton")

            Button("Erase & Reset", role: .destructive) {
                resetSettings()
                resetConfirmText = ""
            }
            .disabled(resetConfirmText != resetConfirmWord)
            .accessibilityLabel("Confirm erase and reset")
            .accessibilityHint("Permanently erases all data and relaunches WolfWave")
            .accessibilityIdentifier("resetSettingsConfirmButton")
        } message: {
            Text("This wipes everything: settings, Twitch and Discord sign-in, logs, listening history, and the artwork cache. WolfWave restarts as a fresh install. This can't be undone.\n\nType \(resetConfirmWord) to confirm.")
        }
        // Clear on the source-of-truth lifecycle event so every dismissal path
        // (Cancel, Escape, click-away) starts the next attempt with an empty field.
        .onChange(of: showingResetAlert) { _, isPresented in
            if !isPresented { resetConfirmText = "" }
        }
    }
    
    // MARK: - Detail Views

    /// Returns the detail pane content for the given sidebar section.
    /// Detail content for the selected section. Most sections render inside a
    /// shared scrolling, width-clamped column. A few opt out because they own
    /// their own scroll layout: General and Song Requests (jump-nav rail),
    /// History & Stats (plain scroll), and the DEBUG-only Debug tab.
    @ViewBuilder
    private var detailPane: some View {
        if selectedSection == .general {
            generalDetail
        } else if selectedSection == .songRequests {
            SongRequestSettingsView()
        } else if selectedSection == .historyStats {
            HistoryStatsSettingsView(openTwitchSettings: { selectedSection = .twitchIntegration })
        } else {
            #if DEBUG
            if selectedSection == .debug {
                DebugSettingsView()
            } else {
                standardDetailScroll
            }
            #else
            standardDetailScroll
            #endif
        }
    }

    /// General pane. Owns its own rail + scroll layout (see `GeneralSettingsView`),
    /// so it bypasses `standardDetailScroll` and fills the full detail width like
    /// the Debug tab. `configure` routes the integration "Configure" rows to the
    /// matching sidebar section.
    private var generalDetail: some View {
        GeneralSettingsView(configure: { target in
            switch target {
            case .twitch: selectedSection = .twitchIntegration
            case .discord: selectedSection = .discord
            case .obs: selectedSection = .websocket
            case .advanced: selectedSection = .advanced
            }
        })
    }

    private var standardDetailScroll: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppConstants.SettingsUI.sectionSpacing) {
                detailView(for: selectedSection)
            }
            .frame(maxWidth: AppConstants.SettingsUI.maxContentWidth, alignment: .topLeading)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.horizontal, AppConstants.SettingsUI.contentPaddingH)
            .padding(.vertical, AppConstants.SettingsUI.contentPaddingV)
        }
    }

    @ViewBuilder
    private func detailView(for section: SettingsSection) -> some View {
        switch section {
        case .general:
            // General owns a full-width rail layout and is routed via
            // `generalDetail` in `detailPane`, bypassing this shared scroll
            // wrapper. Kept here only to satisfy switch exhaustiveness.
            EmptyView()
        case .songRequests:
            // Song Requests owns a full-width rail layout (when enabled) and is
            // routed via `detailPane`, bypassing this shared scroll wrapper. Kept
            // here only to satisfy switch exhaustiveness.
            EmptyView()
        case .websocket:
            WebSocketSettingsView()
        case .historyStats:
            // History & Stats owns a full-width scroll layout and is routed via
            // `detailPane`, bypassing this shared scroll wrapper. Kept here only
            // to satisfy switch exhaustiveness.
            EmptyView()
        case .twitchIntegration:
            twitchIntegrationView()
        case .discord:
            DiscordSettingsView()
        case .softwareUpdate:
            SoftwareUpdateSettingsView()
        case .advanced:
            AdvancedSettingsView(showingResetAlert: $showingResetAlert)
        case .about:
            AboutSettingsView()
        #if DEBUG
        case .debug:
            DebugSettingsView()
        #endif
        }
    }

    // MARK: - Sidebar Helpers

    /// Grouped sidebar layout. Headers keep related sections together so the
    /// list scans cleanly, each group covering one concept: General first, then
    /// linked services (Integrations), on-stream features, insights, and the
    /// app-level pages. Within App, order runs most- to least-reached (update →
    /// advanced → info), so the read-only About anchors the bottom. `.debug` is
    /// appended to the App group in DEBUG builds.
    private static var sidebarGroups: [(title: String?, sections: [SettingsSection])] {
        var app: [SettingsSection] = [.softwareUpdate, .advanced, .about]
        #if DEBUG
        app.append(.debug)
        #endif
        return [
            (nil, [.general]),
            ("Integrations", [.twitchIntegration, .discord]),
            ("On Stream", [.websocket, .songRequests]),
            ("Insights", [.historyStats]),
            ("App", app),
        ]
    }

    /// Twitch detail pane: auth settings plus the bot commands card.
    private func twitchIntegrationView() -> some View {
        VStack(alignment: .leading, spacing: AppConstants.SettingsUI.sectionSpacing) {
            TwitchSettingsView(viewModel: twitchViewModel)

            Divider()
                .padding(.vertical, DSSpace.s1)

            TwitchCommandsCard(viewModel: twitchViewModel)

            Divider()
                .padding(.vertical, DSSpace.s1)

            CustomCommandsCard()
        }
    }

    // MARK: - Helpers

    /// Toggles the sidebar column between visible (`.all`) and hidden
    /// (`.detailOnly`), animated. Drives the detail-toolbar toggle button that
    /// replaces SwiftUI's automatic sidebar-segment toggle (see `body`).
    private func toggleSidebar() {
        withAnimation(DSMotion.Spring.snappy) {
            columnVisibility = columnVisibility == .detailOnly ? .all : .detailOnly
        }
    }

    /// Wipes every trace of the app's state and relaunches into a fresh
    /// install. This is a true factory reset, not just a preferences reset.
    ///
    /// Order matters: stop outward connections, then tear down their config.
    /// 1. Disconnect Discord Rich Presence and the WebSocket overlay server
    /// 2. Disconnect Twitch and clear its in-memory state
    /// 3. Delete every Keychain credential (Twitch tokens + WebSocket token)
    /// 4. Remove every UserDefaults key the app writes
    /// 5. Delete the on-disk container (logs, listening history, artwork
    ///    cache, crash markers, diagnostics)
    /// 6. Relaunch into a clean state so onboarding returns and live services
    ///    boot without stale in-memory state
    private func resetSettings() {
        // Disconnect outward integrations before clearing their config.
        NotificationCenter.default.postEnabled(.discordPresenceChanged, enabled: false)
        NotificationCenter.default.postWebSocketServerChanged(enabled: false)

        // Twitch: disconnect + clear in-memory view-model state.
        // clearCredentials() leaves the channel first when connected.
        twitchViewModel.clearCredentials()

        // Keychain: wipe every stored credential in one sweep.
        KeychainService.deleteAll()

        // UserDefaults: remove every key the app writes.
        AppConstants.UserDefaults.allKeys.forEach {
            UserDefaults.standard.removeObject(forKey: $0)
        }

        // On-disk data: logs, listening history, artwork cache, crash
        // markers, diagnostics: the whole Application Support container.
        AppContainer.wipe()

        // Relaunch into a clean, fresh-install state.
        relaunchApp()
    }

    /// Relaunches WolfWave in a new process, then quits the current instance.
    ///
    /// Uses `NSWorkspace.openApplication`, which is sandbox-safe. Spawning
    /// `/usr/bin/open` or a raw `Process` is blocked under the App Sandbox.
    /// `createsNewApplicationInstance` lets the new copy start while this one
    /// is still terminating.
    ///
    /// Terminates only when the new instance actually launched. If the launch
    /// fails we keep this process alive rather than leaving the user with no
    /// running app after a wipe.
    private func relaunchApp() {
        let bundleURL = Bundle.main.bundleURL
        let config = NSWorkspace.OpenConfiguration()
        config.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: bundleURL, configuration: config) { app, error in
            DispatchQueue.main.async {
                if let error {
                    Log.error(
                        "Relaunch after reset failed: \(error.localizedDescription)",
                        category: "Reset"
                    )
                    return
                }
                guard app != nil else {
                    Log.error("Relaunch after reset returned no app instance", category: "Reset")
                    return
                }
                NSApplication.shared.terminate(nil)
            }
        }
    }
}

// MARK: - Window Configurator

/// Reaches the SwiftUI `Settings` window via `view.window` and applies the
/// clean full-height-sidebar chrome: hidden title text and a transparent title
/// bar. This matches the native reference look (no centered "WolfWave Settings"
/// label) and frees title-bar width, so `NavigationSplitView`'s sidebar toggle
/// and tracking separator stop overflowing into AppKit's `>>` clip chevron while
/// the sidebar animates.
///
/// Only cosmetic window properties are touched; `styleMask` is left to SwiftUI,
/// so `SettingsSceneBridge.settingsWindow()`'s titled / non-fullSizeContentView
/// detection and the dock-visibility probe keep working.
private struct SettingsWindowConfigurator: NSViewRepresentable {
    /// Bound to the split view's column visibility so `updateNSView` fires on
    /// every sidebar toggle. The value itself isn't read; it exists to make the
    /// dependency explicit and guarantee the re-assert below runs.
    let columnVisibility: NavigationSplitViewVisibility

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        // The host window isn't attached yet during `makeNSView`; defer one
        // runloop tick until `view.window` is populated.
        DispatchQueue.main.async { configure(view.window) }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        // Re-assert in case SwiftUI re-realizes or re-themes the window. Toggling
        // the sidebar re-themes the title bar (restoring the default visible title
        // and opaque bar) on this same runloop pass, so a synchronous re-assert
        // here loses the race. Defer one tick so our chrome wins after the toggle's
        // re-theme commits.
        DispatchQueue.main.async { configure(nsView.window) }
    }

    @MainActor
    private func configure(_ window: NSWindow?) {
        guard let window else { return }
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
    }
}

// MARK: - Preview

#Preview {
    SettingsView()
        .frame(
            width: AppConstants.SettingsUI.idealWidth,
            height: AppConstants.SettingsUI.idealHeight
        )
}
