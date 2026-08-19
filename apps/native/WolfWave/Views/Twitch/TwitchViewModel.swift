//
//  TwitchViewModel.swift
//  WolfWave
//
//  Created by Nathanial Henniges on 2026-01-08.
//  Copyright © 2026 MrDemonWolf, Inc. All rights reserved.
//

import Foundation
import Observation
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
@Observable
final class TwitchViewModel {
    /// One app-lifetime owner shared by Settings and Onboarding.
    static let shared = TwitchViewModel()

    /// UI surface that presented a device-code flow. The shared view model uses
    /// this to ensure one window disappearing cannot cancel another window lifecycle.
    enum OAuthPresentationOwner: Equatable {
        case settings(UUID)
        case onboarding(UUID)
        case unspecified
    }

    // MARK: - Channel Validation State

    /// State of the channel name validation check.
    enum ChannelValidationState: Equatable {
        case idle
        case validating
        case valid
        case invalid
        case error(String)
    }

    // MARK: - Observable State

    /// The bot account's Twitch username, resolved after OAuth completes.
    var botUsername = ""
    /// The raw OAuth token used for Twitch API calls.
    var oauthToken = ""
    /// The target Twitch channel name the bot connects to.
    var channelID = ""
    /// Whether valid credentials exist in the Keychain.
    var credentialsSaved = false
    /// Whether the bot is actively connected to a Twitch channel.
    var channelConnected = false
    /// Whether a channel join attempt is currently in progress.
    var isConnecting = false
    /// Whether the stored token has expired and the user must sign in again.
    var reauthNeeded = false
    /// Neutral, in-flight progress text ("Verifying channel…", "Connecting to
    /// Twitch…"). Never carries a failure: those are ``connectionError``.
    ///
    /// Replaces the old `statusMessage`, which was documented as "shown below
    /// the auth card" and was read by no view at all. Roughly forty carefully
    /// written failure messages went into it and were never seen. Anything
    /// stored here now renders in `TwitchSettingsView`.
    var progressMessage = ""

    /// The current failure, if any, rendered as an ``ErrorCallout``.
    ///
    /// Modelled rather than stringly-typed so the banner can offer the fix that
    /// matches the cause, instead of one generic sentence for four different
    /// problems.
    var connectionError: UserFacingError?
    /// Current state of the channel name lookup against the Twitch API.
    var channelValidationState: ChannelValidationState = .idle
    /// Current state of the lightweight token validation check.
    var testAuthResult: TestAuthResult = .idle

    // MARK: - Test Auth State

    /// State of the "Test Auth" button feedback.
    enum TestAuthResult: Equatable {
        case idle, testing, success, failure
    }

    // MARK: - Auth State

    /// Tracks where the user is in the OAuth Device Code flow.
    enum AuthState: Equatable {
        case idle
        case requestingCode
        case waitingForAuth(userCode: String, verificationURI: String)
        case inProgress
        case error(String)

        /// Whether the flow is actively running (requesting, waiting, or exchanging).
        var isInProgress: Bool {
            switch self {
            case .inProgress, .requestingCode, .waitingForAuth:
                return true
            default:
                return false
            }
        }

        /// The device code the user enters on Twitch, or empty if not in that state.
        var userCode: String {
            switch self {
            case .waitingForAuth(let code, _):
                return code
            default:
                return ""
            }
        }

        /// The Twitch URL where the user enters the code, or empty if not in that state.
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
    enum IntegrationState: Equatable {
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
        case .connected: return DSColor.success
        case .authorizing: return DSColor.warning
        case .error: return DSColor.error
        case .notConnected: return DSColor.neutral
        }
    }

    /// Current OAuth authentication state
    var authState = AuthState.idle

    /// Cached reference to the Twitch chat service
    @ObservationIgnored private var cachedTwitchService: TwitchChatService?

    /// Long-lived consumer of `service.connectionStateChanges()`. Cancelled and
    /// replaced whenever the service reference changes.
    @ObservationIgnored private var connectionObserverTask: Task<Void, Never>?

    /// Wires the connection-state AsyncStream into `channelConnected` and seeds
    /// the initial value from the actor's nonisolated snapshot. Each call gets
    /// its own per-subscriber stream, so cancelling this view model's iteration
    /// (settings window closing) never starves other consumers.
    private func observeConnection(_ service: TwitchChatService) {
        connectionObserverTask?.cancel()
        // Register first so a transition between the snapshot and iteration is
        // buffered by AsyncStream instead of being lost.
        let stateChanges = service.connectionStateChanges()
        self.channelConnected = service.currentlyConnected
        connectionObserverTask = Task { [weak self] in
            for await isConnected in stateChanges {
                self?.channelConnected = isConnected
            }
        }
    }

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
                observeConnection(service)
                return service
            }

            Log.error(
                "TwitchViewModel: AppDelegate.shared is nil or service not available",
                category: .twitch)
            return nil
        }
        set {
            cachedTwitchService = newValue
            if let svc = newValue {
                observeConnection(svc)
            } else {
                connectionObserverTask?.cancel()
                connectionObserverTask = nil
            }
        }
    }

    /// Outer task that drives the overall OAuth flow (request + polling)
    @ObservationIgnored var oAuthTask: Task<Void, Never>?
    /// Supersedes UI mutations and cleanup from an older OAuth flow.
    @ObservationIgnored private var oauthGeneration: UInt64 = 0
    /// Set only after the replacement flow has awaited service teardown. OAuth
    /// cancellation may invalidate this revision without racing the old reward
    /// pause; before then, generation + task cancellation are sufficient.
    @ObservationIgnored private var oauthCredentialRevision: UInt64?
    /// Presentation cancellation stops at the durable grant commit boundary.
    @ObservationIgnored private var oauthGrantCommitted = false
    /// Surface whose lifecycle currently owns device-code presentation.
    @ObservationIgnored private var oauthPresentationOwner: OAuthPresentationOwner?
    /// Owns the current validate+join pipeline so logout/account replacement can
    /// cancel it before clearing credentials and leaving the actor service.
    @ObservationIgnored private var joinTask: Task<Void, Never>?
    @ObservationIgnored private var joinGeneration: UInt64 = 0
    /// Fences identity completion from overwriting a newer channel text edit.
    @ObservationIgnored private var channelDraftGeneration: UInt64 = 0
    /// Prevents a second production surface from rehydrating over a live draft.
    @ObservationIgnored private var hasLoadedSavedCredentials = false
    /// Task that resets the test-auth result badge back to idle after a delay.
    @ObservationIgnored private var pendingAuthResetTask: Task<Void, Never>?
    /// In-flight task for the lightweight token validation check.
    @ObservationIgnored private var pendingTestAuthTask: Task<Void, Never>?
    /// Stops the validation owner for the account being replaced or cleared.
    @ObservationIgnored private let cancelTokenValidationSchedule:
        @MainActor @Sendable () -> Void
    /// Starts the app-lifetime validation owner immediately after a durable
    /// OAuth grant commit, before identity resolution can suspend or cancel.
    @ObservationIgnored private let restartTokenValidationSchedule:
        @MainActor @Sendable () -> Void
    /// Resolves the Twitch client ID for validation and channel joins.
    @ObservationIgnored private let twitchClientIDProvider:
        @MainActor @Sendable () -> String?
    /// Resolves configuration and constructs one test-injectable device-flow client.
    @ObservationIgnored private let makeOAuthClient:
        @MainActor @Sendable () -> (clientID: String, auth: TwitchDeviceAuth)?
    /// Injectable identity lookup keeps OAuth commit ordering deterministic in
    /// lifecycle tests without performing a live Helix request.
    @ObservationIgnored private let resolveBotIdentity:
        @MainActor @Sendable (String, String, UInt64) async throws -> Void
    /// Test-injectable account leave keeps cancellation ordering deterministic.
    @ObservationIgnored private let leaveAccountService:
        @MainActor @Sendable (TwitchChatService?, Bool) async -> Bool
    /// Prevents a replacement OAuth/join from starting while an older account
    /// teardown is still awaiting actor-owned refresh/socket cleanup.
    private(set) var isAccountTeardownInProgress = false

    /// Tracked notification observer tokens for proper cleanup
    @ObservationIgnored private var reauthObserver: NSObjectProtocol?
    @ObservationIgnored private var connectionObserver: NSObjectProtocol?

    // MARK: - Initialization

    init(
        cancelTokenValidationSchedule: @escaping @MainActor @Sendable () -> Void = {
            AppDelegate.shared?.cancelTwitchBootValidation()
        },
        restartTokenValidationSchedule: @escaping @MainActor @Sendable () -> Void = {
            AppDelegate.shared?.restartTwitchTokenValidationSchedule()
        },
        twitchClientIDProvider: @escaping @MainActor @Sendable () -> String? = {
            TwitchChatService.resolveClientID()
        },
        makeOAuthClient: @escaping @MainActor @Sendable ()
            -> (clientID: String, auth: TwitchDeviceAuth)? = {
            guard let clientID = TwitchChatService.resolveClientID(),
                  !clientID.isEmpty else { return nil }
            return (
                clientID,
                TwitchDeviceAuth(
                    clientID: clientID,
                    scopes: AppConstants.Twitch.allScopes
                )
            )
        },
        resolveBotIdentity: @escaping @MainActor @Sendable (
            String,
            String,
            UInt64
        ) async throws -> Void = { token, clientID, revision in
            try await TwitchChatService.resolveBotIdentityStatic(
                token: token,
                clientID: clientID,
                credentialRevision: revision
            )
        },
        leaveAccountService: @escaping @MainActor @Sendable (
            TwitchChatService?,
            Bool
        ) async -> Bool = { service, discardOpaqueRedemptionRecovery in
            guard let service else {
                return TwitchManagedRewardStore.snapshot() == .none
                    && (discardOpaqueRedemptionRecovery
                        || !TwitchRedemptionResolutionOutbox.shared
                            .hasOpaqueRecoveryRisk())
            }
            return await service.leaveChannel(
                allowDiscardingOpaqueRedemptionRecovery:
                    discardOpaqueRedemptionRecovery)
        }
    ) {
        self.cancelTokenValidationSchedule = cancelTokenValidationSchedule
        self.restartTokenValidationSchedule = restartTokenValidationSchedule
        self.twitchClientIDProvider = twitchClientIDProvider
        self.makeOAuthClient = makeOAuthClient
        self.resolveBotIdentity = resolveBotIdentity
        self.leaveAccountService = leaveAccountService
        // Immediately try to get the service reference on initialization
        if let appDelegate = AppDelegate.shared {
            self.cachedTwitchService = appDelegate.twitchService
            if let svc = appDelegate.twitchService {
                observeConnection(svc)
            }
        }
    }

    /// Cancels the active OAuth flow, waits for its old-account leave boundary,
    /// then restores validation only if no newer flow superseded this cancel.
    func cancelOAuth(
        ifOwnedBy owner: OAuthPresentationOwner? = nil,
        expectedGeneration: UInt64? = nil
    ) async {
        if let owner, oauthPresentationOwner != owner { return }
        if let expectedGeneration, oauthGeneration != expectedGeneration { return }
        guard !oauthGrantCommitted else { return }
        let outer = oAuthTask
        let hadCredentialRevision = oauthCredentialRevision != nil
        oauthGeneration &+= 1
        let generation = oauthGeneration
        if hadCredentialRevision {
            TwitchCredentialStore.shared.supersede()
        }
        oauthCredentialRevision = nil
        oauthPresentationOwner = nil
        outer?.cancel()
        oAuthTask = nil

        if let outer {
            await outer.value
        }
        guard oauthGeneration == generation else { return }

        if outer != nil {
            restoreTokenValidationScheduleForStoredCredential()
        }
        authState = .idle
        progressMessage = ""
    }

    /// Captures the current UI flow generation before scheduling async teardown.
    /// A delayed disappearance task therefore cannot cancel a replacement flow.
    @discardableResult
    func requestOAuthCancellation(
        ifOwnedBy owner: OAuthPresentationOwner
    ) -> Task<Void, Never>? {
        guard oauthPresentationOwner == owner, oAuthTask != nil else { return nil }
        let expectedGeneration = oauthGeneration
        return Task { @MainActor [weak self] in
            await self?.cancelOAuth(
                ifOwnedBy: owner,
                expectedGeneration: expectedGeneration
            )
        }
    }

    // MARK: - Computed Properties

    /// Status chip text based on current state
    var statusChipText: String {
        if reauthNeeded { return "Sign-in expired" }
        if channelConnected { return "Connected" }
        if credentialsSaved { return "Signed in" }
        return "Not signed in"
    }

    /// Status chip color based on current state
    var statusChipColor: Color {
        if reauthNeeded { return DSColor.warning }
        if channelConnected { return DSColor.success }
        // Informational tint when the app is signed in but not actively joined.
        if credentialsSaved { return DSColor.info }
        // Not signed in. `StatusChip` already renders the tint at 10% for its
        // background wash, so the token is used at full strength here.
        return DSColor.neutral
    }

    // MARK: - Public Methods

    /// Loads saved credentials from macOS Keychain.
    ///
    /// Also loads the reauth needed flag and sets up notification observers for auth state changes.
    func loadSavedCredentials() {
        guard !hasLoadedSavedCredentials else { return }
        do {
            let grant = try KeychainService.loadTwitchCredentialGrantChecked()
            botUsername = grant.username ?? ""
            oauthToken = grant.accessToken ?? ""
            channelID = grant.channelID ?? ""
            credentialsSaved = grant.accessToken?.isEmpty == false
            hasLoadedSavedCredentials = true
        } catch {
            // A Keychain outage is not proof that the account disappeared. Keep
            // the last coherent UI snapshot and let the user retry the read.
            Log.error(
                "TwitchViewModel: Could not read saved Twitch credentials - "
                    + error.localizedDescription,
                category: .twitch
            )
            if connectionError == nil {
                connectionError = Failure.keychainUnreadable()
            }
        }

        // Load reauth needed flag from UserDefaults
        reauthNeeded = Preferences.twitchReauthNeeded

        // Idempotent: only register observers once across repeated calls.
        // Notifications already arrive on `.main` (queue: .main), so we can mutate
        // @MainActor state directly via `MainActor.assumeIsolated`, no Task hop.
        if reauthObserver == nil {
            reauthObserver = NotificationCenter.default.addObserver(
                forName: Notification.Name.twitchReauthNeededChanged,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.reauthNeeded = Preferences.twitchReauthNeeded
                }
            }
        }

        if connectionObserver == nil {
            connectionObserver = NotificationCenter.default.addObserver(
                forName: TwitchChatService.connectionStateChanged,
                object: nil,
                queue: .main
            ) { [weak self] note in
                let isConnected = note.isConnectedFlag
                let errorMessage = note.errorMessage
                MainActor.assumeIsolated {
                    self?.handleTwitchConnectionState(
                        isConnected: isConnected, errorMessage: errorMessage)
                }
            }
        }
    }

    /// Updates connection UI state from extracted notification values.
    private func handleTwitchConnectionState(isConnected: Bool?, errorMessage: String?) {
        guard let isConnected else {
            Log.error(
                "TwitchViewModel: Notification userInfo missing or invalid", category: .twitch)
            return
        }

        self.channelConnected = isConnected
        self.isConnecting = false
        if isConnected {
            // Connected state is conveyed by the status chip, not prose.
            self.progressMessage = ""
            self.connectionError = nil
        } else {
            self.progressMessage = ""
            if let error = errorMessage {
                self.connectionError = error.contains("timed out") || error.contains("timeout")
                    ? Failure.connectionTimedOut()
                    : Failure.connectionFailed(error)
                Log.error(
                    "TwitchViewModel: Connection error - \(error)", category: .twitch)
            } else if self.reauthNeeded {
                self.connectionError = Failure.signInExpired()
                Log.warn("TwitchViewModel: UI updated - Reauth needed", category: .twitch)
            }
            // A plain disconnect is not a failure, so it clears nothing and
            // shows nothing. The chip already reads "Disconnected".
        }
    }

    // Isolated teardown cancels only resources owned by this instance.
    // App-global token validation is owned by AppDelegate, never by deinit.
    isolated deinit {
        oAuthTask?.cancel()
        joinTask?.cancel()
        pendingAuthResetTask?.cancel()
        pendingTestAuthTask?.cancel()
        connectionObserverTask?.cancel()
        if let token = reauthObserver {
            NotificationCenter.default.removeObserver(token)
        }
        if let token = connectionObserver {
            NotificationCenter.default.removeObserver(token)
        }
        cachedTwitchService = nil
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
    /// - authState cycles: idle -> requestingCode -> waitingForAuth -> inProgress, then
    ///   back to idle on success or to error(_) on failure
    /// - progressMessage carries in-flight progress; failures set connectionError
    /// - All UI updates dispatched to @MainActor
    ///
    /// Error Handling:
    /// - Missing Client ID: Shows warning and sets error state
    /// - Network/parsing errors: Handled by handleOAuthError
    /// - User denial: Caught during polling and shown as error
    /// - Timeout: Polling stops at Twitch's original device-code expiry deadline
    ///
    /// Dependencies:
    /// - Requires TWITCH_CLIENT_ID environment variable in Xcode scheme
    /// - Requires internet connectivity
    ///
    func startOAuth(owner: OAuthPresentationOwner = .unspecified) {
        guard !isAccountTeardownInProgress else { return }

        guard let oauthClient = makeOAuthClient() else {
            connectionError = Failure.missingClientID()
            authState = .error("Missing Client ID")
            return
        }
        let clientID = oauthClient.clientID
        let helper = oauthClient.auth

        let serviceToDisconnect = cancelJoinForAccountTransition()
        oauthGeneration &+= 1
        let generation = oauthGeneration
        oAuthTask?.cancel()
        oauthCredentialRevision = nil
        oauthGrantCommitted = false
        oauthPresentationOwner = owner
        oAuthTask = nil

        // Keep the old app-lifetime validator from re-adopting or reconnecting
        // the prior account while its replacement device flow is in progress.
        cancelTokenValidationSchedule()

        authState = .requestingCode
        progressMessage = "Requesting authorization code from Twitch..."

        // One structured task owns both the device-code request and polling.
        oAuthTask = Task { @MainActor [weak self] in
            guard let self else { return }
            var validationOwnershipHandled = false
            defer {
                if self.oauthGeneration == generation {
                    self.oAuthTask = nil
                    self.oauthCredentialRevision = nil
                    self.oauthPresentationOwner = nil
                    if !validationOwnershipHandled {
                        // Restore whichever durable grant survived only when the
                        // success path did not already settle validation ownership.
                        self.restoreTokenValidationScheduleForStoredCredential()
                    }
                }
            }
            do {
                // Account replacement owns the service lifecycle: retire the
                // existing socket before changing the credential revision, so
                // no old join or receive loop can survive under the new grant.
                guard await self.leaveServiceForAccountTransition(
                    serviceToDisconnect) else {
                    guard !Task.isCancelled,
                          self.oauthGeneration == generation else { return }
                    self.showAccountTeardownRetry()
                    return
                }
                guard !Task.isCancelled, self.oauthGeneration == generation else { return }
                await TwitchTokenRefresher.invalidateSession()
                guard !Task.isCancelled, self.oauthGeneration == generation else { return }
                let credentialRevision = TwitchCredentialStore.shared.supersede()
                self.oauthCredentialRevision = credentialRevision

                let response = try await helper.requestDeviceCode()
                guard !Task.isCancelled, self.oauthGeneration == generation else { return }
                self.updateAuthState(
                    .waitingForAuth(
                        userCode: response.userCode,
                        verificationURI: response.verificationURIComplete
                            ?? response.verificationURI)
                )
                self.progressMessage = "Code ready. Enter it on Twitch to finish."

                // TwitchDeviceAuth owns the one monotonic expiry deadline from
                // the server response. Keep no competing UI timer here.
                let grant = try await helper.pollForToken(
                    deviceCode: response.deviceCode,
                    interval: response.interval,
                    expiresIn: response.expiresIn
                ) { status in
                    Task { @MainActor [weak self] in
                        guard let self,
                              self.oauthGeneration == generation,
                              !Task.isCancelled else { return }
                        self.progressMessage = status
                    }
                }

                guard !Task.isCancelled, self.oauthGeneration == generation else { return }
                validationOwnershipHandled = await self.handleOAuthSuccess(
                    grant: grant,
                    clientID: clientID,
                    generation: generation,
                    credentialRevision: credentialRevision
                )
            } catch is CancellationError {
                guard self.oauthGeneration == generation else { return }
                self.progressMessage = "Authorization cancelled"
                self.authState = .idle
            } catch let error as TwitchDeviceAuthError {
                guard !Task.isCancelled, self.oauthGeneration == generation else { return }
                await self.handleOAuthError(error, generation: generation)
            } catch {
                guard !Task.isCancelled, self.oauthGeneration == generation else { return }
                await self.handleOAuthError(
                    .unknown(error.localizedDescription),
                    generation: generation
                )
            }
        }
    }

    /// Marks a channel edit as an uncommitted UI draft. The draft becomes
    /// canonical only after Join validates that the channel exists.
    func channelDraftChanged() {
        guard !isAccountTeardownInProgress else { return }
        channelDraftGeneration &+= 1
        Preferences.clearPendingImportedTwitchChannelName()
        channelValidationState = .idle
        joinGeneration &+= 1
        joinTask?.cancel()
        joinTask = nil
        isConnecting = false
    }

    /// Clears all stored Twitch credentials and resets state.
    @discardableResult
    func clearCredentials(
        discardOpaqueRedemptionRecovery: Bool = false
    ) async -> Bool {
        guard !isAccountTeardownInProgress else { return false }
        isAccountTeardownInProgress = true
        defer { isAccountTeardownInProgress = false }
        cancelTokenValidationSchedule()
        // Cancel task/UI owners synchronously, but do not supersede the
        // credential revision until the old service transport is fully gone.
        joinGeneration &+= 1
        joinTask?.cancel()
        joinTask = nil
        oauthGeneration &+= 1
        oAuthTask?.cancel()
        oAuthTask = nil
        oauthCredentialRevision = nil
        oauthGrantCommitted = false
        pendingTestAuthTask?.cancel()
        pendingTestAuthTask = nil
        let service = twitchService
        await TwitchTokenRefresher.invalidateSession()
        guard await leaveServiceForAccountTransition(
            service,
            discardOpaqueRedemptionRecovery: discardOpaqueRedemptionRecovery
        ) else {
            restoreTokenValidationScheduleForStoredCredential()
            showAccountTeardownRetry()
            return false
        }
        do {
            try TwitchCredentialStore.shared.clearCredentials(
                includingChannel: true)
        } catch {
            restoreTokenValidationScheduleForStoredCredential()
            showCredentialDeletionRetry(error)
            return false
        }

        // Clear all state only after the Keychain transaction commits.
        botUsername = ""
        oauthToken = ""
        channelID = ""
        Preferences.clearPendingImportedTwitchChannelName()
        credentialsSaved = false
        setReauthFlag(false)
        progressMessage = ""
        authState = .idle
        channelValidationState = .idle
        isConnecting = false
        channelConnected = false
        return true
    }

    /// Clears OAuth credentials and bot identity without touching the channel name.
    /// Use for re-authentication flows where the target channel should be preserved.
    @discardableResult
    func clearAuthOnly() async -> Bool {
        guard !isAccountTeardownInProgress else { return false }
        isAccountTeardownInProgress = true
        defer { isAccountTeardownInProgress = false }
        cancelTokenValidationSchedule()
        // Cancel task/UI owners synchronously, but do not supersede the
        // credential revision until the old service transport is fully gone.
        joinGeneration &+= 1
        joinTask?.cancel()
        joinTask = nil
        oauthGeneration &+= 1
        oAuthTask?.cancel()
        oAuthTask = nil
        oauthCredentialRevision = nil
        oauthGrantCommitted = false
        pendingTestAuthTask?.cancel()
        pendingTestAuthTask = nil
        let service = twitchService
        await TwitchTokenRefresher.invalidateSession()
        guard await leaveServiceForAccountTransition(service) else {
            restoreTokenValidationScheduleForStoredCredential()
            showAccountTeardownRetry()
            return false
        }
        do {
            try TwitchCredentialStore.shared.clearCredentials(
                includingChannel: false)
        } catch {
            restoreTokenValidationScheduleForStoredCredential()
            showCredentialDeletionRetry(error)
            return false
        }

        botUsername = ""
        oauthToken = ""
        credentialsSaved = false
        setReauthFlag(false)
        progressMessage = ""
        authState = .idle
        channelValidationState = .idle
        isConnecting = false
        channelConnected = false
        return true
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
    /// 1. Validates the draft channel against Twitch
    /// 2. Safely drains and leaves the prior EventSub broadcaster
    /// 3. Commits the validated channel with credential compare-and-swap
    /// 4. Establishes the replacement EventSub WebSocket connection
    /// 5. Updates UI state on success/failure
    ///
    /// UI Updates:
    /// - Success: clears any error, sets channelConnected=true
    /// - Failure: Shows error message with reason, keeps channelConnected=false
    /// - All updates dispatched to @MainActor
    ///
    /// Error Handling:
    /// - ConnectionError subclasses for specific failures (auth, network, config)
    /// - Generic errors from system are caught and displayed
    /// - Errors are logged; UI shows user-friendly messages
    ///
    /// The canonical channel remains unchanged if validation or safe teardown
    /// fails, so reconnect owners never observe an unvalidated draft.
    ///
    func joinChannel() {
        guard !isAccountTeardownInProgress else { return }
        guard !authState.isInProgress else {
            progressMessage = "Finish or cancel Twitch sign-in before joining a channel."
            return
        }
        joinTask?.cancel()
        joinGeneration &+= 1
        let generation = joinGeneration
        isConnecting = true

        let channelDraft = channelID
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        guard !channelDraft.isEmpty else {
            connectionError = Failure.channelNameInvalid("Enter the channel WolfWave should join.")
            isConnecting = false
            return
        }

        guard channelDraft.count <= 25 else {
            connectionError = Failure.channelNameInvalid("Twitch names are 25 characters or fewer.")
            isConnecting = false
            return
        }

        guard let channel = TwitchChatService.normalizedChannelName(channelDraft) else {
            connectionError = Failure.channelNameInvalid("Use only letters, numbers, or underscores.")
            channelValidationState = .invalid
            isConnecting = false
            return
        }

        guard let clientID = twitchClientIDProvider(), !clientID.isEmpty else {
            connectionError = Failure.missingClientID()
            isConnecting = false
            return
        }

        guard let credential = TwitchCredentialStore.shared.connectionSnapshot() else {
            connectionError = Failure.noCredentials()
            Log.error("TwitchViewModel: No OAuth token found", category: .twitch)
            isConnecting = false
            return
        }

        joinTask = Task { @MainActor [weak self] in
            guard let self else { return }
            defer {
                if self.joinGeneration == generation {
                    self.joinTask = nil
                }
            }
            do {
                // Access the service property which will fetch from AppDelegate if needed
                guard let service = self.twitchService else {
                    self.connectionError = Failure.serviceUnavailable()
                    self.isConnecting = false
                    Log.error(
                        "TwitchViewModel: twitchService property returned nil", category: .twitch)
                    return
                }

                // Validate channel exists before attempting connection
                self.channelValidationState = .validating
                self.progressMessage = "Verifying channel..."

                let validationResult = await service.validateChannelExists(
                    channel, token: credential.accessToken, clientID: clientID)
                guard !Task.isCancelled,
                      self.joinGeneration == generation,
                      !self.isAccountTeardownInProgress,
                      TwitchCredentialStore.shared.connectionSnapshot() == credential else {
                    throw CancellationError()
                }

                switch validationResult {
                case .exists:
                    break
                case .notFound:
                    self.channelValidationState = .invalid
                    self.connectionError = Failure.channelNotFound(channel)
                    self.isConnecting = false
                    return
                case .authenticationFailed:
                    self.channelValidationState = .error("Authentication failed")
                    self.connectionError = Failure.signInExpired()
                    self.isConnecting = false
                    return
                case .notPermitted(let status):
                    // Twitch accepted the sign-in and refused the lookup, so
                    // reconnecting would not help. Say which it was.
                    self.channelValidationState = .error(Self.notPermittedMessage(status: status))
                    self.isConnecting = false
                    return
                case .error(let message):
                    self.channelValidationState = .error(message)
                    self.connectionError = Failure.connectionFailed(message)
                    self.isConnecting = false
                    return
                }

                // Quiesce and drain the old broadcaster before publishing the
                // new canonical channel. This keeps the old managed reward from
                // accepting a paid redemption in the commit-to-disconnect gap.
                guard await self.leaveServiceForAccountTransition(service) else {
                    guard self.joinGeneration == generation else { return }
                    self.channelValidationState = .error("Could not safely disconnect")
                    self.connectionError = Failure.disconnectFailed()
                    self.isConnecting = false
                    return
                }
                guard !Task.isCancelled,
                      self.joinGeneration == generation,
                      !self.isAccountTeardownInProgress,
                      TwitchCredentialStore.shared.connectionSnapshot() == credential else {
                    throw CancellationError()
                }

                guard let committedCredential = try TwitchCredentialStore.shared
                    .commitChannelID(channel, expected: credential) else {
                    throw CancellationError()
                }
                Preferences.clearPendingImportedTwitchChannelName()
                self.restartTokenValidationSchedule()
                self.channelValidationState = .valid

                Log.info(
                    "TwitchViewModel: Twitch service found, starting connection to channel: \(channel)",
                    category: .twitch)

                self.progressMessage = "Connecting to Twitch..."

                await service.setShouldSendConnectionMessageOnSubscribe(true)
                guard !Task.isCancelled,
                      self.joinGeneration == generation,
                      !self.isAccountTeardownInProgress,
                      TwitchCredentialStore.shared.connectionSnapshot() == committedCredential else {
                    throw CancellationError()
                }

                try await service.connectToChannel(
                    channelName: channel,
                    token: committedCredential.accessToken,
                    clientID: clientID,
                    expectedCredentialRevision: committedCredential.revision
                )

                // Don't set channelConnected here - it will be set by the notification
                // from the service when the EventSub session is actually established
                guard self.joinGeneration == generation else { return }
                self.progressMessage = "Waiting for connection..."
            } catch is CancellationError {
                if self.joinGeneration == generation {
                    self.isConnecting = false
                }
                return
            } catch let error as TwitchChatService.ConnectionError {
                guard self.joinGeneration == generation else { return }
                self.connectionError = Failure.connectionFailed(error.localizedDescription)
                self.channelConnected = false
                self.isConnecting = false
            } catch {
                guard self.joinGeneration == generation else { return }
                self.connectionError = Failure.connectionFailed(error.localizedDescription)
                self.channelConnected = false
                self.isConnecting = false
            }
        }
    }

    /// Validates the stored OAuth token against the Twitch API without making a full connection.
    ///
    /// Performs a lightweight HTTP GET to the Twitch token validation endpoint
    /// to verify the token is still valid and has the required scopes.
    func testConnection() {
        let token: String
        do {
            guard let storedToken = try KeychainService
                .loadTwitchCredentialGrantChecked().accessToken,
                  !storedToken.isEmpty else {
                connectionError = Failure.noCredentials()
                testAuthResult = .failure
                scheduleTestAuthReset()
                return
            }
            token = storedToken
        } catch {
            connectionError = Failure.keychainUnreadable()
            testAuthResult = .failure
            scheduleTestAuthReset()
            return
        }

        guard let service = twitchService else {
            connectionError = Failure.serviceUnavailable()
            testAuthResult = .failure
            scheduleTestAuthReset()
            return
        }

        progressMessage = "Testing token…"
        testAuthResult = .testing

        // Cancel any in-flight test-auth task to prevent stale resets
        pendingTestAuthTask?.cancel()
        pendingTestAuthTask = Task {
            let result = await service.validateToken(token)
            guard !Task.isCancelled else { return }
            switch result {
            case .valid:
                self.progressMessage = "Token is valid."
                self.testAuthResult = .success
            case .invalid:
                self.connectionError = Failure.signInExpired()
                self.testAuthResult = .failure
            case .missingScopes(let scopes):
                // The token works. Reporting this as a failure would be a lie,
                // and would push the user to reconnect a live session.
                self.connectionError = Failure.missingScopes(scopes)
                self.testAuthResult = .success
            case .temporarilyUnavailable:
                self.connectionError = Failure.connectionFailed("Twitch could not be reached to check the token.")
                self.testAuthResult = .failure
            }
            self.scheduleTestAuthReset()
        }
    }

    /// Silently re-validates the saved OAuth token so the status chip flips to
    /// "Sign-in expired" on its own when a token dies, without the user pressing
    /// a button. Called on a cadence by the settings pane while it's open.
    ///
    /// No-ops when there's nothing to check (no saved credentials) or when reauth
    /// is already flagged. Unlike `testConnection()`, this never touches
    /// `testAuthResult` or `connectionError` so it stays invisible until something
    /// actually changes.
    func refreshAuthStatus() async {
        guard credentialsSaved, !reauthNeeded else { return }
        let token: String
        do {
            guard let storedToken = try KeychainService
                .loadTwitchCredentialGrantChecked().accessToken,
                  !storedToken.isEmpty else { return }
            token = storedToken
        } catch {
            Log.warn(
                "TwitchViewModel: Skipping background token validation because "
                    + "Keychain is temporarily unavailable",
                category: .twitch
            )
            return
        }
        guard let service = twitchService else { return }

        let result = await service.validateToken(token)
        applyTokenValidationResult(result)
    }

    /// Applies a background validation result without conflating an outage with
    /// an expired grant. Internal so the credential-preservation rule has direct
    /// regression coverage without performing a live Twitch request.
    func applyTokenValidationResult(_ result: TwitchChatService.TokenValidationResult) {
        // Only Twitch's explicit invalid-token response (or confirmed missing
        // required scopes) may expire the local session. Outages are retried on
        // the next cadence without touching credentials or the re-auth flag.
        guard result == .invalid else { return }
        setReauthFlag(true)
    }

    /// Resets `testAuthResult` back to `.idle` after 3 seconds.
    private func scheduleTestAuthReset() {
        pendingAuthResetTask?.cancel()
        pendingAuthResetTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            self.testAuthResult = .idle
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
        guard let service = twitchService else {
            channelConnected = false
            return
        }
        Task { @MainActor [weak self] in
            guard let self else { return }
            if await service.leaveChannel() {
                self.channelConnected = false
            } else {
                self.connectionError = Failure.disconnectFailed()
            }
        }
    }

    // MARK: - Private Methods

    // MARK: - Error Construction

    /// Builds the errors this view model can surface.
    ///
    /// Grouped in one place so the copy stays consistent and each failure keeps
    /// the action that actually fixes it. Reconnect is offered only where a new
    /// sign-in genuinely helps.
    enum Failure {
        static func keychainUnreadable() -> UserFacingError {
            UserFacingError(
                id: "twitch.keychainUnreadable",
                title: "Couldn't read your saved Twitch sign-in",
                cause: "macOS blocked WolfWave from reading the Keychain.",
                fix: "Try again. If it keeps happening, sign in once more.",
                severity: .error,
                actions: [.retry, .reportBug]
            )
        }

        static func keychainWriteFailed() -> UserFacingError {
            UserFacingError(
                id: "twitch.keychainWriteFailed",
                title: "Couldn't save your Twitch sign-in",
                cause: "macOS blocked WolfWave from writing to the Keychain.",
                fix: "You'll be asked to sign in again next launch.",
                severity: .error,
                actions: [.reconnectTwitch, .reportBug],
                docsAnchor: "keychain-write-failed"
            )
        }

        /// Signing out could not remove the stored grant, so the account is
        /// still signed in. Says so plainly rather than implying it worked.
        static func credentialClearFailed() -> UserFacingError {
            UserFacingError(
                id: "twitch.credentialClearFailed",
                title: "Couldn't sign out of Twitch",
                cause: "macOS wouldn't let WolfWave remove the saved sign-in, "
                    + "so you are still signed in.",
                fix: "Try again. If it keeps failing, restart your Mac.",
                severity: .error,
                actions: [.retry, .reportBug],
                docsAnchor: "keychain-write-failed"
            )
        }

        /// The token works; a feature-specific permission is absent. Reconnect
        /// is the right fix here, and the only place it is offered for a token
        /// Twitch still honors.
        static func missingScopes(_ scopes: [String]) -> UserFacingError {
            UserFacingError(
                id: "twitch.missingScopes",
                title: "Signed in, but missing a permission",
                cause: "WolfWave wasn't granted: \(scopes.joined(separator: ", ")).",
                fix: "Reconnect to grant it. Everything else keeps working.",
                severity: .warning,
                actions: [.reconnectTwitch],
                docsAnchor: "twitch-missing-permission"
            )
        }

        static func missingClientID() -> UserFacingError {
            UserFacingError(
                id: "twitch.missingClientID",
                title: "WolfWave isn't set up for Twitch",
                cause: "This build has no Twitch Client ID.",
                fix: "Reinstall from the website, or set TWITCH_CLIENT_ID in Config.xcconfig.",
                severity: .error,
                actions: [.openDocs(anchor: "twitch-client-id")],
                docsAnchor: "twitch-client-id"
            )
        }

        static func signInExpired() -> UserFacingError {
            UserFacingError(
                id: "twitch.signInExpired",
                title: "Twitch sign-in expired",
                cause: "Chat commands stopped working.",
                fix: "Reconnect and WolfWave picks up where it left off.",
                severity: .warning,
                actions: [.reconnectTwitch],
                docsAnchor: "twitch-sign-in-expired"
            )
        }

        static func noCredentials() -> UserFacingError {
            UserFacingError(
                id: "twitch.noCredentials",
                title: "Not signed in to Twitch",
                fix: "Connect with Twitch to get started.",
                severity: .info,
                actions: [.reconnectTwitch]
            )
        }

        static func channelNameInvalid(_ reason: String) -> UserFacingError {
            UserFacingError(
                id: "twitch.channelNameInvalid",
                title: "That channel name won't work",
                cause: reason,
                severity: .error
            )
        }

        static func channelNotFound(_ channel: String) -> UserFacingError {
            UserFacingError(
                id: "twitch.channelNotFound",
                title: "No Twitch channel by that name",
                cause: "Nothing on Twitch matches \(StreamerMode.mask(channel, style: .channel, isOn: StreamerMode.isEnabled)).",
                fix: "Check the spelling, then choose Join.",
                severity: .error,
                docsAnchor: "channel-not-found"
            )
        }

        /// Twitch accepted the sign-in and refused the lookup, so a reconnect
        /// is deliberately not offered.
        static func lookupRefused(status: Int) -> UserFacingError {
            UserFacingError(
                id: "twitch.lookupRefused",
                title: status == 429
                    ? "Your sign-in is fine, we're being rate limited"
                    : "Your sign-in is fine, Twitch isn't",
                cause: TwitchViewModel.notPermittedMessage(status: status),
                severity: .warning,
                actions: [.retry],
                docsAnchor: "sign-in-is-fine"
            )
        }

        static func connectionFailed(_ detail: String) -> UserFacingError {
            UserFacingError(
                id: "twitch.connectionFailed",
                title: "Couldn't connect to Twitch chat",
                cause: detail,
                fix: "Try again in a moment.",
                severity: .error,
                actions: [.retry]
            )
        }

        static func connectionTimedOut() -> UserFacingError {
            UserFacingError(
                id: "twitch.connectionTimedOut",
                title: "Twitch didn't respond",
                cause: "The connection timed out. A firewall or VPN can cause this.",
                severity: .warning,
                actions: [.retry]
            )
        }

        static func disconnectFailed() -> UserFacingError {
            UserFacingError(
                id: "twitch.disconnectFailed",
                title: "Couldn't switch channels cleanly",
                cause: "WolfWave couldn't leave the old channel.",
                fix: "Choose Join again.",
                severity: .warning,
                actions: [.retry]
            )
        }

        static func botIdentityUnresolved() -> UserFacingError {
            UserFacingError(
                id: "twitch.botIdentityUnresolved",
                title: "Couldn't confirm which account is posting",
                fix: "Reconnect with Twitch.",
                severity: .warning,
                actions: [.reconnectTwitch]
            )
        }

        static func serviceUnavailable() -> UserFacingError {
            UserFacingError(
                id: "twitch.serviceUnavailable",
                title: "WolfWave couldn't start its Twitch connection",
                fix: "Restart WolfWave.",
                severity: .error,
                actions: [.reportBug]
            )
        }

        static func oauth(_ message: String) -> UserFacingError {
            UserFacingError(
                id: "twitch.oauthFailed",
                title: "Twitch sign-in didn't finish",
                cause: message,
                severity: .warning,
                actions: [.retry]
            )
        }
    }

    /// Copy for a channel lookup Twitch accepted the credentials for but
    /// refused to answer.
    ///
    /// `GET /helix/users` needs no scope, so reaching this at all means the
    /// sign-in is good. Each message leads with that, because the instinct
    /// otherwise is to reconnect, which cannot help.
    nonisolated static func notPermittedMessage(status: Int) -> String {
        switch status {
        case 429:
            return "Your sign-in is fine. Twitch is rate limiting us, so try again in a moment."
        case 500...599:
            return "Your sign-in is fine. Twitch is having trouble right now."
        default:
            return "Your sign-in is fine, but Twitch refused the lookup (HTTP \(status))."
        }
    }

    /// Cancels any join that belongs to the old account before an OAuth/manual
    /// replacement starts. The returned actor is then awaited for transport
    /// teardown by the owning structured task.
    private func cancelJoinForAccountTransition() -> TwitchChatService? {
        joinGeneration &+= 1
        joinTask?.cancel()
        joinTask = nil
        isConnecting = false
        return twitchService
    }

    /// Account replacement/clear may destroy the last credentials able to hold
    /// the managed reward. A newer explicit join supersedes the pending leave;
    /// in that case preserve Keychain state and ask the user to retry instead of
    /// clearing credentials under a live replacement session.
    private func leaveServiceForAccountTransition(
        _ service: TwitchChatService?,
        discardOpaqueRedemptionRecovery: Bool = false
    ) async -> Bool {
        await leaveAccountService(service, discardOpaqueRedemptionRecovery)
    }

    private func showAccountTeardownRetry() {
        let message = "Could not safely disconnect Twitch. Please try again."
        connectionError = Failure.disconnectFailed()
        authState = .error(message)
    }

    private func showCredentialDeletionRetry(_ error: Error) {
        let message = "Could not clear saved Twitch credentials. Please try again."
        connectionError = Failure.credentialClearFailed()
        authState = .error(message)
        Log.error(
            "TwitchViewModel: Keychain credential deletion failed - \(error.localizedDescription)",
            category: .twitch)
    }

    /// Installs exactly one validation owner for whichever durable grant
    /// survived an OAuth cancellation/failure, or leaves validation stopped
    /// when there is no stored account.
    func restoreTokenValidationScheduleForStoredCredential() {
        do {
            if try KeychainService.loadTwitchCredentialGrantChecked().accessToken == nil {
                cancelTokenValidationSchedule()
            } else {
                restartTokenValidationSchedule()
            }
        } catch {
            // A read error is uncertainty, not confirmed absence. Retain a
            // validator owner so a durable token cannot be abandoned silently.
            Log.warn(
                "TwitchViewModel: Conservatively restoring token validation "
                    + "after a Keychain read failure",
                category: .twitch
            )
            restartTokenValidationSchedule()
        }
    }

    /// Updates the published authorization state. Centralized so the
    /// observable-mutation site is consistent in the future when telemetry or
    /// additional side effects are added.
    private func updateAuthState(_ state: AuthState) {
        authState = state
    }

    /// Single write path for the re-auth flag: updates the observable
    /// property, persists via `Preferences.setTwitchReauthNeeded`, and posts
    /// `.twitchReauthNeededChanged` so every observer (menu bar, other view
    /// model instances) stays in sync.
    private func setReauthFlag(_ value: Bool) {
        reauthNeeded = value
        Preferences.setTwitchReauthNeeded(value)
        NotificationCenter.default.post(
            name: Notification.Name.twitchReauthNeededChanged,
            object: nil
        )
    }

    /// Stores a freshly-issued OAuth token in the Keychain, clears the
    /// re-auth flag, and resolves the bot identity (username + user ID) via
    /// Helix so subsequent EventSub subscriptions have everything they need.
    ///
    /// - Parameters:
    ///   - token: New OAuth access token.
    ///   - clientID: Twitch developer client ID used to mint the token.
    @discardableResult
    func handleOAuthSuccess(
        grant: TwitchTokenResponse,
        clientID: String,
        generation: UInt64,
        credentialRevision: UInt64
    ) async -> Bool {
        defer {
            if oauthGeneration == generation {
                oauthGrantCommitted = false
            }
        }
        guard !Task.isCancelled, oauthGeneration == generation else { return false }
        guard let refreshToken = grant.refreshToken, !refreshToken.isEmpty else {
            let message = "OAuth response did not include a refresh token."
            connectionError = Failure.oauth("Twitch didn't return a refresh token.")
            authState = .error(message)
            restoreTokenValidationScheduleForStoredCredential()
            return true
        }
        let initialChannelDraftGeneration = channelDraftGeneration
        cancelTokenValidationSchedule()
        authState = .inProgress
        progressMessage = "Saving credentials\u{2026}"
        let pendingImportedChannel = Preferences.pendingImportedTwitchChannelName
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        let visibleChannel = channelID
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        let channelCandidateWasPending = !pendingImportedChannel.isEmpty
        let channelCandidate = channelCandidateWasPending
            ? pendingImportedChannel
            : (visibleChannel.isEmpty ? nil : visibleChannel)
        var configuredChannel: String?
        var preserveVisibleChannelDraft = false

        if let channelCandidate {
            if TwitchChatService.normalizedChannelName(channelCandidate) == nil {
                preserveVisibleChannelDraft = !channelCandidateWasPending
                channelValidationState = .invalid
                connectionError = Failure.channelNameInvalid("Update it and choose Join.")
            } else {
                channelValidationState = .validating
                progressMessage = "Verifying channel..."
                let validationResult = await twitchService?.validateChannelExists(
                    channelCandidate,
                    token: grant.accessToken,
                    clientID: clientID
                ) ?? .error("Twitch service not initialized")
                guard !Task.isCancelled, oauthGeneration == generation else { return true }

                let currentPendingChannel = Preferences.pendingImportedTwitchChannelName
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .lowercased()
                let currentVisibleChannel = channelID
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .lowercased()
                let candidateIsCurrent = channelCandidateWasPending
                    ? currentPendingChannel == channelCandidate
                    : currentPendingChannel.isEmpty
                        && currentVisibleChannel == channelCandidate

                if candidateIsCurrent {
                    switch validationResult {
                    case .exists:
                        configuredChannel = channelCandidate
                        channelValidationState = .valid
                    case .notFound:
                        preserveVisibleChannelDraft = !channelCandidateWasPending
                        channelValidationState = .invalid
                        connectionError = Failure.channelNotFound(channelCandidate)
                    case .authenticationFailed:
                        preserveVisibleChannelDraft = !channelCandidateWasPending
                        channelValidationState = .error("Authentication failed")
                        connectionError = Failure.signInExpired()
                    case .notPermitted(let status):
                        preserveVisibleChannelDraft = !channelCandidateWasPending
                        channelValidationState = .error(Self.notPermittedMessage(status: status))
                        connectionError = Failure.lookupRefused(status: status)
                    case .error:
                        preserveVisibleChannelDraft = !channelCandidateWasPending
                        channelValidationState = .error("Channel verification failed")
                        connectionError = Failure.connectionFailed(
                            "The channel couldn't be verified.")
                    }
                } else {
                    preserveVisibleChannelDraft = !channelCandidateWasPending
                    channelValidationState = .idle
                }
            }
        }

        do {
            guard try TwitchCredentialStore.shared.commitDeviceGrant(
                grant,
                channelID: configuredChannel,
                expectedRevision: credentialRevision
            ) else {
                return true
            }
            // From this durable boundary onward, presentation lifecycle cannot
            // cancel identity finalization and strand a partial stored grant.
            oauthGrantCommitted = true
            oauthCredentialRevision = nil
            oauthPresentationOwner = nil
            // Install the new app-lifetime owner before any cancellable identity
            // lookup so a committed grant is never left without validation.
            restartTokenValidationSchedule()
            guard !Task.isCancelled, oauthGeneration == generation else { return true }
            oauthToken = grant.accessToken
            if channelCandidateWasPending, configuredChannel != nil {
                Preferences.clearPendingImportedTwitchChannelName()
            }
        } catch {
            Log.error(
                "TwitchViewModel: Failed to save OAuth token: \(error.localizedDescription)",
                category: .twitch
            )
            connectionError = Failure.keychainWriteFailed()
            authState = .error(error.localizedDescription)
            restoreTokenValidationScheduleForStoredCredential()
            return true
        }

        // Resolve bot identity. The committed grant already has an app-lifetime
        // validation owner even if this follow-up lookup fails or is cancelled.
        do {
            try await resolveBotIdentity(
                grant.accessToken,
                clientID,
                credentialRevision)
            guard !Task.isCancelled, oauthGeneration == generation else { return true }
            let committedGrant = try KeychainService.loadTwitchCredentialGrantChecked()
            guard committedGrant.accessToken == grant.accessToken else {
                throw CancellationError()
            }
            guard let username = committedGrant.username, !username.isEmpty else {
                throw TwitchChatService.ConnectionError.invalidCredentials
            }
            botUsername = username
            if channelDraftGeneration == initialChannelDraftGeneration,
               !preserveVisibleChannelDraft {
                channelID = committedGrant.channelID ?? ""
            }
            setReauthFlag(false)
            credentialsSaved = true
            // Sign-in finished. Any problem found while promoting the channel
            // already set `connectionError`, which the pane renders; success
            // needs no prose because the status chip flips to connected.
            progressMessage = ""
            authState = .idle
            await twitchService?.replayPendingRedemptionResolutions()
        } catch is CancellationError {
            guard oauthGeneration == generation else { return true }
            oauthToken = ""
            botUsername = ""
            credentialsSaved = false
            progressMessage = ""
            authState = .idle
            return true
        } catch {
            guard !Task.isCancelled, oauthGeneration == generation else { return true }
            Log.error(
                "TwitchViewModel: Failed to resolve bot identity: \(error.localizedDescription)",
                category: .twitch
            )
            connectionError = Failure.botIdentityUnresolved()
            authState = .error(error.localizedDescription)
        }
        return true
    }

    /// Maps a `TwitchDeviceAuthError` onto the error model and transitions the
    /// auth state machine to `.error` for UI display.
    ///
    /// The two "still working on it" cases are progress, not failure: the
    /// device-code flow polls, and Twitch asking us to wait or slow down is the
    /// protocol behaving normally. Rendering those as errors made a healthy
    /// sign-in look broken.
    ///
    /// - Parameter error: Failure produced by the device-code OAuth flow.
    private func handleOAuthError(
        _ error: TwitchDeviceAuthError,
        generation: UInt64
    ) async {
        guard !Task.isCancelled, oauthGeneration == generation else { return }

        switch error {
        case .authorizationPending:
            progressMessage = "Waiting for you to authorize on Twitch\u{2026}"
            return
        case .slowDown:
            progressMessage = "Waiting for Twitch\u{2026}"
            return
        default:
            break
        }

        let message: String
        let failure: UserFacingError
        switch error {
        case .accessDenied:
            message = "You declined the authorization on Twitch."
            failure = Failure.oauth(message)
        case .expiredToken:
            message = "That sign-in code expired. Codes last only a few minutes."
            failure = Failure.oauth(message)
        case .invalidClient:
            message = "This build's Twitch Client ID was rejected."
            failure = Failure.missingClientID()
        default:
            message = error.localizedDescription
            failure = Failure.oauth(message)
        }
        progressMessage = ""
        connectionError = failure
        authState = .error(message)
    }

    // deinit handled above to remove all observers
}
