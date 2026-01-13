//
//  SettingsView.swift
//  wolfwave
//
//  Created by MrDemonWolf, Inc. on 1/8/26.
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
        static let defaultAppName = "WolfWave"
        static let minWidth: CGFloat = 700
        static let minHeight: CGFloat = 500
        static let sidebarWidth: CGFloat = 200
        static let validSchemes = ["ws", "wss", "http", "https"]

        enum UserDefaultsKeys {
            static let trackingEnabled = "trackingEnabled"
            static let websocketEnabled = "websocketEnabled"
            static let websocketURI = "websocketURI"
            static let currentSongCommandEnabled = "currentSongCommandEnabled"
            static let dockVisibility = "dockVisibility"
        }

        enum Notifications {
            static let trackingSettingChanged = "TrackingSettingChanged"
        }
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
            .infoDictionary?["CFBundleName"] as? String ?? Constants.defaultAppName
    }

    // MARK: - User Settings

    /// Whether music tracking is currently enabled
    @AppStorage(Constants.UserDefaultsKeys.trackingEnabled)
    private var trackingEnabled = true

    /// Whether the Current Song command is enabled
    @AppStorage(Constants.UserDefaultsKeys.currentSongCommandEnabled)
    private var currentSongCommandEnabled = false

    @AppStorage(Constants.UserDefaultsKeys.dockVisibility)
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
            // Sidebar
            List(SettingsSection.allCases, selection: $selectedSection) { section in
                if let customIcon = section.customIcon {
                    Label {
                        Text(section.rawValue)
                    } icon: {
                        Image(customIcon)
                            .renderingMode(.original)
                            .resizable()
                            .interpolation(.high)
                            .scaledToFit()
                            .frame(width: 16, height: 16)
                    }
                    .tag(section)
                } else if let systemIcon = section.systemIcon {
                    Label(section.rawValue, systemImage: systemIcon)
                        .tag(section)
                }
            }
            .navigationSplitViewColumnWidth(Constants.sidebarWidth)
            .listStyle(.sidebar)
        } detail: {
            // Detail view
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    detailView(for: selectedSection)
                }
                .padding(20)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
            .background(.ultraThinMaterial)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button(action: {
                        withAnimation(.easeInOut(duration: 0.25)) {
                            sidebarVisibility = sidebarVisibility == .all ? .detailOnly : .all
                        }
                    }) {
                        Image(systemName: sidebarVisibility == .all ? "sidebar.left" : "sidebar.leading")
                    }
                }
            }
        }
        .frame(minWidth: Constants.minWidth, minHeight: Constants.minHeight)
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
            // Initialize Twitch view model
            twitchViewModel.twitchService = appDelegate?.twitchService
            twitchViewModel.loadSavedCredentials()

            // Apply bot command toggle to service
            appDelegate?.twitchService?.commandsEnabled = currentSongCommandEnabled

            // Set up Twitch service callbacks
            appDelegate?.twitchService?.onConnectionStateChanged = { isConnected in
                DispatchQueue.main.async {
                    twitchViewModel.channelConnected = isConnected
                }
            }

            // Set up callback to get current song info
            appDelegate?.twitchService?.getCurrentSongInfo = {
                if let appDelegate = NSApplication.shared.delegate as? AppDelegate {
                    return appDelegate.getCurrentSongInfo()
                }
                return "No track currently playing"
            }

            // Auto-join channel if credentials are saved and channel is set
            if twitchViewModel.credentialsSaved && !twitchViewModel.channelID.isEmpty
                && !twitchViewModel.channelConnected
            {
                Log.info(
                    "SettingsView: Auto-joining Twitch channel \(twitchViewModel.channelID)",
                    category: "Settings")
                twitchViewModel.joinChannel()
            }
        }
        .alert("Reset Settings?", isPresented: $showingResetAlert) {
            Button("Cancel", role: .cancel) {}
            Button("Reset", role: .destructive) {
                resetSettings()
            }
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
    
    private func twitchIntegrationView() -> some View {
        VStack(alignment: .leading, spacing: 24) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Image("TwitchLogo")
                        .renderingMode(.original)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 18, height: 18)
                    Text("Twitch Integration")
                        .font(.title2)
                        .fontWeight(.semibold)
                    Spacer()
                    StatusChip(text: twitchViewModel.statusChipText, color: twitchViewModel.statusChipColor)
                }
            }
            
            // Twitch Bot Connection
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
                        Text("Current Song")
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
                        .onChange(of: currentSongCommandEnabled) { _, enabled in
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
            name: NSNotification.Name(Constants.Notifications.trackingSettingChanged),
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
        Constants.UserDefaultsKeys.allKeys.forEach {
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

extension SettingsView.Constants.UserDefaultsKeys {
    static var allKeys: [String] {
        [trackingEnabled, currentSongCommandEnabled, dockVisibility, websocketEnabled, websocketURI]
    }
}

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
