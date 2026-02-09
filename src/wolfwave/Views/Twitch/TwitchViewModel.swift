//
//  TwitchViewModel.swift
//  wolfwave
//
//  Created by MrDemonWolf, Inc. on 1/17/26.
//

import Combine
import Foundation
import SwiftUI

/// View model managing Twitch bot authentication, connection state, and operations.
///
/// Handles:
/// - OAuth Device Code flow
/// - Bot identity resolution
/// - Channel connection lifecycle
/// - Secure credential management via Keychain
/// - Re-authentication state tracking
///
/// All operations are @MainActor marked for UI thread safety.
@MainActor
final class TwitchViewModel: ObservableObject {

    // MARK: - Channel Validation State

    /// State of the channel name validation check.
    enum ChannelValidationState: Equatable {
        case idle
        case validating
        case valid
        case invalid
        case error(String)
    }

    // MARK: - Published State

    @Published var botUsername = ""
    @Published var oauthToken = ""
    @Published var channelID = ""
    @Published var credentialsSaved = false
    @Published var channelConnected = false
    @Published var isConnecting = false
    @Published var reauthNeeded = false
    @Published var statusMessage = ""
    @Published var channelValidationState: ChannelValidationState = .idle

    // MARK: - Auth State

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

    /// High level integration states consumed by the UI to simplify view logic
    enum IntegrationState {
        case notConnected
        case authorizing
        case connected
        case error(String)
    }

    /// Friendly, UI-focused mapping of lower-level auth state + connection flags
    var integrationState: IntegrationState {
        if case .error(let msg) = authState {
            return .error(msg)
        }

        // Consider the view "connected" when we either have an active channel
        // connection or saved credentials. This ensures leaving the channel (but
        // still signed-in) doesn't force the UI back to the sign-in state.
        if channelConnected || credentialsSaved {
            return .connected
        }

        switch authState {
        case .requestingCode, .waitingForAuth, .inProgress:
            return .authorizing
        default:
            return .notConnected
        }
    }

    /// Color appropriate for the integration state (UI should respect system semantic colors)
    var integrationColor: Color {
        switch integrationState {
        case .connected: return .green
        case .authorizing: return .orange
        case .error: return .red
        case .notConnected: return .secondary
        }
    }

    /// Current OAuth authentication state
    @Published var authState = AuthState.idle

    /// Cached reference to the Twitch chat service
    private var cachedTwitchService: TwitchChatService?

    /// Reference to the Twitch chat service with fallback to AppDelegate
    var twitchService: TwitchChatService? {
        get {
            // If we have a cached service, return it
            if let cached = cachedTwitchService {
                return cached
            }

            // Otherwise, try to fetch from AppDelegate and cache it
            if let appDelegate = AppDelegate.shared,
                let service = appDelegate.twitchService
            {
                cachedTwitchService = service
                // Set up the connection state callback
                service.onConnectionStateChanged = { [weak self] isConnected in
                    Task { @MainActor [weak self] in
                        self?.channelConnected = isConnected
                    }
                }
                self.channelConnected = service.isConnected
                return service
            }

            Log.error(
                "TwitchViewModel: AppDelegate.shared is nil or service not available",
                category: "Twitch")
            return nil
        }
        set {
            cachedTwitchService = newValue
            if let svc = newValue {
                svc.onConnectionStateChanged = { [weak self] isConnected in
                    Task { @MainActor [weak self] in
                        self?.channelConnected = isConnected
                    }
                }
                self.channelConnected = svc.isConnected
            }
        }
    }

    /// Background task for polling token during OAuth flow
    var devicePollingTask: Task<Void, Never>?
    /// Outer task that drives the overall OAuth flow (request + polling)
    var oAuthTask: Task<Void, Never>?
    /// Debounce task for saving channel ID to avoid excessive Keychain writes
    private var channelIDSaveTask: Task<Void, Never>?
    /// Task for validating channel name existence after save
    private var channelValidationTask: Task<Void, Never>?

    // MARK: - Initialization

    init() {
        // Immediately try to get the service reference on initialization
        if let appDelegate = AppDelegate.shared {
            self.cachedTwitchService = appDelegate.twitchService
            if let svc = appDelegate.twitchService {
                svc.onConnectionStateChanged = { [weak self] isConnected in
                    Task { @MainActor [weak self] in
                        self?.channelConnected = isConnected
                    }
                }
                self.channelConnected = svc.isConnected
            }
        }
    }

    /// Cancel any in-progress OAuth/device-code flow and reset related state.
    func cancelOAuth() {
        if let poll = devicePollingTask {
            poll.cancel()
            devicePollingTask = nil
        }
        if let outer = oAuthTask {
            outer.cancel()
            oAuthTask = nil
        }

        authState = .idle
        statusMessage = ""
    }

    // MARK: - Computed Properties

    /// Status chip text based on current state
    var statusChipText: String {
        if reauthNeeded { return "Reauth needed" }
        if channelConnected { return "Connected" }
        if credentialsSaved { return "Signed in" }
        return "Not signed in"
    }

    /// Status chip color based on current state
    var statusChipColor: Color {
        if reauthNeeded { return .yellow }
        if channelConnected { return .green }
        // Use a blue tint when the app is signed in but not actively joined.
        if credentialsSaved { return .blue }
        // Not signed in: use a distinct, muted gray tint so it's visually different
        return Color.gray.opacity(0.55)
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
        reauthNeeded = UserDefaults.standard.bool(
            forKey: AppConstants.UserDefaults.twitchReauthNeeded)

        // Remove any existing observers before registering to prevent duplicates
        NotificationCenter.default.removeObserver(
            self,
            name: NSNotification.Name(AppConstants.Notifications.twitchReauthNeededChanged),
            object: nil
        )
        NotificationCenter.default.removeObserver(
            self,
            name: TwitchChatService.connectionStateChanged,
            object: nil
        )

        // Listen for reauth status changes
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(reAuthStatusChanged),
            name: NSNotification.Name(AppConstants.Notifications.twitchReauthNeededChanged),
            object: nil
        )
        // Also listen for Twitch chat connection state changes posted by the service.
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(twitchConnectionStateChanged(_:)),
            name: TwitchChatService.connectionStateChanged,
            object: nil
        )
    }

    @objc private func twitchConnectionStateChanged(_ note: Notification) {
        if let info = note.userInfo, let isConnected = info["isConnected"] as? Bool {
            // Check if there's an error in the notification
            let errorMessage = info["error"] as? String

            Task { @MainActor in
                self.channelConnected = isConnected
                self.isConnecting = false
                if isConnected {
                    // Connection succeeded
                    if !self.channelID.isEmpty {
                        self.statusMessage = "✅ Connected to #\(self.channelID)"
                    } else {
                        self.statusMessage = "✅ Connected"
                    }
                } else {
                    // Connection failed or disconnected
                    if let error = errorMessage {
                        // Check if it's a timeout error
                        if error.contains("timed out") || error.contains("timeout") {
                            self.statusMessage =
                                "❌ Connection timed out. Check your network connection or firewall settings."
                        } else {
                            self.statusMessage = "❌ Connection failed: \(error)"
                        }
                        Log.error(
                            "TwitchViewModel: Connection error - \(error)", category: "Twitch")
                    } else if self.reauthNeeded {
                        // Disconnected due to reauth needed
                        self.statusMessage = "⚠️ Reauth needed"
                        Log.warn("TwitchViewModel: UI updated - Reauth needed", category: "Twitch")
                    } else if !self.statusMessage.contains("❌") && !self.statusMessage.isEmpty {
                        // Only update if there's no error message already shown
                        self.statusMessage = "Disconnected"
                    }
                }
            }
        } else {
            Log.error(
                "TwitchViewModel: Notification userInfo missing or invalid", category: "Twitch")
        }
    }

    deinit {
        devicePollingTask?.cancel()
        oAuthTask?.cancel()
        channelIDSaveTask?.cancel()
        channelValidationTask?.cancel()
        NotificationCenter.default.removeObserver(self)
    }

    /// Called when the reauth needed status changes.
    @objc private func reAuthStatusChanged() {
        reauthNeeded = UserDefaults.standard.bool(
            forKey: AppConstants.UserDefaults.twitchReauthNeeded)
    }

    /// Initiates the OAuth Device Code flow.
    ///
    /// - Requests a device code from Twitch
    /// - Shows the code to user for authorization
    /// - Polls for token approval
    /// - On success, saves credentials and resolves bot identity
    /// - On failure, displays error message to user
    ///
    /// Flow Overview:
    /// 1. Requests device code from Twitch (requires TWITCH_CLIENT_ID)
    /// 2. Displays user code for authorization
    /// 3. Polls Twitch for token while user authorizes
    /// 4. Updates UI with progress messages
    /// 5. On success, saves token to Keychain and calls handleOAuthSuccess
    ///
    /// Cancellation:
    /// - Cancels any previous OAuth flow before starting new one
    /// - Device polling can be cancelled independently
    /// - Cancellation errors are ignored; UI shows "cancelled" status
    ///
    /// UI State Updates:
    /// - authState cycles: idle -> requestingCode -> waitingForAuth -> authenticating -> success/error
    /// - statusMessage updated at each step with user-facing text
    /// - All UI updates dispatched to @MainActor
    ///
    /// Error Handling:
    /// - Missing Client ID: Shows warning and sets error state
    /// - Network/parsing errors: Handled by handleOAuthError
    /// - User denial: Caught during polling and shown as error
    /// - Timeout: Device code expires after ~10 minutes; polling stops
    ///
    /// Dependencies:
    /// - Requires TWITCH_CLIENT_ID environment variable in Xcode scheme
    /// - Requires internet connectivity
    ///
    func startOAuth() {
        authState = .requestingCode
        statusMessage = "Requesting authorization code from Twitch..."

        // Cancel any existing polling task
        if let existingTask = devicePollingTask {
            existingTask.cancel()
            devicePollingTask = nil
        }

        guard let clientID = TwitchChatService.resolveClientID(), !clientID.isEmpty else {
            statusMessage = "⚠️ Missing Twitch Client ID. Set TWITCH_CLIENT_ID in Config.xcconfig."
            authState = .error("Missing Client ID")
            return
        }

        let helper = TwitchDeviceAuth(
            clientID: clientID,
            scopes: ["user:read:chat", "user:write:chat"]
        )

        // Track the overall OAuth flow so it can be cancelled cleanly
        oAuthTask = Task { @MainActor in
            do {
                let response = try await helper.requestDeviceCode()
                updateAuthState(
                    .waitingForAuth(
                        userCode: response.userCode, verificationURI: response.verificationURI)
                )
                statusMessage = "✅ Code ready! Go to Twitch and enter the code above."

                // Start polling in a child task so it can be cancelled independently
                devicePollingTask = Task {
                    defer {
                        Task { @MainActor in
                            self.devicePollingTask = nil
                            self.oAuthTask = nil
                        }
                    }

                    do {
                        let token = try await helper.pollForToken(
                            deviceCode: response.deviceCode,
                            interval: response.interval,
                            expiresIn: response.expiresIn
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
                updateAuthState(.error(error.localizedDescription))
                statusMessage = "❌ OAuth setup failed: \(error.localizedDescription)"
                await MainActor.run {
                    self.oAuthTask = nil
                }
            }
        }
    }

    /// Saves credentials to macOS Keychain and resolves bot identity.
    func saveCredentials() {
        // Validate before saving
        guard !oauthToken.isEmpty else {
            statusMessage = "❌ No OAuth token to save"
            return
        }

        guard !channelID.isEmpty else {
            statusMessage = "❌ Please enter a channel name"
            return
        }

        do {
            try KeychainService.saveTwitchToken(oauthToken)
            try KeychainService.saveTwitchChannelID(channelID.lowercased())
            credentialsSaved = true
            reauthNeeded = false
            UserDefaults.standard.set(false, forKey: AppConstants.UserDefaults.twitchReauthNeeded)
            NotificationCenter.default.post(
                name: NSNotification.Name(AppConstants.Notifications.twitchReauthNeededChanged),
                object: nil
            )
            statusMessage = "✅ Credentials saved successfully"
        } catch {
            statusMessage = "❌ Failed to save: \(error.localizedDescription)"
            Log.error(
                "TwitchViewModel: Failed to save credentials - \(error.localizedDescription)",
                category: "Twitch"
            )
        }
    }

    /// Saves just the channel ID to Keychain (auto-save on input).
    /// Debounced to avoid excessive writes - waits 1 second after last keystroke.
    /// After saving, triggers channel name validation against the Twitch API.
    func saveChannelID() {
        // Cancel any pending save task and validation task
        channelIDSaveTask?.cancel()
        channelValidationTask?.cancel()
        channelValidationState = .idle

        // Create a new task that waits 1 second before saving
        channelIDSaveTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_000_000_000)  // 1 second

            // Check if task was cancelled
            guard !Task.isCancelled else { return }

            let channel = self.channelID.trimmingCharacters(in: .whitespacesAndNewlines)

            do {
                try KeychainService.saveTwitchChannelID(channel)
            } catch {
                Log.error(
                    "Failed to save channel ID: \(error.localizedDescription)",
                    category: "Keychain"
                )
                return
            }

            // Trigger validation if channel name is non-empty
            if !channel.isEmpty {
                self.validateChannelName(channel)
            }
        }
    }

    /// Clears all stored Twitch credentials and resets state.
    func clearCredentials() {

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
        reauthNeeded = false
        UserDefaults.standard.set(false, forKey: AppConstants.UserDefaults.twitchReauthNeeded)
        statusMessage = ""
        authState = .idle
        channelValidationTask?.cancel()
        channelValidationTask = nil
        channelValidationState = .idle

        NotificationCenter.default.post(
            name: NSNotification.Name(AppConstants.Notifications.twitchReauthNeededChanged),
            object: nil
        )
    }

    /// Joins the configured Twitch channel with the saved bot credentials.
    ///
    /// Prerequisites:
    /// - OAuth token must be saved in Keychain (from completed OAuth flow)
    /// - Channel name must be set and valid (alphanumeric, ≤25 chars, lowercase)
    /// - TWITCH_CLIENT_ID must be available
    ///
    /// Validation:
    /// - Checks token presence in Keychain
    /// - Normalizes channel name (trimmed, lowercased)
    /// - Validates length (max 25 chars per Twitch limits)
    /// - Verifies Client ID is configured
    ///
    /// Connection Process:
    /// 1. Shows "Connecting to Twitch..." status
    /// 2. Calls TwitchChatService.connectToChannel() (async, off-thread)
    /// 3. TwitchChatService validates and resolves user IDs
    /// 4. Establishes EventSub WebSocket connection
    /// 5. Updates UI state on success/failure
    ///
    /// UI Updates:
    /// - Success: Shows "✅ Connected to #channel", sets channelConnected=true
    /// - Failure: Shows error message with reason, keeps channelConnected=false
    /// - All updates dispatched to @MainActor
    ///
    /// Error Handling:
    /// - ConnectionError subclasses for specific failures (auth, network, config)
    /// - Generic errors from system are caught and displayed
    /// - Errors are logged; UI shows user-friendly messages
    ///
    /// Note: Does not validate that channel name exists on Twitch.
    /// Validation happens during EventSub subscription in TwitchChatService.
    ///
    func joinChannel() {
        isConnecting = true

        guard let token = KeychainService.loadTwitchToken(), !token.isEmpty else {
            statusMessage = "❌ No OAuth token found. Please sign in first."
            Log.error("TwitchViewModel: No OAuth token found", category: "Twitch")
            isConnecting = false
            return
        }

        let channel = channelID.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !channel.isEmpty else {
            statusMessage = "❌ Please enter a channel name"
            isConnecting = false
            return
        }

        guard channel.count <= 25 else {
            statusMessage = "❌ Channel name too long"
            isConnecting = false
            return
        }

        guard let clientID = TwitchChatService.resolveClientID(), !clientID.isEmpty else {
            statusMessage = "❌ Client ID not configured"
            isConnecting = false
            return
        }

        Task {
            do {
                // Access the service property which will fetch from AppDelegate if needed
                guard let service = self.twitchService else {
                    await MainActor.run {
                        self.statusMessage =
                            "❌ Twitch service not initialized. Try restarting the app."
                        self.isConnecting = false
                    }
                    Log.error(
                        "TwitchViewModel: twitchService property returned nil", category: "Twitch")
                    return
                }

                Log.info(
                    "TwitchViewModel: Twitch service found, starting connection to channel: \(channel)",
                    category: "Twitch")

                await MainActor.run {
                    self.statusMessage = "Connecting to Twitch..."
                }

                service.shouldSendConnectionMessageOnSubscribe = true

                try await service.connectToChannel(
                    channelName: channel,
                    token: token,
                    clientID: clientID
                )

                // Don't set channelConnected here - it will be set by the notification
                // from the service when the EventSub session is actually established
                await MainActor.run {
                    self.statusMessage = "Waiting for connection..."
                }
            } catch let error as TwitchChatService.ConnectionError {
                await MainActor.run {
                    self.statusMessage = "❌ Connection failed: \(error)"
                    self.channelConnected = false
                    self.isConnecting = false
                }
            } catch {
                await MainActor.run {
                    self.statusMessage = "❌ Error: \(error.localizedDescription)"
                    self.channelConnected = false
                    self.isConnecting = false
                }
            }
        }
    }

    /// Leaves the connected Twitch channel and closes EventSub connection.
    ///
    /// Cleanup:
    /// - Calls TwitchChatService.leaveChannel() for clean disconnection
    /// - Closes EventSub WebSocket with .goingAway code
    /// - Sets channelConnected = false
    ///
    /// Thread Safety: Safe to call from any thread; dispatches to service on proper queue.
    ///
    /// Side Effects:
    /// - onMessageReceived callbacks will stop being called
    /// - Pending sends are discarded
    /// - Connection state notifications are posted
    ///
    func leaveChannel() {
        if let service = twitchService {
            service.leaveChannel()
        }
        channelConnected = false
    }

    // MARK: - Private Methods

    /// Validates whether a channel name exists on Twitch.
    ///
    /// Loads token and client ID from Keychain/config, calls the service's
    /// `validateChannelExists()`, and updates published validation state.
    /// Shows an alert if the channel is not found.
    private func validateChannelName(_ channelName: String) {
        channelValidationTask?.cancel()

        channelValidationState = .validating

        channelValidationTask = Task { @MainActor in
            guard !Task.isCancelled else { return }

            guard let token = KeychainService.loadTwitchToken(), !token.isEmpty else {
                self.channelValidationState = .idle
                return
            }

            guard let clientID = TwitchChatService.resolveClientID(), !clientID.isEmpty else {
                self.channelValidationState = .idle
                return
            }

            guard let service = self.twitchService else {
                self.channelValidationState = .idle
                return
            }

            let result = await service.validateChannelExists(channelName, token: token, clientID: clientID)

            guard !Task.isCancelled else { return }

            switch result {
            case .exists:
                self.channelValidationState = .valid
            case .notFound:
                self.channelValidationState = .invalid
            case .authenticationFailed:
                self.channelValidationState = .error("Authentication failed")
            case .error(let message):
                self.channelValidationState = .error(message)
            }
        }
    }

    private func updateAuthState(_ state: AuthState) {
        authState = state
    }

    /// Retrieves the TwitchChatService from AppDelegate if twitchService is not yet set.
    private func getTwitchServiceFromAppDelegate() -> TwitchChatService? {
        return AppDelegate.shared?.twitchService
    }

    private func handleOAuthSuccess(token: String, clientID: String) async {
        authState = .inProgress
        statusMessage = "✅ Authorization successful! Saving credentials..."
        oauthToken = token

        do {
            try KeychainService.saveTwitchToken(token)
            reauthNeeded = false
            UserDefaults.standard.set(false, forKey: AppConstants.UserDefaults.twitchReauthNeeded)
            NotificationCenter.default.post(
                name: NSNotification.Name(AppConstants.Notifications.twitchReauthNeededChanged),
                object: nil
            )
            credentialsSaved = true
        } catch {
            Log.error(
                "Failed to save OAuth token: \(error.localizedDescription)",
                category: "Keychain"
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
            }
        } catch {
            Log.error(
                "Failed to resolve bot identity: \(error.localizedDescription)",
                category: "Twitch"
            )
            statusMessage = "⚠️ Could not resolve bot identity: \(error.localizedDescription)"
            authState = .error(error.localizedDescription)
        }
        // Ensure any polling/outer tasks are cleared after success
        devicePollingTask = nil
        oAuthTask = nil
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
        // Clear any polling/outer tasks on error
        devicePollingTask = nil
        oAuthTask = nil
    }

    // deinit handled above to remove all observers
}
