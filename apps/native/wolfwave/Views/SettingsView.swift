//
//  SettingsView.swift
//  wolfwave
//
//  Created by MrDemonWolf, Inc. on 1/17/26.
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
        case websocket = "Now-Playing Server"
        case twitchIntegration = "Twitch Integration"
        case discord = "Discord Integration"
        case advanced = "Advanced"

        var id: String { rawValue }

        /// SF Symbol name for the sidebar icon (used as fallback when no brand icon exists).
        var systemIcon: String {
            switch self {
            case .general: return "gear"
            case .websocket: return "tv.badge.wifi"
            case .twitchIntegration: return "message.badge.waveform"
            case .discord: return "headphones"
            case .advanced: return "gearshape.2"
            }
        }

        /// Asset catalog name for brand icons, `nil` for sections using SF Symbols.
        var brandIcon: String? {
            switch self {
            case .twitchIntegration: return "TwitchLogo"
            case .discord: return "DiscordLogo"
            case .websocket: return "OBSLogo"
            default: return nil
            }
        }

        /// Whether the brand icon should render as a template (tinted by macOS for light/dark mode).
        var brandIconIsTemplate: Bool {
            switch self {
            case .websocket: return true
            default: return false
            }
        }
    }

    // MARK: - Properties

    /// Application name from bundle metadata, with fallback to default.
    ///
    /// Used in window titles, notifications, and menu items.
    private var appName: String {
        Bundle.main.infoDictionary?["CFBundleDisplayName"] as? String ?? Bundle.main
            .infoDictionary?["CFBundleName"] as? String ?? AppConstants.SettingsUI.defaultAppName
    }

    // MARK: - User Settings

    /// Whether music tracking is currently enabled
    @AppStorage(AppConstants.UserDefaults.trackingEnabled)
    private var trackingEnabled = true

    /// Whether the Current Playing Song command is enabled
    @AppStorage(AppConstants.UserDefaults.currentSongCommandEnabled)
    private var currentSongCommandEnabled = false

    /// Whether the Last Played Song command is enabled
    @AppStorage(AppConstants.UserDefaults.lastSongCommandEnabled)
    private var lastSongCommandEnabled = false

    /// Cooldown settings for bot commands
    @AppStorage(AppConstants.UserDefaults.songCommandGlobalCooldown)
    private var songGlobalCooldown: Double = 15.0
    @AppStorage(AppConstants.UserDefaults.songCommandUserCooldown)
    private var songUserCooldown: Double = 15.0
    @AppStorage(AppConstants.UserDefaults.lastSongCommandGlobalCooldown)
    private var lastSongGlobalCooldown: Double = 15.0
    @AppStorage(AppConstants.UserDefaults.lastSongCommandUserCooldown)
    private var lastSongUserCooldown: Double = 15.0

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
    
    /// Controls sidebar visibility
    @State private var sidebarVisibility: NavigationSplitViewVisibility = .all

    var body: some View {
        NavigationSplitView(columnVisibility: $sidebarVisibility) {
            List(SettingsSection.allCases, selection: $selectedSection) { section in
                sidebarRow(for: section)
                    .tag(section)
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 200, ideal: 220, max: 280)
            .padding(.top, 4)
        } detail: {
            ScrollView {
                VStack(alignment: .leading, spacing: AppConstants.SettingsUI.sectionSpacing) {
                    detailView(for: selectedSection)
                }
                .transaction { $0.animation = nil }
                .frame(maxWidth: AppConstants.SettingsUI.maxContentWidth, alignment: .topLeading)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.horizontal, AppConstants.SettingsUI.contentPaddingH)
                .padding(.vertical, AppConstants.SettingsUI.contentPaddingV)
            }
            .animation(.none, value: selectedSection)
            .onChange(of: selectedSection) { _, newSection in
                // Cancel in-progress Twitch OAuth if user navigates away
                if newSection != .twitchIntegration, twitchViewModel.authState.isInProgress {
                    twitchViewModel.cancelOAuth()
                }
            }
            .padding(.top, 8)
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
        }
        .frame(
            minWidth: AppConstants.SettingsUI.minWidth,
            idealWidth: AppConstants.SettingsUI.idealWidth,
            maxWidth: AppConstants.SettingsUI.maxWidth,
            minHeight: AppConstants.SettingsUI.minHeight,
            idealHeight: AppConstants.SettingsUI.idealHeight,
            maxHeight: AppConstants.SettingsUI.maxHeight
        )
        .onAppear {
            // Link the view model to the app delegate's service (without reconnecting)
            twitchViewModel.twitchService = appDelegate?.twitchService

            // Initialize the view model's connection state from the service so the UI
            // reflects whether we are already joined (prevents missed callbacks).
            twitchViewModel.channelConnected = appDelegate?.twitchService?.isConnected ?? false
        }
        .toolbar(removing: .sidebarToggle)
        .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
        .navigationSplitViewStyle(.balanced)
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
            GeneralSettingsView()
        case .websocket:
            WebSocketSettingsView()
        case .twitchIntegration:
            twitchIntegrationView()
        case .discord:
            DiscordSettingsView()
        case .advanced:
            AdvancedSettingsView(showingResetAlert: $showingResetAlert)
        }
    }

    // MARK: - Sidebar Helpers

    /// Builds a sidebar row with a brand icon (if available) or an SF Symbol fallback.
    @ViewBuilder
    private func sidebarRow(for section: SettingsSection) -> some View {
        if let brandIcon = section.brandIcon {
            Label {
                Text(section.rawValue)
            } icon: {
                Image(brandIcon)
                    .renderingMode(section.brandIconIsTemplate ? .template : .original)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 16, height: 16)
            }
            .accessibilityLabel(Text(section.rawValue))
            .accessibilityIdentifier(section.rawValue.replacingOccurrences(of: " ", with: "-").lowercased())
        } else {
            Label(section.rawValue, systemImage: section.systemIcon)
                .accessibilityLabel(Text(section.rawValue))
                .accessibilityIdentifier(section.rawValue.replacingOccurrences(of: " ", with: "-").lowercased())
        }
    }
    
    /// Twitch detail pane — auth settings plus bot command toggles and cooldown sliders.
    private func twitchIntegrationView() -> some View {
        VStack(alignment: .leading, spacing: AppConstants.SettingsUI.sectionSpacing) {
            TwitchSettingsView(viewModel: twitchViewModel)

            Divider()
                .padding(.vertical, 4)

            // Bot Commands Section
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        Image(systemName: "bubble.left.fill")
                            .font(.system(size: 15))
                            .foregroundStyle(Color(nsColor: .controlAccentColor))
                        Text("Bot Commands")
                            .sectionSubHeader()
                    }

                    Text("Choose which commands people can use in chat.")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }

                VStack(spacing: 1) {
                    commandToggleRow(
                        title: "!song Command",
                        subtitle: "!song  ·  !currentsong  ·  !nowplaying",
                        isOn: $currentSongCommandEnabled,
                        accessibilityLabel: "Enable Current Playing Song command",
                        accessibilityIdentifier: "currentSongCommandToggle",
                        isFirst: true
                    ) { enabled in
                        Log.debug("SettingsView: Current Song Command \(enabled ? "enabled" : "disabled")", category: "Twitch")
                    }

                    if currentSongCommandEnabled {
                        cooldownRow(
                            label: "!song cooldowns",
                            globalCooldown: $songGlobalCooldown,
                            userCooldown: $songUserCooldown
                        )
                    }

                    commandToggleRow(
                        title: "!last Command",
                        subtitle: "!last  ·  !lastsong  ·  !prevsong",
                        isOn: $lastSongCommandEnabled,
                        accessibilityLabel: "Enable Last Played Song command",
                        accessibilityIdentifier: "lastSongCommandToggle",
                        isLast: !lastSongCommandEnabled
                    ) { enabled in
                        Log.debug("SettingsView: Last Song Command \(enabled ? "enabled" : "disabled")", category: "Twitch")
                    }

                    if lastSongCommandEnabled {
                        cooldownRow(
                            label: "!last cooldowns",
                            globalCooldown: $lastSongGlobalCooldown,
                            userCooldown: $lastSongUserCooldown,
                            isLast: true
                        )
                    }
                }
                .background(Color(nsColor: .controlBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: AppConstants.SettingsUI.cardCornerRadius))

                HStack(spacing: 6) {
                    Image(systemName: "info.circle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    Text("Cooldowns don't apply to you or your mods.")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    /// A toggle row for enabling/disabling a single bot command.
    @ViewBuilder
    private func commandToggleRow(
        title: String,
        subtitle: String,
        isOn: Binding<Bool>,
        accessibilityLabel: String,
        accessibilityIdentifier: String,
        isFirst: Bool = false,
        isLast: Bool = false,
        onChange: @escaping (Bool) -> Void
    ) -> some View {
        ToggleSettingRow(
            title: title,
            subtitle: subtitle,
            isOn: isOn,
            accessibilityLabel: accessibilityLabel,
            accessibilityIdentifier: accessibilityIdentifier,
            onChange: onChange
        )
        .padding(.horizontal, AppConstants.SettingsUI.cardPadding)
        .padding(.vertical, 12)
        .background(Color(nsColor: .controlBackgroundColor))
        .overlay(alignment: .bottom) {
            if !isLast {
                Divider()
                    .padding(.leading, AppConstants.SettingsUI.cardPadding)
            }
        }
    }

    /// A row with global and per-user cooldown sliders for a bot command.
    @ViewBuilder
    private func cooldownRow(
        label: String,
        globalCooldown: Binding<Double>,
        userCooldown: Binding<Double>,
        isLast: Bool = false
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)

            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Everyone: \(Int(globalCooldown.wrappedValue))s")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    Slider(value: globalCooldown, in: 0...30, step: 5)
                        .controlSize(.small)
                        .accessibilityLabel("\(label) global cooldown")
                        .accessibilityValue("\(Int(globalCooldown.wrappedValue)) seconds")
                        .accessibilityHint("Adjusts the global cooldown between 0 and 30 seconds")
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("Per person: \(Int(userCooldown.wrappedValue))s")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    Slider(value: userCooldown, in: 0...60, step: 5)
                        .controlSize(.small)
                        .accessibilityLabel("\(label) per-user cooldown")
                        .accessibilityValue("\(Int(userCooldown.wrappedValue)) seconds")
                        .accessibilityHint("Adjusts the per-user cooldown between 0 and 60 seconds")
                }
            }
        }
        .padding(.horizontal, AppConstants.SettingsUI.cardPadding)
        .padding(.vertical, 8)
        .background(Color(nsColor: .controlBackgroundColor))
        .overlay(alignment: .bottom) {
            if !isLast {
                Divider()
                    .padding(.leading, AppConstants.SettingsUI.cardPadding)
            }
        }
    }

    // MARK: - Helpers

    /// Posts a notification when music tracking is toggled on or off.
    private func notifyTrackingSettingChanged(enabled: Bool) {
        NotificationCenter.default.post(
            name: NSNotification.Name(AppConstants.Notifications.trackingSettingChanged),
            object: nil,
            userInfo: ["enabled": enabled]
        )
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
        NotificationCenter.default.post(
            name: NSNotification.Name(AppConstants.Notifications.discordPresenceChanged),
            object: nil,
            userInfo: ["enabled": false]
        )

        // Disconnect WebSocket server before clearing UserDefaults
        NotificationCenter.default.post(
            name: NSNotification.Name(AppConstants.Notifications.websocketServerChanged),
            object: nil,
            userInfo: ["enabled": false]
        )

        // Clear UserDefaults
        [AppConstants.UserDefaults.trackingEnabled, AppConstants.UserDefaults.currentSongCommandEnabled, AppConstants.UserDefaults.lastSongCommandEnabled, AppConstants.UserDefaults.dockVisibility, AppConstants.UserDefaults.websocketEnabled, AppConstants.UserDefaults.websocketURI, AppConstants.UserDefaults.websocketServerPort, AppConstants.UserDefaults.hasCompletedOnboarding, AppConstants.UserDefaults.discordPresenceEnabled, AppConstants.UserDefaults.widgetHTTPEnabled, AppConstants.UserDefaults.widgetPort, AppConstants.UserDefaults.widgetTheme, AppConstants.UserDefaults.widgetLayout, AppConstants.UserDefaults.widgetTextColor, AppConstants.UserDefaults.widgetBackgroundColor, AppConstants.UserDefaults.widgetFontFamily, AppConstants.UserDefaults.songCommandGlobalCooldown, AppConstants.UserDefaults.songCommandUserCooldown, AppConstants.UserDefaults.lastSongCommandGlobalCooldown, AppConstants.UserDefaults.lastSongCommandUserCooldown, AppConstants.UserDefaults.updateCheckEnabled, AppConstants.UserDefaults.updateSkippedVersion, AppConstants.UserDefaults.lastSeenWhatsNewVersion].forEach {
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
