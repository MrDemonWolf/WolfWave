//
//  WebSocketSettingsView.swift
//  wolfwave
//
//  Created by MrDemonWolf, Inc. on 1/17/26.
//

import SwiftUI

/// WebSocket settings interface for configuring now playing data transmission.
struct WebSocketSettingsView: View {
    // MARK: - Constants
    
    private enum Constants {
        static let validSchemes = ["ws", "wss"]
    }
    
    // MARK: - User Settings
    
    /// Whether WebSocket reporting is enabled
    @AppStorage("websocketEnabled")
    private var websocketEnabled = false
    
    /// The WebSocket server URI (ws:// or wss://)
    @AppStorage("websocketURI")
    private var websocketURI: String?
    
    // MARK: - State
    
    /// The authentication token (JWT) for WebSocket connections.
    @State private var authToken: String = ""
    
    /// Indicates whether the token has been successfully saved to Keychain
    @State private var tokenSaved = false
    
    // MARK: - Validation
    
    /// Validates the WebSocket URI format.
    private var isWebSocketURLValid: Bool {
        guard let uri = websocketURI, !uri.isEmpty else {
            return false
        }
        return isValidWebSocketURL(uri)
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Work in Progress Banner
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "exclamationmark.circle.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(.orange)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Work in Progress")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.orange)
                    Text("This feature is under development and will be available in a future update.")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.orange.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .allowsHitTesting(false)

            // Section Header
            VStack(alignment: .leading, spacing: 6) {
                Text("WebSocket Overlay")
                    .font(.system(size: 17, weight: .semibold))

                Text("Stream your now-playing data to a browser overlay or external server in real time.")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }

            // Server Configuration Card
            VStack(alignment: .leading, spacing: 12) {
                Text("Server Connection")
                    .font(.system(size: 13, weight: .medium))

                TextField("WebSocket server URL (ws:// or wss://)", text: websocketURIBinding)
                    .textFieldStyle(.roundedBorder)
                    .disabled(true)
                    .accessibilityLabel("WebSocket server URL")
                    .accessibilityHint("Enter the full WebSocket server URL, for example ws://example.com")
                    .accessibilityIdentifier("websocketUrlTextField")

                if !isWebSocketURLValid && !(websocketURI?.isEmpty ?? true) {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.circle.fill")
                            .font(.system(size: 11))
                        Text("Please enter a valid WebSocket URL (ws:// or wss://).")
                            .font(.system(size: 11))
                    }
                    .foregroundStyle(.red)
                }

                if !isWebSocketURLValid {
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "info.circle.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(.blue)
                        Text("Add a WebSocket URL to enable this feature.")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.blue.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                }

                Divider()
                    .padding(.vertical, 4)

                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("WebSocket Broadcasting")
                            .font(.system(size: 13, weight: .medium))
                        Text("Sends track info to connected overlays and servers")
                            .font(.system(size: 11))
                            .foregroundStyle(.tertiary)
                    }
                    Spacer()
                    Toggle("", isOn: $websocketEnabled)
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .controlSize(.small)
                        .disabled(true)
                        .accessibilityLabel("Enable WebSocket connection")
                        .accessibilityIdentifier("websocketEnabledToggle")
                }
            }
            .cardStyle()
            .allowsHitTesting(false)

            Divider()
                .padding(.vertical, 4)

            // Authentication Section
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        Image(systemName: "lock.fill")
                            .font(.system(size: 14))
                            .foregroundStyle(.secondary)
                        Text("Authentication")
                            .font(.system(size: 15, weight: .semibold))
                    }

                    Text("Required only if your server expects a token for connections.")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }

                VStack(alignment: .leading, spacing: 12) {
                    SecureField("Auth token (JWT)", text: $authToken)
                        .textFieldStyle(.roundedBorder)
                        .disabled(true)
                        .accessibilityLabel("Authentication token")
                        .accessibilityHint("Paste your JWT authentication token for the WebSocket server")
                        .accessibilityIdentifier("websocketAuthTokenField")

                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "lock.shield.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(.green)
                        Text("Tokens are stored securely in your Mac's Keychain")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.green.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 6))

                    HStack(spacing: 8) {
                        Button("Save Token") {
                            saveToken()
                        }
                        .disabled(true)
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .accessibilityLabel("Save authentication token")
                        .accessibilityIdentifier("saveWebsocketTokenButton")

                        Button("Clear Token") {
                            clearToken()
                        }
                        .disabled(true)
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .tint(.red)
                        .accessibilityLabel("Clear authentication token")
                        .accessibilityIdentifier("clearWebsocketTokenButton")

                        if tokenSaved {
                            HStack(spacing: 4) {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.green)
                                Text("Saved")
                                    .font(.system(size: 11))
                                    .foregroundStyle(.green)
                            }
                            .padding(.leading, 4)
                            .accessibilityElement(children: .combine)
                            .accessibilityLabel("Token saved")
                            .accessibilityIdentifier("websocketTokenSavedStatus")
                        }

                        Spacer()
                    }
                }
                .cardStyle()
                .allowsHitTesting(false)
            }
        }
        .onAppear {
            if let savedToken = KeychainService.loadToken() {
                authToken = savedToken
                tokenSaved = true
            }

            if !isWebSocketURLValid {
                websocketEnabled = false
            }
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
}

// MARK: - Preview

#Preview {
    WebSocketSettingsView()
        .padding()
}
