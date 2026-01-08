//
//  SettingsView.swift
//  packtrack
//
//  Created by Nathanial Henniges on 1/8/26.
//

import AppKit
import SwiftUI

/// The main settings interface for PackTrack.
///
/// This view provides controls for:
/// - Enabling/disabling music tracking
/// - Configuring WebSocket connection for remote tracking
/// - Managing authentication tokens (stored in Keychain)
/// - Resetting all settings to defaults
struct SettingsView: View {
    // MARK: - Constants

    fileprivate enum Constants {
        static let defaultAppName = "Pack Track"
        static let minWidth: CGFloat = 390
        static let minHeight: CGFloat = 420
        static let validSchemes = ["ws", "wss", "http", "https"]

        enum UserDefaultsKeys {
            static let trackingEnabled = "trackingEnabled"
            static let websocketEnabled = "websocketEnabled"
            static let websocketURI = "websocketURI"
            static let currentSongCommandEnabled = "currentSongCommandEnabled"
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

    /// Whether raw Twitch chat events should be logged for debugging
    @AppStorage("twitchDebugLogging")
    private var twitchDebugLogging = false

    /// Whether a re-authentication is needed for Twitch (set on app boot)
    @AppStorage("twitchReauthNeeded")
    private var twitchReauthNeeded = false

    // MARK: - State

    /// The authentication token (JWT) for WebSocket connections.
    /// Temporarily held in memory and saved to Keychain when user clicks "Save Token".
    @State private var authToken: String = ""

    /// Indicates whether the token has been successfully saved to Keychain
    @State private var tokenSaved = false

    /// The Twitch bot username (read-only, resolved from OAuth)
    @State private var twitchBotUsername: String = ""

    /// The Twitch OAuth token
    @State private var twitchOAuthToken: String = ""

    /// The Twitch channel to join (username)
    @State private var twitchChannelID: String = ""

    /// Indicates whether the Twitch credentials have been successfully saved to Keychain
    @State private var twitchCredentialsSaved = false

    /// Whether the bot is currently connected to a Twitch channel
    @State private var twitchChannelConnected = false

    /// The Twitch service for connecting/disconnecting from channels

    // Helper to get the shared Twitch service from AppDelegate
    private var appDelegate: AppDelegate? {
        NSApplication.shared.delegate as? AppDelegate
    }

    private var twitchService: TwitchChatService? {
        appDelegate?.twitchService
    }

    /// Connection status message
    @State private var connectionStatusMessage = ""

    /// OAuth helper and state
    @State private var oauthInProgress = false
    @State private var oauthStatusMessage = ""

    /// Device-code flow state
    @State private var deviceUserCode: String = ""
    @State private var deviceVerificationURI: String = ""
    @State private var deviceAuthInProgress = false
    @State private var devicePollingTask: Task<Void, Never>?
    @State private var twitchConnectedOnce = false

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
            VStack(alignment: .leading, spacing: 20) {

                // MARK: Header
                Text("Settings")
                    .font(.title)

                Divider()

                // MARK: Tracking
                GroupBox(
                    label: Label("Music Playback Monitor", systemImage: "music.note").font(
                        .headline)
                ) {
                    VStack(alignment: .leading, spacing: 10) {
                        Spacer(minLength: 4)

                        Text("Show what you're playing from Apple Music inside PackTrack.")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        Toggle("Show what's playing from Apple Music", isOn: $trackingEnabled)
                            .onChange(of: trackingEnabled) { _, newValue in
                                notifyTrackingSettingChanged(enabled: newValue)
                            }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Divider()

                // MARK: WebSocket
                GroupBox(
                    label: Label(
                        "Now Playing WebSocket", systemImage: "dot.radiowaves.left.and.right"
                    )
                    .font(.headline)
                ) {
                    VStack(alignment: .leading, spacing: 10) {
                        Spacer(minLength: 4)

                        Text("Send your now playing info to an overlay or server via WebSocket.")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        Toggle("Send now playing to your server", isOn: $websocketEnabled)
                            .disabled(!isWebSocketURLValid)

                        TextField(
                            "WebSocket server URL (ws:// or wss://)", text: websocketURIBinding
                        )
                        .textFieldStyle(.roundedBorder)

                        if !isWebSocketURLValid {
                            Text("Add a WebSocket URL (ws:// or wss://) to turn this on.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }

                        SecureField("Auth token (optional JWT)", text: $authToken)

                        HStack {
                            Button("Save Token", action: saveToken)
                                .disabled(authToken.isEmpty)

                            Button("Clear Token", action: clearToken)
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

                        Text(
                            "Tokens are stored securely in macOS Keychain; never written to disk or UserDefaults."
                        )
                        .font(.caption)
                        .foregroundColor(.secondary)
                    }
                    .padding(8)
                }

                Divider()

                // MARK: Twitch Bot
                GroupBox(
                    label: Label("Twitch Bot", systemImage: "bubble.left.and.bubble.right").font(
                        .headline)
                ) {
                    VStack(alignment: .leading, spacing: 10) {
                        if twitchReauthNeeded {
                            HStack(alignment: .top, spacing: 8) {
                                Image(systemName: "exclamationmark.triangle.fill").foregroundColor(
                                    .yellow)
                                Text(
                                    "Your Twitch session expired. Please sign in again to continue."
                                )
                                .font(.caption)
                                .foregroundColor(.secondary)
                            }
                        }
                        Text(
                            "Connect the bot to your Twitch channel so it can chat and share what you're playing."
                        )
                        .font(.caption)
                        .foregroundColor(.secondary)

                        HStack {
                            Text("Bot Username")
                                .foregroundColor(.secondary)
                            Spacer()
                            Text(twitchBotUsername.isEmpty ? "Not resolved yet" : twitchBotUsername)
                                .fontWeight(.semibold)
                        }

                        if !deviceUserCode.isEmpty {
                            VStack(alignment: .leading, spacing: 6) {
                                Label("Enter this code on Twitch", systemImage: "number")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                HStack {
                                    Text(deviceUserCode)
                                        .font(.title3).monospaced().bold()
                                    Spacer()
                                    Button(action: {
                                        NSPasteboard.general.clearContents()
                                        NSPasteboard.general.setString(
                                            deviceUserCode, forType: .string)
                                    }) {
                                        Label("Copy", systemImage: "doc.on.doc")
                                    }
                                    .buttonStyle(.borderless)
                                }
                                if !deviceVerificationURI.isEmpty {
                                    Button(action: {
                                        if let url = URL(string: deviceVerificationURI) {
                                            NSWorkspace.shared.open(url)
                                        }
                                    }) {
                                        Label("Open Twitch to authorize", systemImage: "link")
                                    }
                                }
                            }
                        }

                        TextField("Channel to join", text: $twitchChannelID)
                            .textFieldStyle(.roundedBorder)

                        Text("Channel to join (usually your Twitch username).").font(.caption)
                            .foregroundColor(.secondary)

                        HStack {
                            Button(action: startTwitchOAuth) {
                                Label("Sign in with Twitch", systemImage: "person.badge.key")
                            }
                            .disabled(oauthInProgress || deviceAuthInProgress)

                            Spacer()

                            Button("Save Bot Info", action: saveTwitchCredentials)
                                .disabled(twitchOAuthToken.isEmpty || twitchChannelID.isEmpty)

                            Button("Clear Bot Info", action: clearTwitchCredentials)
                                .foregroundColor(.red)
                        }

                        if oauthInProgress || deviceAuthInProgress {
                            ProgressView()
                                .progressViewStyle(.linear)
                                .frame(maxWidth: .infinity)
                                .padding(.top, 4)
                        }

                        if twitchCredentialsSaved && twitchConnectedOnce && !twitchReauthNeeded {
                            Label(
                                "Saved to Keychain: bot username, token, channel.",
                                systemImage: "checkmark.seal.fill"
                            )
                            .font(.caption)
                            .foregroundColor(.green)
                        } else if twitchReauthNeeded {
                            Text("Re-authentication required. Click 'Sign in with Twitch'.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        } else if !oauthStatusMessage.isEmpty {
                            Text(oauthStatusMessage)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }

                        Text(
                            "After sign-in, your bot username, OAuth token, and channel are stored securely in Keychain. The bot username is resolved from Twitch after authentication."
                        )
                        .font(.caption)
                        .foregroundColor(.secondary)

                        Toggle("Log raw Twitch chat events", isOn: $twitchDebugLogging)
                            .onChange(of: twitchDebugLogging) { _, newValue in
                                twitchService?.debugLoggingEnabled = newValue
                            }

                        Text("Prints raw Twitch chat events to the debug console.")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        Divider()

                        if KeychainService.loadTwitchToken() != nil && !twitchReauthNeeded {
                            HStack(spacing: 12) {
                                Button(action: twitchChannelConnected ? leaveChannel : joinChannel)
                                {
                                    Label(
                                        twitchChannelConnected ? "Leave Channel" : "Join Channel",
                                        systemImage: twitchChannelConnected
                                            ? "xmark.circle.fill" : "arrow.right.circle.fill"
                                    )
                                }
                                .foregroundColor(twitchChannelConnected ? .red : .blue)

                                Image(
                                    systemName: twitchChannelConnected
                                        ? "checkmark.circle.fill" : "xmark.circle.fill"
                                )
                                .foregroundColor(twitchChannelConnected ? .green : .red)

                                Spacer()
                            }

                            if !connectionStatusMessage.isEmpty {
                                HStack(spacing: 8) {
                                    Text(connectionStatusMessage)
                                        .font(.caption)
                                }
                            }
                        } else if twitchReauthNeeded {
                            Text("Please re-authenticate before connecting to a channel.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(8)
                }

                Divider()

                // MARK: Twitch Bot Commands
                GroupBox(label: Label("Bot Commands", systemImage: "command").font(.headline)) {
                    VStack(alignment: .leading, spacing: 10) {
                        Spacer(minLength: 4)

                        Text("Choose which chat commands the bot responds to in Twitch chat.")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        Toggle("Current Song", isOn: $currentSongCommandEnabled)

                        Text(
                            "When enabled, the bot will respond to !song, !currentsong, and !nowplaying in Twitch chat with the currently playing Apple Music track."
                        )
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
        .frame(minWidth: Constants.minWidth, minHeight: Constants.minHeight)
        .onAppear {
            if let savedToken = KeychainService.loadToken() {
                authToken = savedToken
                tokenSaved = true
            }

            if let savedTwitchUsername = KeychainService.loadTwitchUsername() {
                twitchBotUsername = savedTwitchUsername
            }

            if let savedTwitchToken = KeychainService.loadTwitchToken() {
                twitchOAuthToken = savedTwitchToken
                twitchCredentialsSaved = true
            }

            if let savedTwitchChannelID = KeychainService.loadTwitchChannelID() {
                twitchChannelID = savedTwitchChannelID
            }

            if !isWebSocketURLValid {
                websocketEnabled = false
            }

            twitchService?.debugLoggingEnabled = twitchDebugLogging

            // Set up Twitch service callbacks
            twitchService?.onConnectionStateChanged = { isConnected in
                DispatchQueue.main.async {
                    twitchChannelConnected = isConnected
                    connectionStatusMessage =
                        isConnected ? "Connected to Twitch chat" : "Disconnected from Twitch chat"
                }
            }

            // Set up callback to get current song info
            twitchService?.getCurrentSongInfo = {
                if let appDelegate = NSApplication.shared.delegate as? AppDelegate {
                    return appDelegate.getCurrentSongInfo()
                }
                return "No track currently playing"
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
        .onDisappear {
            // Clean up any ongoing OAuth tasks when the view disappears
            if let task = devicePollingTask {
                Log.debug(
                    "Settings: Cancelling OAuth polling task on view disappear",
                    category: "Settings")
                task.cancel()
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

    private func notifyTrackingSettingChanged(enabled: Bool) {
        NotificationCenter.default.post(
            name: NSNotification.Name(Constants.Notifications.trackingSettingChanged),
            object: nil,
            userInfo: ["enabled": enabled]
        )
    }

    private func startTwitchOAuth() {
        Log.info("Settings: Starting Twitch device-code flow", category: "Settings")
        oauthStatusMessage = "Requesting authorization code from Twitch..."
        deviceUserCode = ""
        deviceVerificationURI = ""
        deviceAuthInProgress = true

        // Cancel any existing polling task before starting a new one
        if let existingTask = devicePollingTask {
            Log.debug("Settings: Cancelling previous OAuth polling task", category: "Settings")
            existingTask.cancel()
            devicePollingTask = nil
        }

        guard let clientID = TwitchChatService.resolveClientID(), !clientID.isEmpty else {
            Log.error("Settings: Twitch Client ID not configured", category: "Settings")
            oauthStatusMessage = "⚠️ Missing Twitch Client ID. Set TWITCH_CLIENT_ID in the scheme."
            deviceAuthInProgress = false
            return
        }

        let helper = TwitchDeviceAuth(
            clientID: clientID,
            scopes: ["user:read:chat", "user:write:chat"]
        )

        Task {
            do {
                let response = try await helper.requestDeviceCode()
                await MainActor.run {
                    deviceUserCode = response.userCode
                    deviceVerificationURI = response.verificationURI
                    oauthStatusMessage = "✅ Code ready! Go to Twitch and enter the code above."
                }

                devicePollingTask = Task {
                    do {
                        let token = try await helper.pollForToken(
                            deviceCode: response.deviceCode,
                            interval: response.interval
                        ) { status in
                            Task { @MainActor in
                                oauthStatusMessage = status
                            }
                        }

                        await MainActor.run {
                            oauthInProgress = false
                            deviceAuthInProgress = false
                            deviceUserCode = ""
                            deviceVerificationURI = ""
                            oauthStatusMessage = "✅ Authorization successful! Saving credentials..."
                            twitchOAuthToken = token
                            do {
                                try KeychainService.saveTwitchToken(token)
                                twitchCredentialsSaved = true
                                twitchConnectedOnce = true
                                Log.info(
                                    "Settings: OAuth token saved successfully", category: "Settings"
                                )
                            } catch {
                                Log.error(
                                    "Settings: Failed to save token to Keychain - \(error.localizedDescription)",
                                    category: "Settings")
                                oauthStatusMessage =
                                    "⚠️ Keychain save failed: \(error.localizedDescription)"
                            }
                        }

                        // Resolve bot identity now that we have a valid token
                        guard let clientID = TwitchChatService.resolveClientID(),
                            !clientID.isEmpty
                        else {
                            Log.debug(
                                "Settings: Cannot resolve bot identity - missing client ID",
                                category: "Settings")
                            return
                        }

                        do {
                            // Use static method so it works even if the service instance isn't available
                            try await TwitchChatService.resolveBotIdentityStatic(
                                token: token, clientID: clientID)

                            // Load and display the resolved username
                            if let username = KeychainService.loadTwitchUsername() {
                                await MainActor.run {
                                    twitchBotUsername = username
                                    oauthStatusMessage = "✅ Bot identity resolved: \(username)"
                                    Log.info(
                                        "Settings: Bot identity resolved - \(username)",
                                        category: "Settings")
                                }
                            } else {
                                Log.error(
                                    "Settings: Failed to load resolved username from Keychain",
                                    category: "Settings")
                            }
                        } catch {
                            Log.error(
                                "Settings: Failed to resolve bot identity - \(error.localizedDescription)",
                                category: "Settings")
                            await MainActor.run {
                                oauthStatusMessage =
                                    "⚠️ Could not resolve bot identity: \(error.localizedDescription)"
                            }
                        }
                    } catch let error as TwitchDeviceAuthError {
                        await MainActor.run {
                            oauthInProgress = false
                            deviceAuthInProgress = false
                            deviceUserCode = ""
                            deviceVerificationURI = ""

                            switch error {
                            case .accessDenied:
                                oauthStatusMessage = "❌ Authorization denied by user"
                            case .expiredToken:
                                oauthStatusMessage = "❌ Authorization code expired"
                            case .authorizationPending:
                                oauthStatusMessage = "⏳ Still waiting for authorization..."
                            case .slowDown:
                                oauthStatusMessage = "⏸️ Polling too quickly, slowing down..."
                            case .invalidClient:
                                oauthStatusMessage = "❌ Invalid Twitch Client ID"
                            default:
                                oauthStatusMessage = "❌ OAuth failed: \(error.localizedDescription)"
                            }
                        }
                    } catch {
                        // Only show error if task wasn't cancelled
                        if !(error is CancellationError) {
                            await MainActor.run {
                                oauthInProgress = false
                                deviceAuthInProgress = false
                                deviceUserCode = ""
                                deviceVerificationURI = ""
                                oauthStatusMessage = "❌ OAuth failed: \(error.localizedDescription)"
                            }
                        }
                    }
                }
            } catch {
                await MainActor.run {
                    deviceAuthInProgress = false
                    oauthInProgress = false
                    deviceUserCode = ""
                    deviceVerificationURI = ""
                    oauthStatusMessage = "❌ OAuth setup failed: \(error.localizedDescription)"
                }
            }
        }
    }

    private func saveToken() {
        do {
            try KeychainService.saveToken(authToken)
            tokenSaved = true
        } catch {
            print("Failed to save token: \(error.localizedDescription)")
            tokenSaved = false
        }
    }

    private func clearToken() {
        KeychainService.deleteToken()
        authToken = ""
        tokenSaved = false
    }

    private func saveTwitchCredentials() {
        Log.info("Settings: Saving Twitch credentials to Keychain", category: "Settings")
        do {
            Log.debug("Settings: Saving OAuth token", category: "Settings")
            try KeychainService.saveTwitchToken(twitchOAuthToken)
            Log.debug("Settings: Saving channel ID", category: "Settings")
            try KeychainService.saveTwitchChannelID(twitchChannelID)
            twitchCredentialsSaved = true
            Log.info("Settings: Twitch credentials saved successfully", category: "Settings")

            // Resolve bot identity with the saved token
            guard !twitchOAuthToken.isEmpty else {
                Log.debug(
                    "Settings: Cannot resolve bot identity - token not available",
                    category: "Settings")
                return
            }

            guard let clientID = TwitchChatService.resolveClientID(), !clientID.isEmpty else {
                Log.debug(
                    "Settings: Cannot resolve bot identity - missing client ID",
                    category: "Settings")
                return
            }

            Task {
                do {
                    // Use static method so it works even if the service instance isn't available
                    try await TwitchChatService.resolveBotIdentityStatic(
                        token: twitchOAuthToken, clientID: clientID)

                    if let username = KeychainService.loadTwitchUsername() {
                        await MainActor.run {
                            twitchBotUsername = username
                            Log.info(
                                "Settings: Bot identity resolved - \(username)",
                                category: "Settings")
                        }
                    } else {
                        Log.error(
                            "Settings: Failed to load resolved username from Keychain",
                            category: "Settings")
                    }
                } catch {
                    Log.error(
                        "Settings: Failed to resolve bot identity - \(error.localizedDescription)",
                        category: "Settings")
                }
            }
        } catch {
            Log.error(
                "Settings: Failed to save Twitch credentials - \(error.localizedDescription)",
                category: "Settings")
            twitchCredentialsSaved = false
        }
    }

    private func clearTwitchCredentials() {
        Log.info("Settings: Clearing Twitch credentials from Keychain", category: "Settings")
        Log.debug("Settings: Deleting bot username", category: "Settings")
        KeychainService.deleteTwitchUsername()
        Log.debug("Settings: Deleting bot user ID", category: "Settings")
        KeychainService.deleteTwitchBotUserID()
        Log.debug("Settings: Deleting OAuth token", category: "Settings")
        KeychainService.deleteTwitchToken()
        Log.debug("Settings: Deleting channel ID", category: "Settings")
        KeychainService.deleteTwitchChannelID()
        twitchBotUsername = ""
        twitchOAuthToken = ""
        twitchChannelID = ""
        twitchCredentialsSaved = false
        twitchConnectedOnce = false
        Log.info("Settings: Twitch credentials cleared", category: "Settings")
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

        // Clear tokens
        clearToken()
        clearTwitchCredentials()

        // Disconnect from Twitch
        twitchService?.leaveChannel()
        twitchChannelConnected = false
        connectionStatusMessage = ""

        // Notify tracking re-enabled
        notifyTrackingSettingChanged(enabled: true)
    }

    /// Join the Twitch channel
    private func joinChannel() {
        guard let token = KeychainService.loadTwitchToken(),
            let channelID = KeychainService.loadTwitchChannelID(),
            !channelID.isEmpty
        else {
            connectionStatusMessage = "Missing channel ID or credentials"
            return
        }

        guard let clientID = TwitchChatService.resolveClientID(), !clientID.isEmpty else {
            connectionStatusMessage =
                "Missing Twitch Client ID. Set TWITCH_CLIENT_ID in the scheme."
            return
        }

        connectionStatusMessage = "Connecting to Twitch..."

        Task {
            do {
                try await twitchService?.connectToChannel(
                    channelName: channelID,
                    token: token,
                    clientID: clientID
                )

                await MainActor.run {
                    connectionStatusMessage = "Connected to Twitch"
                    twitchChannelConnected = true
                    Log.debug("Settings: Connected to Twitch channel", category: "Settings")
                }
            } catch {
                await MainActor.run {
                    connectionStatusMessage = "Failed to join: \(error.localizedDescription)"
                }
                Log.error(
                    "Twitch: Failed to join channel - \(error.localizedDescription)",
                    category: "Settings")
            }
        }
    }

    /// Leave the Twitch channel
    private func leaveChannel() {
        Log.info("Settings: Leaving Twitch channel", category: "Settings")
        twitchService?.leaveChannel()
        twitchChannelConnected = false
        Log.info("Settings: Disconnected from Twitch channel", category: "Settings")
    }
}

// MARK: - Constants Extension

extension SettingsView.Constants.UserDefaultsKeys {
    static var allKeys: [String] {
        [trackingEnabled, websocketEnabled, websocketURI, currentSongCommandEnabled]
    }
}
