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
        VStack(alignment: .leading, spacing: 24) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.orange)
                    Text("Work in Progress")
                        .font(.title2)
                        .fontWeight(.semibold)
                        .foregroundStyle(.orange)
                }
                
                Text("This feature is currently not supported and will be added in a future release.")
                    .font(.body)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(Color.orange.opacity(0.1))
            .cornerRadius(8)
            .onHover { isInside in
                if isInside {
                    NSCursor.operationNotAllowed.push()
                } else {
                    NSCursor.pop()
                }
            }
            
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Image(systemName: "dot.radiowaves.left.and.right")
                        .font(.title3)
                    Text("Now Playing WebSocket")
                        .font(.title2)
                        .fontWeight(.semibold)
                }
                
                Text("Send your now playing info to an overlay or server via WebSocket.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            
            Divider()
            
            VStack(alignment: .leading, spacing: 12) {
                Text("Server Configuration")
                    .font(.body)
                    .fontWeight(.medium)
                
                VStack(alignment: .leading, spacing: 8) {
                    TextField("WebSocket server URL (ws:// or wss://)", text: websocketURIBinding)
                        .textFieldStyle(.roundedBorder)
                        .disabled(true)
                        .accessibilityLabel("WebSocket server URL")
                        .accessibilityHint("Enter the full WebSocket server URL, for example ws://example.com")
                        .accessibilityIdentifier("websocketUrlTextField")
                        .onHover { isInside in
                            if isInside {
                                NSCursor.operationNotAllowed.push()
                            } else {
                                NSCursor.pop()
                            }
                        }

                    if !isWebSocketURLValid && !(websocketURI?.isEmpty ?? true) {
                        HStack(spacing: 6) {
                            Image(systemName: "exclamationmark.circle.fill")
                                .font(.caption)
                            Text("Please enter a valid WebSocket URL (ws:// or wss://).")
                                .font(.caption)
                        }
                        .foregroundStyle(.red)
                    }
                }
                
                if !isWebSocketURLValid {
                    HStack(spacing: 8) {
                        Image(systemName: "info.circle.fill")
                            .font(.caption)
                            .foregroundStyle(.blue)
                        Text("Add a WebSocket URL to enable this feature.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(Color.blue.opacity(0.1))
                    .cornerRadius(8)
                }
                
                HStack {
                    Text("Enable WebSocket connection")
                        .font(.body)
                    Spacer()
                    Toggle("", isOn: $websocketEnabled)
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .disabled(true)
                        .accessibilityLabel("Enable WebSocket connection")
                        .accessibilityIdentifier("websocketEnabledToggle")
                        .onHover { isInside in
                            if isInside {
                                NSCursor.operationNotAllowed.push()
                            } else {
                                NSCursor.pop()
                            }
                        }
                }
                .padding(12)
                .background(Color(nsColor: .controlBackgroundColor))
                .cornerRadius(8)
            }

            Divider()
            
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        Image(systemName: "lock.fill")
                            .font(.title3)
                            .foregroundStyle(.secondary)
                        Text("Authentication (Optional)")
                            .font(.headline)
                    }
                    
                    Text("Only required if your WebSocket server uses authentication.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                SecureField("Auth token (JWT)", text: $authToken)
                    .textFieldStyle(.roundedBorder)
                    .disabled(true)
                    .accessibilityLabel("Authentication token")
                    .accessibilityHint("Paste your JWT authentication token for the WebSocket server")
                    .accessibilityIdentifier("websocketAuthTokenField")
                    .onHover { isInside in
                        if isInside {
                            NSCursor.operationNotAllowed.push()
                        } else {
                            NSCursor.pop()
                        }
                    }
                
                HStack(spacing: 8) {
                    Image(systemName: "lock.shield.fill")
                        .font(.body)
                        .foregroundStyle(.green)
                    Text("Authentication tokens are stored securely in macOS Keychain")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
                .background(Color.green.opacity(0.1))
                .cornerRadius(8)

                HStack(spacing: 8) {
                    Button("Save Token") {
                        saveToken()
                    }
                    .disabled(true)
                    .buttonStyle(.bordered)
                    .accessibilityLabel("Save authentication token")
                    .accessibilityIdentifier("saveWebsocketTokenButton")

                    Button("Clear Token") {
                        clearToken()
                    }
                    .disabled(true)
                    .buttonStyle(.bordered)
                    .tint(.red)
                    .accessibilityLabel("Clear authentication token")
                    .accessibilityIdentifier("clearWebsocketTokenButton")

                    if tokenSaved {
                        HStack(spacing: 4) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                            Text("Saved")
                                .font(.caption)
                                .foregroundColor(.green)
                        }
                        .padding(.leading, 8)
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel("Token saved")
                        .accessibilityIdentifier("websocketTokenSavedStatus")
                    }
                    
                    Spacer()
                }
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
