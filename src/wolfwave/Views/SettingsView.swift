//
//  SettingsView.swift
//  wolfwave
//
//  Created by MrDemonWolf, Inc. on 1/17/26.
//

import AppKit
import SwiftUI

/// The main settings interface for WolfWave.
///
/// This view provides controls for:
/// - Enabling/disabling music tracking
/// - Configuring WebSocket connection for remote tracking
/// - Managing authentication tokens (stored in Keychain)
/// - Resetting all settings to defaults
struct SettingsView: View {
    // MARK: - Constants

    fileprivate enum Constants {
        static let validSchemes = ["ws", "wss", "http", "https"]
    }
    
    // MARK: - Sidebar Navigation
    
    enum SettingsSection: String, CaseIterable, Identifiable {
        case musicMonitor = "Music Monitor"
        case appVisibility = "App Visibility"
        case websocket = "WebSocket"
        case twitchIntegration = "Twitch Integration"
        case advanced = "Advanced"
        
        var id: String { rawValue }
        
        var systemIcon: String? {
            switch self {
            case .musicMonitor: return "music.note"
            case .appVisibility: return "eye"
            case .websocket: return "dot.radiowaves.left.and.right"
            case .twitchIntegration: return nil // Uses custom image
            case .advanced: return "gearshape"
            }
        }
        
        var customIcon: String? {
            switch self {
            case .twitchIntegration: return "TwitchLogo"
            default: return nil
            }
        }
    }

    // MARK: - Properties

    /// Retrieves the app name from the bundle
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

    // Smoother animation for showing/hiding the sidebar
    private var sidebarAnimation: Animation {
        if #available(macOS 14.0, *) {
            return .snappy(duration: 0.32, extraBounce: 0)
        } else {
            return .easeInOut(duration: 0.28)
        }
    }

    var body: some View {
        NavigationSplitView(columnVisibility: $sidebarVisibility) {
            List(SettingsSection.allCases, selection: $selectedSection) { section in
                sidebarRow(for: section)
                    .tag(section)
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 180, ideal: 200, max: 220)
        } detail: {
            // Detail view
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    detailView(for: selectedSection)
                }
                .padding(.vertical, 20)
                .padding(.horizontal, 12)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
            .background(.ultraThinMaterial)
            .onAppear {
                // Check if a specific section was requested to be opened
                if let requestedSection = UserDefaults.standard.string(forKey: AppConstants.UserDefaults.selectedSettingsSection) {
                    if requestedSection == AppConstants.Twitch.settingsSection {
                        selectedSection = .twitchIntegration
                    }
                    // Clear the request after using it
                    UserDefaults.standard.removeObject(forKey: AppConstants.UserDefaults.selectedSettingsSection)
                }
            }
            // Rely on the system-provided sidebar toggle for NavigationSplitView
        }
        .animation(sidebarAnimation, value: sidebarVisibility)
        .frame(minWidth: AppConstants.SettingsUI.minWidth, minHeight: AppConstants.SettingsUI.minHeight)
        .keyboardShortcut("w", modifiers: .command)
        .onKeyPress { keyPress in
            if keyPress.key == .escape || (keyPress.modifiers.contains(.command) && keyPress.key.character == "w") {
                if sidebarVisibility == .all {
                    sidebarVisibility = .detailOnly
                }
                return .handled
            }
            return .ignored
        }
        .onAppear {
            // Link the view model to the app delegate's service (without reconnecting)
            twitchViewModel.twitchService = appDelegate?.twitchService

            // Apply bot command toggle to service
            appDelegate?.twitchService?.commandsEnabled = currentSongCommandEnabled

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
        }
        // Listen for toggle requests from the AppDelegate toolbar button
        .onReceive(NotificationCenter.default.publisher(for: .toggleSettingsSidebar)) { _ in
            withAnimation(.easeInOut(duration: 0.25)) {
                sidebarVisibility = sidebarVisibility == .all ? .detailOnly : .all
            }
        }
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
                .interpolation(.high)
                .scaledToFit()
                .frame(width: 16, height: 16)
        } else if let systemIcon = section.systemIcon {
            Image(systemName: systemIcon)
        }
    }
    
    private func twitchIntegrationView() -> some View {
        VStack(alignment: .leading, spacing: 24) {
            // Use the inner header inside `TwitchSettingsView` — remove outer duplicated header.
            TwitchSettingsView(viewModel: twitchViewModel)
            
            Divider()
            
            // Bot Commands
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        Image(systemName: "bubble.left.fill")
                            .font(.title3)
                            .foregroundStyle(Color(nsColor: .controlAccentColor))
                        Text("Bot Commands")
                            .font(.headline)
                    }
                    
                    Text("Choose which chat commands the bot responds to in Twitch chat.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Current Playing Song")
                            .font(.body)
                            .fontWeight(.medium)
                        Text("!song, !currentsong, !nowplaying")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Toggle("", isOn: $currentSongCommandEnabled)
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .accessibilityLabel("Enable Current Playing Song command")
                        .accessibilityIdentifier("currentSongCommandToggle")
                        .onChange(of: currentSongCommandEnabled) { _, enabled in
                            appDelegate?.twitchService?.commandsEnabled = enabled
                        }
                }
                .padding(12)
                .background(Color(nsColor: .controlBackgroundColor))
                .cornerRadius(8)

                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Last Played Song")
                            .font(.body)
                            .fontWeight(.medium)
                        Text("!last, !lastsong, !prevsong")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Toggle("", isOn: $lastSongCommandEnabled)
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .accessibilityLabel("Enable Last Played Song command")
                        .accessibilityIdentifier("lastSongCommandToggle")
                        .onChange(of: lastSongCommandEnabled) { _, enabled in
                            appDelegate?.twitchService?.commandsEnabled = enabled
                        }
                }
                .padding(12)
                .background(Color(nsColor: .controlBackgroundColor))
                .cornerRadius(8)
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
        [AppConstants.UserDefaults.trackingEnabled, AppConstants.UserDefaults.currentSongCommandEnabled, AppConstants.UserDefaults.lastSongCommandEnabled, AppConstants.UserDefaults.dockVisibility, AppConstants.UserDefaults.websocketEnabled, AppConstants.UserDefaults.websocketURI].forEach {
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



// MARK: - StatusChip and Helpers

private struct StatusChip: View {
    let text: String
    let color: Color

    var body: some View {
        Text(text)
            .font(.caption2).bold()
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .foregroundColor(color)
            .background(color.opacity(0.15))
            .clipShape(Capsule())
    }
}

// MARK: - Preview

#Preview {
    SettingsView()
        .frame(minWidth: 700, minHeight: 500)
}
