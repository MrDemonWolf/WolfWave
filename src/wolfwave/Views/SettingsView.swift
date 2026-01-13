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
        static let minWidth: CGFloat = 600
        static let minHeight: CGFloat = 550
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

    /// Whether WebSocket reporting is enabled
    @AppStorage(Constants.UserDefaultsKeys.websocketEnabled)
    private var websocketEnabled = false

    /// The WebSocket server URI (ws:// or wss://)
    @AppStorage(Constants.UserDefaultsKeys.websocketURI)
    private var websocketURI: String?

    /// Whether the Current Song command is enabled
    @AppStorage(Constants.UserDefaultsKeys.currentSongCommandEnabled)
    private var currentSongCommandEnabled = false

    @AppStorage(Constants.UserDefaultsKeys.dockVisibility)
    private var dockVisibility = "both"

    // MARK: - State

    /// The authentication token (JWT) for WebSocket connections.
    /// Temporarily held in memory and saved to Keychain when user clicks "Save Token".
    @State private var authToken: String = ""

    /// Indicates whether the token has been successfully saved to Keychain
    @State private var tokenSaved = false

    /// Twitch settings view model
    @StateObject private var twitchViewModel = TwitchViewModel()

    // Helper to get the shared Twitch service from AppDelegate
    private var appDelegate: AppDelegate? {
        NSApplication.shared.delegate as? AppDelegate
    }

    /// Controls the display of the reset confirmation alert
    @State private var showingResetAlert = false

    // MARK: - Validation

    /// Validates the WebSocket URI format.
    ///
    /// Ensures the URI has a valid scheme (ws, wss, http, or https) and can be parsed as a URL.
    /// - Returns: true if the URI is valid, false otherwise
    private var isWebSocketURLValid: Bool {
        guard let uri = websocketURI, !uri.isEmpty else {
            return false
        }
        return isValidWebSocketURL(uri)
    }

    var body: some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 16) {

                // MARK: Header
                Text("Settings")
                    .font(.title)

                Divider()

                // MARK: Tracking
                GroupBox(
                    label: Label("Music Playback Monitor", systemImage: "music.note").font(
                        .headline
                    )
                    .padding(.bottom, 4)
                ) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Monitor your Apple Music playback to display in the menu bar and share with external services like Twitch or custom WebSocket endpoints.")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        HStack {
                            Text("Enable Apple Music monitoring")
                            Spacer()
                            Toggle("", isOn: $trackingEnabled)
                                .labelsHidden()
                                .toggleStyle(.switch)
                                .onChange(of: trackingEnabled) { _, newValue in
                                    notifyTrackingSettingChanged(enabled: newValue)
                                }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Divider()

                // MARK: App Visibility
                GroupBox(
                    label: Label("App Visibility", systemImage: "eye")
                        .font(.headline)
                        .padding(.bottom, 4)
                ) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Choose where WolfWave appears on your Mac.")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        Picker("Show app in:", selection: $dockVisibility) {
                            Text("Dock and Menu Bar").tag("both")
                            Text("Menu Bar Only").tag("menuOnly")
                            Text("Dock Only").tag("dockOnly")
                        }
                        .pickerStyle(.radioGroup)
                        .onChange(of: dockVisibility) { _, newValue in
                            applyDockVisibility(newValue)
                        }

                        if dockVisibility == "menuOnly" {
                            Text("When menu bar only is enabled, the app will appear in the dock when settings are open.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                Divider()

                // MARK: WebSocket
                GroupBox(
                    label: Label(
                        "Now Playing WebSocket", systemImage: "dot.radiowaves.left.and.right"
                    )
                    .font(.headline)
                    .padding(.bottom, 4)
                ) {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Send your now playing info to an overlay or server via WebSocket.")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        VStack(alignment: .leading, spacing: 8) {
                            TextField("WebSocket server URL (ws:// or wss://)", text: websocketURIBinding)
                                .textFieldStyle(.roundedBorder)

                            if !isWebSocketURLValid && !(websocketURI?.isEmpty ?? true) {
                                Text("Please enter a valid WebSocket URL (ws:// or wss://).")
                                    .font(.caption)
                                    .foregroundStyle(.red)
                            }
                        }

                        HStack {
                            Text("Enable WebSocket connection")
                            Spacer()
                            Toggle("", isOn: $websocketEnabled)
                                .labelsHidden()
                                .toggleStyle(.switch)
                                .disabled(!isWebSocketURLValid)
                        }

                        if !isWebSocketURLValid {
                            Text("Add a WebSocket URL to enable this feature.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Divider()
                            .padding(.vertical, 4)

                        VStack(alignment: .leading, spacing: 8) {
                            Text("Authentication (Optional)")
                                .font(.caption)
                                .fontWeight(.medium)
                                .foregroundStyle(.secondary)

                            SecureField("Auth token (JWT)", text: $authToken)
                                .textFieldStyle(.roundedBorder)

                            HStack(spacing: 8) {
                                Button("Save Token") {
                                    saveToken()
                                }
                                .disabled(authToken.isEmpty)
                                .buttonStyle(.bordered)

                                Button("Clear Token") {
                                    clearToken()
                                }
                                .disabled(!tokenSaved && authToken.isEmpty)
                                .buttonStyle(.bordered)
                                .foregroundColor(.red)

                                if tokenSaved {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundColor(.green)
                                        .imageScale(.medium)
                                }
                            }

                            Text("Only required if your WebSocket server uses authentication.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(10)
                }

                Divider()

                // MARK: Twitch Bot
                TwitchSettingsView(viewModel: twitchViewModel)

                Divider()

                // MARK: Twitch Bot Commands
                GroupBox(
                    label: Label("Bot Commands", systemImage: "command").font(.headline).padding(
                        .bottom, 4)
                ) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Choose which chat commands the bot responds to in Twitch chat.")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        HStack {
                            Text("Current Song")
                            Spacer()
                            Toggle("", isOn: $currentSongCommandEnabled)
                                .labelsHidden()
                                .toggleStyle(.switch)
                                .onChange(of: currentSongCommandEnabled) { _, enabled in
                                    appDelegate?.twitchService?.commandsEnabled = enabled
                                }
                        }

                        Text(
                            "When enabled, the bot will respond to !song, !currentsong, and !nowplaying in Twitch chat with the currently playing Apple Music track."
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                Spacer(minLength: 10)

                Divider()

                // MARK: Reset
                HStack {
                    Button("Reset to Defaults") {
                        showingResetAlert = true
                    }
                    .buttonStyle(.bordered)
                    .foregroundColor(.red)
                    Spacer()
                }
                .padding(.top, 4)
            }
            .padding()
        }
        .background(.ultraThinMaterial)
        .frame(minWidth: Constants.minWidth, minHeight: Constants.minHeight)
        .onAppear {
            if let savedToken = KeychainService.loadToken() {
                authToken = savedToken
                tokenSaved = true
            }

            if !isWebSocketURLValid {
                websocketEnabled = false
            }

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

    // MARK: - Computed Properties

    private var websocketURIBinding: Binding<String> {
        Binding(
            get: { websocketURI ?? "" },
            set: { newValue in
                websocketURI = newValue
                if !isWebSocketURLValid {
                    websocketEnabled = false
                }
            }
        )
    }

    // MARK: - Helpers

    private func isValidWebSocketURL(_ urlString: String) -> Bool {
        guard let url = URL(string: urlString),
            let scheme = url.scheme?.lowercased()
        else {
            return false
        }
        return Constants.validSchemes.contains(scheme)
    }

    private func notifyTrackingSettingChanged(enabled: Bool) {
        NotificationCenter.default.post(
            name: NSNotification.Name(Constants.Notifications.trackingSettingChanged),
            object: nil,
            userInfo: ["enabled": enabled]
        )
    }

    private func saveToken() {
        do {
            try KeychainService.saveToken(authToken)
            tokenSaved = true
        } catch {
            tokenSaved = false
        }
    }

    private func clearToken() {
        KeychainService.deleteToken()
        authToken = ""
        tokenSaved = false
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
        websocketEnabled = false
        websocketURI = nil
        dockVisibility = "both"

        // Clear tokens
        clearToken()
        twitchViewModel.clearCredentials()

        // Disconnect from Twitch
        twitchViewModel.leaveChannel()

        // Notify tracking re-enabled
        notifyTrackingSettingChanged(enabled: true)
    }

    private func applyDockVisibility(_ mode: String) {
        NotificationCenter.default.post(
            name: NSNotification.Name("DockVisibilityChanged"),
            object: nil,
            userInfo: ["mode": mode]
        )
    }
}

// MARK: - Constants Extension

extension SettingsView.Constants.UserDefaultsKeys {
    static var allKeys: [String] {
        [trackingEnabled, websocketEnabled, websocketURI, currentSongCommandEnabled, dockVisibility]
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
