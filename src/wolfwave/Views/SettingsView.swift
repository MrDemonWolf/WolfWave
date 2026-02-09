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
/// - @StateObject for TwitchViewModel (Twitch integration state)
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

    fileprivate enum Constants {
        /// Valid schemes for WebSocket URI validation
        static let validSchemes = ["ws", "wss", "http", "https"]
    }
    
    // MARK: - Settings Section Enum
    
    /// Navigation sections in the settings sidebar.
    enum SettingsSection: String, CaseIterable, Identifiable {
        case musicMonitor = "Music Monitor"
        case appVisibility = "App Visibility"
        case websocket = "WebSocket"
        case twitchIntegration = "Twitch Integration"
        case discord = "Discord Integration"
        case advanced = "Advanced"
        
        var id: String { rawValue }
        
        /// System SF Symbol name for sidebar icon (or nil for custom image).
        var systemIcon: String? {
            switch self {
            case .musicMonitor: return "music.note"
            case .appVisibility: return "eye"
            case .websocket: return "dot.radiowaves.left.and.right"
            case .twitchIntegration: return nil // Uses custom image
            case .discord: return nil // Uses custom image
            case .advanced: return "gearshape"
            }
        }

        /// Custom image name for sidebar icon (or nil for system icon).
        var customIcon: String? {
            switch self {
            case .twitchIntegration: return "TwitchGlitch"
            case .discord: return "DiscordLogo"
            default: return nil
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
    private var currentSongCommandEnabled = true

    /// Whether the Last Played Song command is enabled
    @AppStorage(AppConstants.UserDefaults.lastSongCommandEnabled)
    private var lastSongCommandEnabled = true

    @AppStorage(AppConstants.UserDefaults.dockVisibility)
    private var dockVisibility = "both"

    // MARK: - State

    /// Twitch settings view model
    @StateObject private var twitchViewModel = TwitchViewModel()

    // Helper to get the shared Twitch service from AppDelegate
    private var appDelegate: AppDelegate? {
        NSApplication.shared.delegate as? AppDelegate
    }

    /// Controls the display of the reset confirmation alert
    @State private var showingResetAlert = false
    
    /// Currently selected settings section
    @State private var selectedSection: SettingsSection = .musicMonitor
    
    /// Controls sidebar visibility
    @State private var sidebarVisibility: NavigationSplitViewVisibility = .all

    var body: some View {
        NavigationSplitView(columnVisibility: $sidebarVisibility) {
            List(SettingsSection.allCases, selection: $selectedSection) { section in
                sidebarRow(for: section)
                    .tag(section)
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 180, ideal: 200, max: 220)
            .padding(.top, 10)
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

            // Apply bot command settings to service
            appDelegate?.twitchService?.currentSongCommandEnabled = currentSongCommandEnabled
            appDelegate?.twitchService?.lastSongCommandEnabled = lastSongCommandEnabled

            // Initialize the view model's connection state from the service so the UI
            // reflects whether we are already joined (prevents missed callbacks).
            twitchViewModel.channelConnected = appDelegate?.twitchService?.isConnected ?? false

            // Set up callback to get current song info
            appDelegate?.twitchService?.getCurrentSongInfo = {
                if let appDelegate = NSApplication.shared.delegate as? AppDelegate {
                    return appDelegate.getCurrentSongInfo()
                }
                return "No track currently playing"
            }
            
            // Set up callback to get last song info
            appDelegate?.twitchService?.getLastSongInfo = {
                if let appDelegate = NSApplication.shared.delegate as? AppDelegate {
                    return appDelegate.getLastSongInfo()
                }
                return "No previous track available"
            }
        }
        .toolbar(removing: .sidebarToggle)
        .navigationSplitViewStyle(.balanced)
        .alert("Reset Settings?", isPresented: $showingResetAlert) {
            Button("Cancel", role: .cancel) {}
            .accessibilityIdentifier("resetSettingsCancelButton")

            Button("Reset", role: .destructive) {
                resetSettings()
            }
            .accessibilityIdentifier("resetSettingsConfirmButton")
        } message: {
            Text("This will reset all settings and clear the stored authentication token.")
        }
    }
    
    // MARK: - Detail Views
    
    @ViewBuilder
    private func detailView(for section: SettingsSection) -> some View {
        switch section {
        case .musicMonitor:
            MusicMonitorSettingsView()
        case .appVisibility:
            AppVisibilitySettingsView()
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

    @ViewBuilder
    private func sidebarRow(for section: SettingsSection) -> some View {
        Label {
            Text(section.rawValue)
        } icon: {
            sidebarIcon(for: section)
        }
        .accessibilityLabel(Text(section.rawValue))
        .accessibilityIdentifier(section.rawValue.replacingOccurrences(of: " ", with: "-").lowercased())
    }

    @ViewBuilder
    private func sidebarIcon(for section: SettingsSection) -> some View {
        if let customIcon = section.customIcon {
            Image(customIcon)
                .renderingMode(.template)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 16, height: 16)
        } else if let systemIcon = section.systemIcon {
            Image(systemName: systemIcon)
        }
    }
    
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
                            .font(.system(size: 15, weight: .semibold))
                    }

                    Text("Control which commands your viewers can use in chat.")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }

                VStack(spacing: 1) {
                    commandToggleRow(
                        title: "Now Playing Command",
                        subtitle: "Viewers type !song to see what's playing",
                        isOn: $currentSongCommandEnabled,
                        accessibilityLabel: "Enable Current Playing Song command",
                        accessibilityIdentifier: "currentSongCommandToggle",
                        isFirst: true
                    ) { enabled in
                        appDelegate?.twitchService?.currentSongCommandEnabled = enabled
                        Log.info("SettingsView: Current Song Command \(enabled ? "enabled" : "disabled")", category: "Twitch")
                    }

                    commandToggleRow(
                        title: "Previous Song Command",
                        subtitle: "Viewers type !last to see the previous track",
                        isOn: $lastSongCommandEnabled,
                        accessibilityLabel: "Enable Last Played Song command",
                        accessibilityIdentifier: "lastSongCommandToggle",
                        isLast: true
                    ) { enabled in
                        appDelegate?.twitchService?.lastSongCommandEnabled = enabled
                        Log.info("SettingsView: Last Song Command \(enabled ? "enabled" : "disabled")", category: "Twitch")
                    }
                }
                .background(Color(nsColor: .controlBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: AppConstants.SettingsUI.cardCornerRadius))
            }
        }
    }

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
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Toggle("", isOn: isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
                .pointerCursor()
                .accessibilityLabel(accessibilityLabel)
                .accessibilityIdentifier(accessibilityIdentifier)
                .onChange(of: isOn.wrappedValue) { _, newValue in
                    onChange(newValue)
                }
        }
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

    // MARK: - Helpers

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
        // Clear UserDefaults
        [AppConstants.UserDefaults.trackingEnabled, AppConstants.UserDefaults.currentSongCommandEnabled, AppConstants.UserDefaults.lastSongCommandEnabled, AppConstants.UserDefaults.dockVisibility, AppConstants.UserDefaults.websocketEnabled, AppConstants.UserDefaults.websocketURI, AppConstants.UserDefaults.hasCompletedOnboarding, AppConstants.UserDefaults.discordPresenceEnabled].forEach {
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

// MARK: - Constants Extension



// MARK: - StatusChip

private struct StatusChip: View {
    let text: String
    let color: Color

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(color)
                .frame(width: 6, height: 6)

            Text(text)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.primary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(color.opacity(0.1))
        .clipShape(Capsule())
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
