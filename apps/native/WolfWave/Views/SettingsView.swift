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

        /// Cases — `.debug` only present in DEBUG builds.
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

    // MARK: - User Settings

    /// Whether music tracking is currently enabled
    @AppStorage(AppConstants.UserDefaults.trackingEnabled)
    private var trackingEnabled = true

    @AppStorage(AppConstants.UserDefaults.dockVisibility)
    private var dockVisibility = "both"

    // MARK: - State

    /// Twitch settings view model
    @State private var twitchViewModel = TwitchViewModel()

    /// Shared Twitch service from the app delegate.
    private var appDelegate: AppDelegate? {
        NSApplication.shared.delegate as? AppDelegate
    }

    /// Controls the display of the reset confirmation alert
    @State private var showingResetAlert = false

    /// Currently selected settings section
    @State private var selectedSection: SettingsSection = .general

    var body: some View {
        NavigationSplitView {
            List(selection: $selectedSection) {
                ForEach(Self.sidebarGroups, id: \.sections) { group in
                    if let title = group.title {
                        Section(title) {
                            ForEach(group.sections) { section in
                                sidebarRow(for: section)
                            }
                        }
                    } else {
                        Section {
                            ForEach(group.sections) { section in
                                sidebarRow(for: section)
                            }
                        }
                    }
                }
            }
            .navigationSplitViewColumnWidth(min: 220, ideal: 240, max: 280)
        } detail: {
            ScrollView {
                VStack(alignment: .leading, spacing: AppConstants.SettingsUI.sectionSpacing) {
                    detailView(for: selectedSection)
                }
                .frame(maxWidth: AppConstants.SettingsUI.maxContentWidth, alignment: .topLeading)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.horizontal, AppConstants.SettingsUI.contentPaddingH)
                .padding(.vertical, AppConstants.SettingsUI.contentPaddingV)
            }
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
            .background(Color(nsColor: .underPageBackgroundColor))
            .onAppear {
                if let requestedSection = UserDefaults.standard.string(forKey: AppConstants.UserDefaults.selectedSettingsSection) {
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
        }
        .onAppear {
            // Link the view model to the app delegate's service (without reconnecting)
            twitchViewModel.twitchService = appDelegate?.twitchService

            // Initialize the view model's connection state from the service so the UI
            // reflects whether we are already joined (prevents missed callbacks).
            twitchViewModel.channelConnected = appDelegate?.twitchService?.isConnectedSnapshot.value ?? false
        }
        // Empty .toolbar { } binds NavigationSplitView's automatic sidebar
        // toggle to the window's NSToolbar (assigned in AppDelegate+Windows).
        // Without this, the toggle falls back to a floating reveal chevron in
        // the detail pane on macOS 26.
        .toolbar { }
        .frame(
            minWidth: AppConstants.SettingsUI.minWidth,
            idealWidth: AppConstants.SettingsUI.idealWidth,
            minHeight: AppConstants.SettingsUI.minHeight,
            idealHeight: AppConstants.SettingsUI.idealHeight
        )
        .navigationSplitViewStyle(.automatic)
        .alert("Reset Settings?", isPresented: $showingResetAlert) {
            Button("Cancel", role: .cancel) {}
            .accessibilityLabel("Cancel reset")
            .accessibilityHint("Cancels the reset and keeps current settings")
            .accessibilityIdentifier("resetSettingsCancelButton")

            Button("Reset", role: .destructive) {
                resetSettings()
            }
            .accessibilityLabel("Confirm reset")
            .accessibilityHint("Permanently resets all settings and signs you out")
            .accessibilityIdentifier("resetSettingsConfirmButton")
        } message: {
            Text("This resets all settings and signs you out. Can't be undone.")
        }
    }
    
    // MARK: - Detail Views

    /// Returns the detail pane content for the given sidebar section.
    @ViewBuilder
    private func detailView(for section: SettingsSection) -> some View {
        switch section {
        case .general:
            GeneralSettingsView(configure: { target in
                switch target {
                case .twitch: selectedSection = .twitchIntegration
                case .discord: selectedSection = .discord
                case .obs: selectedSection = .websocket
                case .advanced: selectedSection = .advanced
                }
            })
        case .songRequests:
            SongRequestSettingsView()
        case .websocket:
            WebSocketSettingsView()
        case .historyStats:
            HistoryStatsSettingsView()
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
    /// list scans cleanly: setup first, then integrations, insights, and the
    /// app-level pages. `.debug` is appended to the App group in DEBUG builds.
    private static var sidebarGroups: [(title: String?, sections: [SettingsSection])] {
        var app: [SettingsSection] = [.softwareUpdate, .about, .advanced]
        #if DEBUG
        app.append(.debug)
        #endif
        return [
            (nil, [.general]),
            ("Integrations", [.twitchIntegration, .discord, .websocket, .songRequests]),
            ("Insights", [.historyStats]),
            ("App", app),
        ]
    }

    /// Builds a sidebar row with a brand icon (if available) or an SF Symbol fallback.
    @ViewBuilder
    private func sidebarRow(for section: SettingsSection) -> some View {
        Label {
            Text(section.rawValue)
        } icon: {
            if let brandIcon = section.brandIcon {
                Image(brandIcon)
                    .renderingMode(.template)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 16, height: 16)
                    .foregroundStyle(.primary)
            } else {
                Image(systemName: section.systemIcon)
                    .frame(width: 16, height: 16)
            }
        }
        .accessibilityLabel(Text(section.rawValue))
        .accessibilityIdentifier(section.rawValue.replacingOccurrences(of: " ", with: "-").lowercased())
    }
    
    /// Twitch detail pane — auth settings plus the bot commands card.
    private func twitchIntegrationView() -> some View {
        VStack(alignment: .leading, spacing: AppConstants.SettingsUI.sectionSpacing) {
            TwitchSettingsView(viewModel: twitchViewModel)

            Divider()
                .padding(.vertical, DSSpace.s1)

            TwitchCommandsCard()
        }
    }

    // MARK: - Helpers

    /// Posts a notification when music tracking is toggled on or off.
    private func notifyTrackingSettingChanged(enabled: Bool) {
        NotificationCenter.default.postEnabled(.trackingSettingChanged, enabled: enabled)
    }

    /// Resets all settings to their default values and clears the stored token.
    ///
    /// This method:
    /// 1. Removes all user preferences from UserDefaults
    /// 2. Resets in-memory state to defaults
    /// 3. Deletes the authentication token from Keychain
    /// 4. Deletes Twitch credentials from Keychain
    /// 5. Notifies the app that tracking has been re-enabled
    private func resetSettings() {
        // Disconnect Discord before clearing UserDefaults
        NotificationCenter.default.postEnabled(.discordPresenceChanged, enabled: false)

        // Disconnect WebSocket server before clearing UserDefaults
        NotificationCenter.default.postWebSocketServerChanged(enabled: false)

        // Clear UserDefaults (every key the app writes)
        AppConstants.UserDefaults.allKeys.forEach {
            UserDefaults.standard.removeObject(forKey: $0)
        }

        // Reset to defaults
        trackingEnabled = true
        dockVisibility = "both"

        // Clear tokens and Twitch
        twitchViewModel.clearCredentials()

        // Disconnect from Twitch
        twitchViewModel.leaveChannel()

        // Notify tracking re-enabled
        notifyTrackingSettingChanged(enabled: true)
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
