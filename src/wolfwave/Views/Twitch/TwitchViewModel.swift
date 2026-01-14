//
//  TwitchViewModel.swift
//  wolfwave
//
//  Created by MrDemonWolf, Inc. on 1/13/26.
//
//  Manages all Twitch bot state and operations for Settings

import Combine
import Foundation
import SwiftUI

// MARK: - Twitch View Model

/// View model managing Twitch bot authentication, connection state, and operations.
///
/// This view model handles:
/// - OAuth Device Code flow coordination
/// - Bot identity resolution and caching
/// - Channel connection lifecycle
/// - Credential management (save/load/clear)
/// - Re-authentication state tracking
/// - Connection status updates
///
/// All operations are marked `@MainActor` for UI thread safety.
@MainActor
final class TwitchViewModel: ObservableObject {
    
    // MARK: - Published State
    
    /// The bot's Twitch display username
    @Published var botUsername = ""
    
    /// OAuth access token (not persisted in view model, loaded from Keychain)
    @Published var oauthToken = ""
    
    /// The channel name/ID to join
    @Published var channelID = ""
    
    /// Whether credentials have been saved to Keychain
    @Published var credentialsSaved = false
    
    /// Whether the bot is currently connected to the channel
    @Published var channelConnected = false
    
    /// Whether re-authentication is required
    @Published var reauthNeeded = false
    
    /// Whether the bot has connected at least once this session
    @Published var connectedOnce = false

    /// Status message displayed to the user
    @Published var statusMessage = ""

    // MARK: - Auth State

    /// Represents the current state of OAuth authentication flow.
    enum AuthState {
        case idle
        case requestingCode
        case waitingForAuth(userCode: String, verificationURI: String)
        case inProgress
        case error(String)

        var isInProgress: Bool {
            switch self {
            case .inProgress, .requestingCode, .waitingForAuth:
                return true
            default:
                return false
            }
        }

        var userCode: String {
            switch self {
            case .waitingForAuth(let code, _):
                return code
            default:
                return ""
            }
        }

        var verificationURI: String {
            switch self {
            case .waitingForAuth(_, let uri):
                return uri
            default:
                return ""
            }
        }
    }

    /// Current OAuth authentication state
    @Published var authState = AuthState.idle
    
    /// Reference to the Twitch chat service
    var twitchService: TwitchChatService? {
        get {
            _twitchService ?? getTwitchServiceFromAppDelegate()
        }
        set {
            _twitchService = newValue
        }
    }
    
    private var _twitchService: TwitchChatService?
    
    /// Background task for polling token during OAuth flow
    var devicePollingTask: Task<Void, Never>?

    // MARK: - Computed Properties

    /// Status chip text based on current state
    var statusChipText: String {
        if reauthNeeded { return "Reauth needed" }
        if channelConnected { return "Connected" }
        if credentialsSaved { return "Ready to join" }
        return "Not signed in"
    }

    /// Status chip color based on current state
    var statusChipColor: Color {
        if reauthNeeded { return .yellow }
        if channelConnected { return .green }
        if credentialsSaved { return .blue }
        return .secondary
    }

    // MARK: - Public Methods

    /// Loads saved credentials from macOS Keychain.
    ///
    /// Also loads the reauth needed flag and sets up notification observers for auth state changes.
    func loadSavedCredentials() {
        if let username = KeychainService.loadTwitchUsername() {
            botUsername = username
        }
        if let token = KeychainService.loadTwitchToken() {
            oauthToken = token
            credentialsSaved = true
        }
        if let channel = KeychainService.loadTwitchChannelID() {
            channelID = channel
        }
        
        // Load reauth needed flag from UserDefaults
        reauthNeeded = UserDefaults.standard.bool(forKey: "twitchReauthNeeded")
        
        // Listen for reauth status changes
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(reAuthStatusChanged),
            name: NSNotification.Name("TwitchReauthNeededChanged"),
            object: nil
        )
    }

    /// Called when the reauth needed status changes.
    @objc private func reAuthStatusChanged() {
        reauthNeeded = UserDefaults.standard.bool(forKey: "twitchReauthNeeded")
    }

    /// Initiates the OAuth Device Code flow.
    ///
    /// - Requests a device code from Twitch
    /// - Displays the code to the user for manual entry on twitch.tv/activate
    /// - Polls for token approval
    /// - On success, saves credentials and resolves bot identity
    /// - On failure, displays error message to user
    func startOAuth() {
        Log.info("TwitchViewModel: Starting OAuth flow", category: "Twitch")
        authState = .requestingCode
        statusMessage = "Requesting authorization code from Twitch..."

        // Cancel any existing polling task
        if let existingTask = devicePollingTask {
            Log.debug("TwitchViewModel: Cancelling previous OAuth polling task", category: "Twitch")
            existingTask.cancel()
            devicePollingTask = nil
        }

        guard let clientID = TwitchChatService.resolveClientID(), !clientID.isEmpty else {
            Log.error("TwitchViewModel: Twitch Client ID not configured", category: "Twitch")
            statusMessage = "⚠️ Missing Twitch Client ID. Set TWITCH_CLIENT_ID in the scheme."
            authState = .error("Missing Client ID")
            return
        }

        let helper = TwitchDeviceAuth(
            clientID: clientID,
            scopes: ["user:read:chat", "user:write:chat"]
        )

        Task {
            do {
                let response = try await helper.requestDeviceCode()
                await self.updateAuthState(
                    .waitingForAuth(
                        userCode: response.userCode, verificationURI: response.verificationURI)
                )
                statusMessage = "✅ Code ready! Go to Twitch and enter the code above."

                devicePollingTask = Task {
                    do {
                        let token = try await helper.pollForToken(
                            deviceCode: response.deviceCode,
                            interval: response.interval
                        ) { status in
                            Task { @MainActor in
                                self.statusMessage = status
                            }
                        }

                        await self.handleOAuthSuccess(token: token, clientID: clientID)
                    } catch let error as TwitchDeviceAuthError {
                        await self.handleOAuthError(error)
                    } catch {
                        if !(error is CancellationError) {
                            await self.handleOAuthError(.unknown(error.localizedDescription))
                        }
                    }
                }
            } catch {
                self.updateAuthState(.error(error.localizedDescription))
                statusMessage = "❌ OAuth setup failed: \(error.localizedDescription)"
            }
        }
    }

    /// Saves credentials to macOS Keychain and resolves bot identity.
    func saveCredentials() {
        Log.info("TwitchViewModel: Saving Twitch credentials", category: "Twitch")
        do {
            try KeychainService.saveTwitchToken(oauthToken)
            try KeychainService.saveTwitchChannelID(channelID)
            credentialsSaved = true
            reauthNeeded = false
            UserDefaults.standard.set(false, forKey: "twitchReauthNeeded")
            NotificationCenter.default.post(
                name: NSNotification.Name("TwitchReauthNeededChanged"),
                object: nil
            )
            Log.info("TwitchViewModel: Credentials saved", category: "Twitch")

            resolveBotIdentity()
        } catch {
            Log.error(
                "TwitchViewModel: Failed to save credentials - \(error.localizedDescription)",
                category: "Twitch"
            )
        }
    }

    /// Saves just the channel ID to Keychain (auto-save on input).
    func saveChannelID() {
        do {
            try KeychainService.saveTwitchChannelID(channelID)
            Log.debug("TwitchViewModel: Channel ID saved", category: "Twitch")
        } catch {
            Log.error(
                "TwitchViewModel: Failed to save channel ID - \(error.localizedDescription)",
                category: "Twitch"
            )
        }
    }

    /// Clears all stored Twitch credentials and resets state.
    func clearCredentials() {
        Log.info("TwitchViewModel: Clearing Twitch credentials", category: "Twitch")
        
        // Disconnect from channel first if connected
        if channelConnected {
            leaveChannel()
        }
        
        // Clear all keychain data
        KeychainService.deleteTwitchUsername()
        KeychainService.deleteTwitchBotUserID()
        KeychainService.deleteTwitchToken()
        KeychainService.deleteTwitchChannelID()

        // Clear all state
        botUsername = ""
        oauthToken = ""
        channelID = ""
        credentialsSaved = false
        connectedOnce = false
        reauthNeeded = false
        UserDefaults.standard.set(false, forKey: "twitchReauthNeeded")
        statusMessage = ""
        authState = .idle

        NotificationCenter.default.post(
            name: NSNotification.Name("TwitchReauthNeededChanged"),
            object: nil
        )
        Log.info("TwitchViewModel: Credentials cleared", category: "Twitch")
    }

    /// Joins the configured Twitch channel with the saved bot credentials.
    ///
    /// - Validates credentials and channel name
    /// - Connects to Twitch EventSub WebSocket
    /// - Updates connection state on success/failure
    /// - Provides user-facing status messages
    func joinChannel() {
        guard let token = KeychainService.loadTwitchToken() else {
            statusMessage = "Missing credentials"
            return
        }

        let channel = channelID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !channel.isEmpty else {
            statusMessage = "Enter a channel first"
            return
        }

        guard let clientID = TwitchChatService.resolveClientID(), !clientID.isEmpty else {
            statusMessage = "Missing Twitch Client ID. Set TWITCH_CLIENT_ID in the scheme."
            return
        }

        Task {
            do {
                try await twitchService?.connectToChannel(
                    channelName: channel,
                    token: token,
                    clientID: clientID
                )

                channelConnected = true
                statusMessage = "Connected to \(channel)"
                Log.info(
                    "TwitchViewModel: Connected to Twitch channel \(channel)", category: "Twitch")
            } catch {
                statusMessage = "Failed to join: \(error.localizedDescription)"
                Log.error(
                    "TwitchViewModel: Failed to join channel - \(error.localizedDescription)",
                    category: "Twitch"
                )
            }
        }
    }

    /// Leaves the connected Twitch channel and closes EventSub connection.
    func leaveChannel() {
        Log.info("TwitchViewModel: Leaving Twitch channel", category: "Twitch")
        twitchService?.leaveChannel()
        channelConnected = false
        Log.info("TwitchViewModel: Disconnected from Twitch channel", category: "Twitch")
    }

    // MARK: - Private Methods

    private func updateAuthState(_ state: AuthState) {
        authState = state
    }

    /// Retrieves the TwitchChatService from AppDelegate if twitchService is not yet set.
    ///
    /// This ensures the view model can always access the service, even if it was created
    /// before SettingsView.onAppear() had a chance to assign it explicitly.
    private func getTwitchServiceFromAppDelegate() -> TwitchChatService? {
        if let appDelegate = NSApplication.shared.delegate as? AppDelegate {
            return appDelegate.twitchService
        }
        return nil
    }

    private func handleOAuthSuccess(token: String, clientID: String) async {
        authState = .inProgress
        statusMessage = "✅ Authorization successful! Saving credentials..."
        oauthToken = token

        do {
            try KeychainService.saveTwitchToken(token)
            reauthNeeded = false
            UserDefaults.standard.set(false, forKey: "twitchReauthNeeded")
            NotificationCenter.default.post(
                name: NSNotification.Name("TwitchReauthNeededChanged"),
                object: nil
            )
            credentialsSaved = true
            connectedOnce = true
            Log.info("TwitchViewModel: OAuth token saved", category: "Twitch")
        } catch {
            Log.error(
                "TwitchViewModel: Failed to save token - \(error.localizedDescription)",
                category: "Twitch"
            )
            statusMessage = "⚠️ Keychain save failed: \(error.localizedDescription)"
            authState = .error(error.localizedDescription)
            return
        }

        // Resolve bot identity
        do {
            try await TwitchChatService.resolveBotIdentityStatic(token: token, clientID: clientID)
            if let username = KeychainService.loadTwitchUsername() {
                botUsername = username
                statusMessage = "✅ Bot identity resolved: \(username)"
                authState = .idle
                Log.info("TwitchViewModel: Bot identity resolved - \(username)", category: "Twitch")
            }
        } catch {
            Log.error(
                "TwitchViewModel: Failed to resolve bot identity - \(error.localizedDescription)",
                category: "Twitch"
            )
            statusMessage = "⚠️ Could not resolve bot identity: \(error.localizedDescription)"
            authState = .error(error.localizedDescription)
        }
    }

    private func handleOAuthError(_ error: TwitchDeviceAuthError) async {
        let message: String
        switch error {
        case .accessDenied:
            message = "❌ Authorization denied by user"
        case .expiredToken:
            message = "❌ Authorization code expired"
        case .authorizationPending:
            message = "⏳ Still waiting for authorization..."
        case .slowDown:
            message = "⏸️ Polling too quickly, slowing down..."
        case .invalidClient:
            message = "❌ Invalid Twitch Client ID"
        default:
            message = "❌ OAuth failed: \(error.localizedDescription)"
        }
        statusMessage = message
        authState = .error(message)
    }

    private func resolveBotIdentity() {
        guard !oauthToken.isEmpty else {
            Log.debug("TwitchViewModel: Cannot resolve - token not available", category: "Twitch")
            return
        }

        guard let clientID = TwitchChatService.resolveClientID(), !clientID.isEmpty else {
            Log.debug("TwitchViewModel: Cannot resolve - missing client ID", category: "Twitch")
            return
        }

        Task {
            do {
                try await TwitchChatService.resolveBotIdentityStatic(
                    token: oauthToken, clientID: clientID
                )

                if let username = KeychainService.loadTwitchUsername() {
                    botUsername = username
                    Log.info(
                        "TwitchViewModel: Bot identity resolved - \(username)", category: "Twitch")
                }
            } catch {
                Log.error(
                    "TwitchViewModel: Failed to resolve bot identity - \(error.localizedDescription)",
                    category: "Twitch"
                )
            }
        }
    }
}
