//
//  SettingsView.swift
//  packtrack
//
//  Created by Nathanial Henniges on 1/8/26.
//

import SwiftUI

/// The main settings interface for PackTrack.
///
/// This view provides controls for:
/// - Enabling/disabling music tracking
/// - Configuring WebSocket connection for remote tracking
/// - Managing authentication tokens (stored in Keychain)
/// - Resetting all settings to defaults
struct SettingsView: View {
    // MARK: - Properties
    
    /// Retrieves the app name from the bundle
    private var appName: String {
        Bundle.main.infoDictionary?["CFBundleDisplayName"] as? String ??
        Bundle.main.infoDictionary?["CFBundleName"] as? String ??
        "Pack Track"
    }

    // MARK: - User Settings
    
    /// Whether music tracking is currently enabled
    @AppStorage("trackingEnabled") private var trackingEnabled = true
    
    /// Whether WebSocket reporting is enabled
    @AppStorage("websocketEnabled") private var websocketEnabled = false
    
    /// The WebSocket server URI (ws:// or wss://)
    @AppStorage("websocketURI") private var websocketURI: String?

    // MARK: - State
    
    /// The authentication token (JWT) for WebSocket connections.
    /// Temporarily held in memory and saved to Keychain when user clicks "Save Token".
    @State private var authToken: String = ""
    
    /// Indicates whether the token has been successfully saved to Keychain
    @State private var tokenSaved = false

    /// Controls the display of the reset confirmation alert
    @State private var showingResetAlert = false

    // MARK: - Validation
    
    /// Validates the WebSocket URI format.
    ///
    /// Ensures the URI has a valid scheme (ws, wss, http, or https) and can be parsed as a URL.
    /// - Returns: true if the URI is valid, false otherwise
    private var isWebSocketURLValid: Bool {
        guard
            let uri = websocketURI,
            let url = URL(string: uri),
            let scheme = url.scheme,
            ["ws", "wss", "http", "https"].contains(scheme.lowercased())
        else {
            return false
        }
        return true
    }

    var body: some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 20) {

                // MARK: Header
                Text("Settings")
                    .font(.title)

                Divider()

                // MARK: Tracking
                GroupBox(label: Label("Tracking", systemImage: "music.note")) {
                    VStack(alignment: .leading, spacing: 12) {

                        Toggle("Enable Music Tracking", isOn: $trackingEnabled)
                            .onChange(of: trackingEnabled) { _, newValue in
                                NotificationCenter.default.post(
                                    name: NSNotification.Name("TrackingSettingChanged"),
                                    object: nil,
                                    userInfo: ["enabled": newValue]
                                )
                            }

                        Text("When enabled, Pack Track will monitor and display your currently playing Apple Music tracks.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(8)
                }

                // MARK: WebSocket
                GroupBox(label: Label("WebSocket", systemImage: "dot.radiowaves.left.and.right")) {
                    VStack(alignment: .leading, spacing: 12) {

                        Toggle("Enable WebSocket Tracking", isOn: $websocketEnabled)
                            .disabled(!isWebSocketURLValid)

                        TextField(
                            "WebSocket Server URI",
                            text: Binding(
                                get: { websocketURI ?? "" },
                                set: { newValue in
                                    websocketURI = newValue

                                    // Auto-disable if URL becomes invalid
                                    if !isWebSocketURLValid {
                                        websocketEnabled = false
                                    }
                                }
                            )
                        )
                        .textFieldStyle(.roundedBorder)

                        if !isWebSocketURLValid {
                            Text("Enter a valid WebSocket URL (ws:// or wss://) to enable.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }

                        SecureField("Auth Token (JWT)", text: $authToken)

                        HStack {
                            Button("Save Token") {
                                do {
                                    try KeychainService.saveToken(authToken)
                                    tokenSaved = true
                                } catch {
                                    tokenSaved = false
                                }
                            }
                            .disabled(authToken.isEmpty)

                            Button("Clear Token") {
                                KeychainService.deleteToken()
                                authToken = ""
                                tokenSaved = false
                            }
                            .foregroundColor(.red)
                        }

                        if tokenSaved {
                            Label(
                                "Token stored securely in macOS Keychain",
                                systemImage: "checkmark.seal.fill"
                            )
                            .font(.caption)
                            .foregroundColor(.green)
                        }

                        Text("The authentication token is stored securely in macOS Keychain and is never saved to disk or UserDefaults.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(8)
                }

                Spacer(minLength: 10)

                Divider()

                // MARK: Reset
                HStack {
                    Spacer()
                    Button("Reset to Defaults") {
                        showingResetAlert = true
                    }
                    .foregroundColor(.red)
                }
            }
            .padding()
        }
        .frame(minWidth: 520, minHeight: 560)
        .onAppear {
            if let savedToken = KeychainService.loadToken() {
                authToken = savedToken
                tokenSaved = true
            }

            if !isWebSocketURLValid {
                websocketEnabled = false
            }
        }
        .alert("Reset Settings?", isPresented: $showingResetAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Reset", role: .destructive) {
                resetSettings()
            }
        } message: {
            Text("This will reset all settings and clear the stored authentication token.")
        }
    }

    // MARK: - Helpers
    
    /// Resets all settings to their default values and clears the stored token.
    ///
    /// This method:
    /// 1. Removes all user preferences from UserDefaults
    /// 2. Resets in-memory state to defaults
    /// 3. Deletes the authentication token from Keychain
    /// 4. Notifies the app that tracking has been re-enabled
    private func resetSettings() {
        UserDefaults.standard.removeObject(forKey: "trackingEnabled")
        UserDefaults.standard.removeObject(forKey: "websocketEnabled")
        UserDefaults.standard.removeObject(forKey: "websocketURI")

        trackingEnabled = true
        websocketEnabled = false
        websocketURI = nil

        KeychainService.deleteToken()
        authToken = ""
        tokenSaved = false

        NotificationCenter.default.post(
            name: NSNotification.Name("TrackingSettingChanged"),
            object: nil,
            userInfo: ["enabled": true]
        )
    }
}
