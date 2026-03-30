//
//  TwitchChatService.swift
//  wolfwave
//
//  Created by MrDemonWolf, Inc. on 1/17/26.
//

import Foundation
import Network

/// Service managing Twitch chat connection and bot commands via EventSub WebSocket.
///
/// Handles:
/// - WebSocket connection to Twitch EventSub
/// - EventSub subscriptions (channel.chat.message)
/// - Chat message routing to bot commands
/// - Chat message sending and replies
/// - Token validation and user identity resolution
///
/// Thread-safe with all state mutations protected by NSLock.
/// Callbacks occur on background queues; dispatch to main for UI updates.
///
/// Usage:
/// ```swift
/// let service = TwitchChatService()
/// try await service.connectToChannel(
///     channelName: "streamer",
///     token: oauthToken,
///     clientID: clientID
/// )
/// service.sendMessage("Hello, chat!")
/// ```
final class TwitchChatService: @unchecked Sendable {

    struct ChatMessage {
        let messageID: String
        let username: String
        let userID: String
        let message: String
        let channel: String
        let badges: [Badge]
        let reply: Reply?

        struct Badge {
            let setID: String
            let id: String
            let info: String
        }

        struct Reply {
            let parentMessageID: String
            let parentMessageBody: String
            let parentUserID: String
            let parentUsername: String
        }
    }

    enum ConnectionError: LocalizedError {
        case invalidCredentials
        case missingClientID
        case networkError(String)
        case authenticationFailed

        var errorDescription: String? {
            switch self {
            case .invalidCredentials:
                return "Invalid Twitch credentials"
            case .missingClientID:
                return "Twitch Client ID is not configured"
            case .networkError(let msg):
                return "Network error: \(msg)"
            case .authenticationFailed:
                return "Failed to authenticate with Twitch"
            }
        }
    }

    struct BotIdentity {
        let userID: String
        let login: String
        let displayName: String
    }

    // MARK: - Properties

    private let apiBaseURL = AppConstants.Twitch.apiBaseURL
    private let commandDispatcher = BotCommandDispatcher()

    nonisolated(unsafe) private var webSocketTask: URLSessionWebSocketTask?
    private let urlSession: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 60
        config.timeoutIntervalForResource = 300
        config.waitsForConnectivity = true
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: config)
    }()
    nonisolated(unsafe) private var sessionID: String?
    private let webSocketLock = NSLock()

    private var broadcasterID: String?
    private var botID: String?

    var shouldSendConnectionMessageOnSubscribe = true

    private var oauthToken: String?
    private var clientID: String?
    private var botUsername: String?

    var debugLoggingEnabled = false
    var getCurrentSongInfo: (@Sendable () -> String)?
    var getLastSongInfo: (@Sendable () -> String)?

    var commandsEnabled = true
    
    /// Whether the current song command is enabled (computed from UserDefaults on each access)
    var currentSongCommandEnabled: Bool {
        UserDefaults.standard.object(forKey: AppConstants.UserDefaults.currentSongCommandEnabled) as? Bool ?? false
    }

    /// Whether the last song command is enabled (computed from UserDefaults on each access)
    var lastSongCommandEnabled: Bool {
        UserDefaults.standard.object(forKey: AppConstants.UserDefaults.lastSongCommandEnabled) as? Bool ?? false
    }

    var onMessageReceived: (@Sendable (ChatMessage) -> Void)?
    var onConnectionStateChanged: (@Sendable (Bool) -> Void)?


    static let connectionStateChanged = NSNotification.Name(AppConstants.Notifications.twitchConnectionStateChanged)

    nonisolated(unsafe) private var _connected = false
    nonisolated(unsafe) private var hasSentConnectionMessage = false
    private let connectionLock = NSLock()

    var isConnected: Bool {
        connectionLock.withLock { _connected }
    }

    nonisolated private func setConnected(_ value: Bool) {
        connectionLock.withLock { _connected = value }
    }

    nonisolated(unsafe) private var isProcessingDisconnect = false
    private let disconnectLock = NSLock()

    nonisolated(unsafe) private var networkPathMonitor: NWPathMonitor?
    private let networkMonitorLock = NSLock()
    private let networkMonitorQueue = DispatchQueue(
        label: "com.mrdemonwolf.wolfwave.networkmonitor")

    nonisolated(unsafe) private var isNetworkReachable = true
    private let networkReachableLock = NSLock()

    /// Tracks total network-triggered reconnect cycles to prevent infinite loops
    /// when the network path flaps repeatedly.
    nonisolated(unsafe) private var networkReconnectCycles = 0
    private let maxNetworkReconnectCycles = AppConstants.Twitch.maxNetworkReconnectCycles
    nonisolated(unsafe) private var lastNetworkReconnectTime: TimeInterval = 0

    nonisolated(unsafe) private var reconnectionAttempts = 0
    private let reconnectionLock = NSLock()

    private let maxReconnectionAttempts = AppConstants.Twitch.maxReconnectionAttempts

    nonisolated(unsafe) private var _reconnectChannelName: String?
    nonisolated(unsafe) private var _reconnectToken: String?
    nonisolated(unsafe) private var _reconnectClientID: String?

    nonisolated(unsafe) private var sessionWelcomeTimer: Timer?
    private let sessionTimerLock = NSLock()

    // MARK: - Reconnection Credentials (Thread-Safe)

    nonisolated private func getReconnectionCredentials() -> (
        channelName: String?, token: String?, clientID: String?
    ) {
        reconnectionLock.withLock {
            (_reconnectChannelName, _reconnectToken, _reconnectClientID)
        }
    }

    nonisolated private func setReconnectionCredentials(
        channelName: String?, token: String?, clientID: String?
    ) {
        reconnectionLock.withLock {
            _reconnectChannelName = channelName
            _reconnectToken = token
            _reconnectClientID = clientID
        }
    }

    struct RateLimitState {
        var remaining: Int = 0
        var resetTime: TimeInterval = 0
        var limit: Int = 0
    }

    nonisolated(unsafe) private var rateLimits: [String: RateLimitState] = [:]
    private let rateLimitLock = NSLock()

    nonisolated(unsafe) private var requestQueue: [() -> Void] = []
    private let requestQueueLock = NSLock()

    nonisolated(unsafe) private var isProcessingQueue = false
    private let queueProcessingLock = NSLock()

    private func canMakeRequest(endpoint: String) -> Bool {
        rateLimitLock.withLock {
            guard let state = rateLimits[endpoint] else {
                return true
            }

            let now = Date().timeIntervalSince1970
            if now >= state.resetTime {
                rateLimits[endpoint] = RateLimitState()
                return true
            }

            return state.remaining > 0
        }
    }

    private func getWaitTimeIfRateLimited(endpoint: String) -> TimeInterval? {
        rateLimitLock.withLock {
            guard let state = rateLimits[endpoint] else {
                return nil
            }

            let now = Date().timeIntervalSince1970
            let timeUntilReset = state.resetTime - now

            if state.remaining <= 0 && timeUntilReset > 0 {
                return timeUntilReset
            }
            return nil
        }
    }

    private func updateRateLimitState(endpoint: String, from headers: [AnyHashable: Any]) {
        rateLimitLock.withLock {
            var state = rateLimits[endpoint] ?? RateLimitState()

            if let remaining = headers["Ratelimit-Remaining"] as? String,
                let remainingInt = Int(remaining)
            {
                state.remaining = remainingInt
            }

            if let reset = headers["Ratelimit-Reset"] as? String,
                let resetInt = TimeInterval(reset)
            {
                state.resetTime = resetInt
            }

            if let limit = headers["Ratelimit-Limit"] as? String,
                let limitInt = Int(limit)
            {
                state.limit = limitInt
            }

            rateLimits[endpoint] = state

            if state.remaining <= 5 && state.remaining > 0 {
                Log.warn(
                    "TwitchChatService: Approaching rate limit on \(endpoint): \(state.remaining)/\(state.limit) remaining",
                    category: "Twitch")
            }
        }
    }

    /// Adds a request to the queue if rate limited, returns true if queued
    private func queueRequestIfRateLimited(endpoint: String, request: @escaping () -> Void) -> Bool
    {
        guard let waitTime = getWaitTimeIfRateLimited(endpoint: endpoint) else {
            return false  // Not rate limited
        }

        Log.info(
            "TwitchChatService: Request queued due to rate limit. Retry after \(String(format: "%.1f", waitTime))s",
            category: "Twitch")

        requestQueueLock.withLock {
            requestQueue.append(request)
        }

        // Schedule queue processing after rate limit reset
        DispatchQueue.global().asyncAfter(deadline: .now() + waitTime) { [weak self] in
            self?.processRequestQueue()
        }

        return true
    }

    /// Processes queued requests after rate limit reset
    private func processRequestQueue() {
        let isProcessing = queueProcessingLock.withLock {
            guard !isProcessingQueue else { return false }
            isProcessingQueue = true
            return true
        }

        guard isProcessing else { return }

        defer {
            queueProcessingLock.withLock { isProcessingQueue = false }
        }

        while true {
            let request: (() -> Void)? = requestQueueLock.withLock {
                guard !requestQueue.isEmpty else { return nil }
                return requestQueue.removeFirst()
            }

            guard let request = request else { break }
            request()
        }
    }

    /// Starts monitoring network connectivity and sets up automatic reconnection
    nonisolated private func startNetworkMonitoring() {
        let monitor = NWPathMonitor()
        networkMonitorLock.withLock {
            networkPathMonitor = monitor
        }

        monitor.pathUpdateHandler = { [weak self] path in
            self?.handleNetworkPathChange(path)
        }

        monitor.start(queue: networkMonitorQueue)
    }

    /// Stops network connectivity monitoring
    nonisolated private func stopNetworkMonitoring() {
        networkMonitorLock.withLock {
            if let monitor = networkPathMonitor {
                monitor.cancel()
                networkPathMonitor = nil
            }
        }
    }

    /// Handles network path changes and triggers reconnection if needed.
    ///
    /// Rate-limits network-triggered reconnects to prevent infinite loops when
    /// the network path flaps rapidly between available/unavailable states.
    nonisolated private func handleNetworkPathChange(_ path: NWPath) {
        let isReachable = path.status == .satisfied
        let wasReachable = networkReachableLock.withLock { isNetworkReachable }

        networkReachableLock.withLock { isNetworkReachable = isReachable }

        if !wasReachable && isReachable {
            // Network became available after being unavailable
            let now = Date().timeIntervalSince1970
            let shouldReconnect = reconnectionLock.withLock { () -> Bool in
                // Reset cycle counter if enough time has passed
                if now - lastNetworkReconnectTime > AppConstants.Twitch.networkReconnectCooldown {
                    networkReconnectCycles = 0
                }

                guard networkReconnectCycles < maxNetworkReconnectCycles else {
                    return false
                }

                networkReconnectCycles += 1
                lastNetworkReconnectTime = now
                // Reset per-attempt counter for the new cycle
                reconnectionAttempts = 0
                return true
            }

            if shouldReconnect {
                attemptReconnect()
            } else {
                Log.error(
                    "TwitchChatService: Max network reconnect cycles reached, not reconnecting",
                    category: "Twitch")
            }
        } else if wasReachable && !isReachable {
            // Network became unavailable
            Log.warn("TwitchChatService: Network unavailable, disconnecting", category: "Twitch")
            disconnectFromEventSub()
        }
    }

    /// Attempts to reconnect to the channel with exponential backoff
    nonisolated private func attemptReconnect() {
        let (channelName, token, clientID) = getReconnectionCredentials()
        guard let channelName = channelName,
            let token = token,
            let clientID = clientID
        else {
            Log.debug("TwitchChatService: Cannot reconnect - missing credentials", category: "Twitch")
            return
        }

        let attempts = reconnectionLock.withLock { reconnectionAttempts }

        if attempts >= maxReconnectionAttempts {
            Log.error("TwitchChatService: Max reconnection attempts reached (\(maxReconnectionAttempts))", category: "Twitch")
            // Reset attempts after hitting the limit to allow manual reconnection later
            reconnectionLock.withLock {
                reconnectionAttempts = 0
            }
            return
        }

        // Exponential backoff: 1s, 2s, 4s, 8s, 16s
        let delaySeconds = min(pow(2.0, Double(attempts)), 16.0)
        
        Log.info("TwitchChatService: Scheduling reconnection attempt \(attempts + 1)/\(maxReconnectionAttempts) in \(String(format: "%.1f", delaySeconds))s", category: "Twitch")

        DispatchQueue.global().asyncAfter(deadline: .now() + delaySeconds) { [weak self] in
            guard let self = self else { return }

            Task {
                do {
                    try await self.connectToChannel(
                        channelName: channelName, token: token, clientID: clientID)

                    // Reset attempts on successful connection
                    self.reconnectionLock.withLock {
                        self.reconnectionAttempts = 0
                    }
                    Log.info("TwitchChatService: Reconnection successful", category: "Twitch")
                } catch {
                    self.reconnectionLock.withLock {
                        self.reconnectionAttempts += 1
                    }
                    
                    Log.warn("TwitchChatService: Reconnection attempt failed: \(error.localizedDescription)", category: "Twitch")

                    // If still under max attempts and network is reachable, schedule next attempt
                    let updatedAttempts = self.reconnectionLock.withLock {
                        self.reconnectionAttempts
                    }
                    let isReachable = self.networkReachableLock.withLock { self.isNetworkReachable }
                    if updatedAttempts < self.maxReconnectionAttempts && isReachable {
                        self.attemptReconnect()
                    } else if !isReachable {
                        Log.info("TwitchChatService: Network no longer reachable, stopping reconnection attempts", category: "Twitch")
                    }
                }
            }
        }
    }

    // MARK: - Lifecycle

    deinit {
        cancelSessionWelcomeTimeout()
        stopNetworkMonitoring()
        disconnectFromEventSub()
    }

    // MARK: - Public Methods

    /// Joins a Twitch channel using pre-resolved IDs.
    ///
    /// - Parameters:
    ///   - broadcasterID: The broadcaster's Twitch user ID
    ///   - botID: The bot's Twitch user ID
    ///   - token: OAuth access token with chat scopes
    ///   - clientID: Twitch application client ID
    /// - Throws: `ConnectionError` if credentials are invalid or missing
    func joinChannel(
        broadcasterID: String,
        botID: String,
        token: String,
        clientID: String
    ) throws {
        guard !broadcasterID.isEmpty, !botID.isEmpty, !token.isEmpty else {
            Log.error("TwitchChatService: Invalid credentials for channel join", category: "Twitch")
            throw ConnectionError.invalidCredentials
        }

        guard !clientID.isEmpty else {
            Log.error("TwitchChatService: Missing client ID for channel join", category: "Twitch")
            throw ConnectionError.missingClientID
        }

        self.broadcasterID = broadcasterID
        self.botID = botID
        self.oauthToken = token
        self.clientID = clientID
        self.botUsername = nil
        connectionLock.withLock { self.hasSentConnectionMessage = false }

        // Reset the disconnect flag so messages can be processed
        disconnectLock.withLock { isProcessingDisconnect = false }

        commandDispatcher.setCurrentSongInfo { [weak self] in
            self?.getCurrentSongInfo?() ?? "No track currently playing"
        }

        commandDispatcher.setLastSongInfo { [weak self] in
            self?.getLastSongInfo?() ?? "No previous track available"
        }

        commandDispatcher.setCurrentSongCommandEnabled { [weak self] in
            self?.currentSongCommandEnabled ?? false
        }

        commandDispatcher.setLastSongCommandEnabled { [weak self] in
            self?.lastSongCommandEnabled ?? false
        }

        // Don't set connected state here - wait for EventSub session_welcome
        // The connection state will be updated in handleSessionWelcome() when the session is actually established
        connectToEventSub()
    }

    /// Connects to a Twitch channel by name, resolving usernames to IDs.
    ///
    /// This is the main entry point for connecting to chat. It:
    /// 1. Resolves bot identity if not already cached
    /// 2. Resolves broadcaster username to user ID
    /// 3. Calls `joinChannel` with resolved IDs
    ///
    /// - Parameters:
    ///   - channelName: The broadcaster's Twitch username
    ///   - token: OAuth access token with chat scopes
    ///   - clientID: Twitch application client ID
    /// - Throws: `ConnectionError` if resolution or connection fails
    func connectToChannel(channelName: String, token: String, clientID: String) async throws {
        guard !channelName.isEmpty, !token.isEmpty else {
            Log.error("TwitchChatService: Invalid channel name or token", category: "Twitch")
            throw ConnectionError.invalidCredentials
        }

        guard !clientID.isEmpty else {
            Log.error("TwitchChatService: Missing client ID for channel connect", category: "Twitch")
            throw ConnectionError.missingClientID
        }

        var botUserID = KeychainService.loadTwitchBotUserID()
        var resolvedUsername = KeychainService.loadTwitchUsername() ?? ""

        if botUserID?.isEmpty ?? true {
            let identity = try await fetchBotIdentity(token: token, clientID: clientID)
            botUserID = identity.userID
            resolvedUsername = identity.displayName.isEmpty ? identity.login : identity.displayName
            try KeychainService.saveTwitchUsername(resolvedUsername)
            try KeychainService.saveTwitchBotUserID(identity.userID)
        }

        guard let botUserID = botUserID else {
            throw ConnectionError.invalidCredentials
        }

        let broadcasterUserID = try await resolveUsername(
            channelName,
            token: token,
            clientID: clientID
        )

        guard !broadcasterUserID.isEmpty else {
            throw ConnectionError.networkError("Could not resolve channel name to user ID")
        }

        try joinChannel(
            broadcasterID: broadcasterUserID,
            botID: botUserID,
            token: token,
            clientID: clientID
        )

        // Store credentials for automatic reconnection (protected by reconnectionLock)
        setReconnectionCredentials(channelName: channelName, token: token, clientID: clientID)
        reconnectionLock.withLock {
            reconnectionAttempts = 0
            networkReconnectCycles = 0
        }

        // Start network monitoring for automatic reconnection
        let needsMonitoring = networkMonitorLock.withLock { networkPathMonitor == nil }
        if needsMonitoring {
            startNetworkMonitoring()
        }

        Log.info("TwitchChatService: Connected to channel \(channelName)", category: "Twitch")
    }

    /// Resolves and stores the bot's identity (user ID and username).
    ///
    /// - Parameters:
    ///   - token: OAuth access token
    ///   - clientID: Twitch application client ID
    /// - Throws: `ConnectionError` if identity resolution fails
    func resolveBotIdentity(token: String, clientID: String) async throws {
        guard !token.isEmpty else {
            throw ConnectionError.invalidCredentials
        }

        guard !clientID.isEmpty else {
            throw ConnectionError.missingClientID
        }

        let identity = try await fetchBotIdentity(token: token, clientID: clientID)
        let resolvedUsername = identity.displayName.isEmpty ? identity.login : identity.displayName

        try KeychainService.saveTwitchUsername(resolvedUsername)
        try KeychainService.saveTwitchBotUserID(identity.userID)
    }

    /// Static method to resolve bot identity without an instance.
    ///
    /// Useful for resolving identity before creating a service instance.
    ///
    /// - Parameters:
    ///   - token: OAuth access token
    ///   - clientID: Twitch application client ID
    /// - Throws: `ConnectionError` if identity resolution fails
    static func resolveBotIdentityStatic(token: String, clientID: String) async throws {
        guard !token.isEmpty else {
            throw ConnectionError.invalidCredentials
        }

        guard !clientID.isEmpty else {
            throw ConnectionError.missingClientID
        }

        let service = TwitchChatService()
        let identity = try await service.fetchBotIdentity(token: token, clientID: clientID)
        let resolvedUsername = identity.displayName.isEmpty ? identity.login : identity.displayName

        try KeychainService.saveTwitchUsername(resolvedUsername)
        try KeychainService.saveTwitchBotUserID(identity.userID)
    }

    /// Resolves the Twitch Client ID from Info.plist (set via Config.xcconfig at build time).
    ///
    /// Checks in order:
    /// 1. `TWITCH_CLIENT_ID` key in Info.plist (expanded from Config.xcconfig at build time)
    /// 2. `TWITCH_CLIENT_ID` environment variable (for dev/CI overrides)
    ///
    /// - Returns: The client ID if found, otherwise nil
    static func resolveClientID() -> String? {
        // Primary: Info.plist value (expanded from Config.xcconfig at build time)
        if let plistValue = Bundle.main.object(forInfoDictionaryKey: "TWITCH_CLIENT_ID") as? String,
            !plistValue.isEmpty,
            !plistValue.hasPrefix("$(") // Skip if xcconfig variable wasn't expanded
        {
            return plistValue
        }

        // Fallback: environment variable (for dev/CI overrides without rebuilding)
        if let env = ProcessInfo.processInfo.environment["TWITCH_CLIENT_ID"], !env.isEmpty {
            return env
        }

        return nil
    }

    /// Fetches the bot's identity (user ID and usernames) from Twitch.
    ///
    /// Uses the `/users` endpoint to retrieve information about the authenticated user.
    ///
    /// - Parameters:
    ///   - token: OAuth access token
    ///   - clientID: Twitch application client ID
    /// - Returns: The bot's identity information
    /// - Throws: `ConnectionError` if the API request fails or returns 401 Unauthorized
    func fetchBotIdentity(token: String, clientID: String) async throws -> BotIdentity {
        guard let url = URL(string: apiBaseURL + "/users") else {
            Log.error("TwitchChatService: Failed to construct users endpoint URL", category: "Twitch")
            throw ConnectionError.networkError("Invalid users endpoint")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue(clientID, forHTTPHeaderField: "Client-ID")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let http = response as? HTTPURLResponse else {
            throw ConnectionError.networkError("No HTTP response")
        }

        guard (200..<300).contains(http.statusCode) else {
            if http.statusCode == 401 {
                Log.error(
                    "TwitchChatService: Authentication failed (401) - invalid or expired OAuth token",
                    category: "Twitch")
                throw ConnectionError.authenticationFailed
            }
            Log.error(
                "TwitchChatService: Users endpoint error HTTP \(http.statusCode)", category: "Twitch")
            throw ConnectionError.networkError("Users endpoint returned \(http.statusCode)")
        }

        let json: [String: Any]
        do {
            guard let parsed = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                Log.error("TwitchChatService: User identity response is not a JSON object", category: "Twitch")
                throw ConnectionError.networkError("Unable to decode user identity JSON")
            }
            json = parsed
        } catch {
            // Catch JSON parsing errors directly
            if let connectionError = error as? ConnectionError {
                throw connectionError
            }
            Log.error("TwitchChatService: Failed to decode user identity JSON - \(error.localizedDescription)", category: "Twitch")
            throw ConnectionError.networkError("Unable to decode user identity JSON: \(error.localizedDescription)")
        }

        guard let dataArray = json["data"] as? [[String: Any]],
            let first = dataArray.first,
            let userID = first["id"] as? String,
            let login = first["login"] as? String
        else {
            Log.error("TwitchChatService: Failed to parse user identity from response", category: "Twitch")
            throw ConnectionError.networkError("Unable to parse user identity")
        }

        let displayName = first["display_name"] as? String ?? login

        botID = userID
        botUsername = displayName

        return BotIdentity(userID: userID, login: login, displayName: displayName)
    }

    /// Leaves the current channel and disconnects from EventSub.
    ///
    /// Clears all stored credentials and session state.
    func leaveChannel() {
        Log.info("TwitchChatService:leaveChannel() called", category: "Twitch")
        // Mark that we're disconnecting to prevent stale message processing
        disconnectLock.withLock { isProcessingDisconnect = true }

        disconnectFromEventSub()
        
        // Clear reconnection credentials (protected by reconnectionLock)
        setReconnectionCredentials(channelName: nil, token: nil, clientID: nil)
        reconnectionLock.withLock { reconnectionAttempts = 0 }

        broadcasterID = nil
        botID = nil
        oauthToken = nil
        clientID = nil

        // Clear connection state callback; onMessageReceived, getCurrentSongInfo,
        // and getLastSongInfo are set by AppDelegate and persist across reconnections.
        onConnectionStateChanged = nil

        // Update internal state and notify listeners that we've left
        self.setConnected(false)
        NotificationCenter.default.post(
            name: TwitchChatService.connectionStateChanged,
            object: nil,
            userInfo: ["isConnected": false]
        )
        DispatchQueue.main.async {
            self.connectionLock.withLock {
                self.hasSentConnectionMessage = false
            }
        }

        Log.info("TwitchChatService: Left channel", category: "Twitch")
    }

    /// Validates an OAuth token with Twitch and verifies required scopes.
    ///
    /// Calls the `/oauth2/validate` endpoint to check token validity and scope permissions.
    ///
    /// - Parameters:
    ///   - token: The OAuth access token (raw string, not prefixed)
    ///   - requiredScopes: Scopes that must be present (default: chat read/write scopes)
    /// - Returns: True if the token is valid and has all required scopes
    func validateToken(
        _ token: String, requiredScopes: [String] = ["user:read:chat", "user:write:chat"]
    ) async -> Bool {
        guard let url = URL(string: "https://id.twitch.tv/oauth2/validate") else {
            Log.error("TwitchChatService: Invalid validate URL", category: "Twitch")
            return false
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        // Per Twitch docs, use "OAuth <token>" for the validate endpoint
        request.setValue("OAuth \(token)", forHTTPHeaderField: "Authorization")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else { return false }

            guard (200..<300).contains(http.statusCode) else {
                if http.statusCode == 401 {
                    Log.warn(
                        "TwitchChatService: Stored OAuth token is invalid or expired", category: "Twitch")
                } else {
                    Log.warn(
                        "TwitchChatService: Token validate HTTP \(http.statusCode)", category: "Twitch")
                }
                return false
            }

            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                Log.warn("TwitchChatService: Could not parse token validate response", category: "Twitch")
                return false
            }

            // optional: check scopes
            if let scopes = json["scopes"] as? [String] {
                let missing = requiredScopes.filter { !scopes.contains($0) }
                if !missing.isEmpty {
                    Log.warn(
                        "TwitchChatService: Token missing required scopes: \(missing.joined(separator: ", "))",
                        category: "Twitch")
                    return false
                }
            }

            return true
        } catch {
            Log.error(
                "TwitchChatService: Token validate request failed - \(error.localizedDescription)",
                category: "Twitch")
            return false
        }
    }

    /// Sends the connection confirmation message to the channel.
    ///
    /// Called automatically when the bot successfully subscribes to channel chat messages.
    /// Sends: "WolfWave Application is connected! 🎵"
    func sendConnectionMessage() {
        DispatchQueue.main.asyncAfter(deadline: .now() + AppConstants.Twitch.connectionMessageDelay) { [weak self] in
            guard let self = self else { return }
            let hasSent = self.connectionLock.withLock { self.hasSentConnectionMessage }
            if hasSent {
                return
            }
            self.connectionLock.withLock { self.hasSentConnectionMessage = true }
            self.sendMessage(AppConstants.Twitch.connectionMessage)
        }
    }

    // MARK: - Message Sending

    /// Maximum number of retry attempts for a failed message send.
    private let maxMessageRetries = AppConstants.Twitch.maxMessageRetries

    /// Pending message awaiting retry.
    private struct PendingMessage {
        let message: String
        let parentMessageID: String?
        var attempts: Int
    }

    /// Queue of messages pending retry.
    nonisolated(unsafe) private var pendingMessages: [PendingMessage] = []
    private let pendingMessagesLock = NSLock()

    /// Sends a message to the current channel.
    ///
    /// Messages are sent via the Helix `/chat/messages` endpoint. Failed sends
    /// are retried up to `maxMessageRetries` times with exponential backoff.
    ///
    /// - Parameter message: The message text to send
    func sendMessage(_ message: String) {
        sendMessage(message, replyTo: nil)
    }

    /// Sends a message that replies to another message.
    ///
    /// Thread Safety: This method is thread-safe. Concurrent calls are safe.
    ///
    /// Message Validation:
    /// - Empty messages (whitespace only) are silently ignored
    /// - Messages over 500 characters are truncated to 497 + "..."
    ///
    /// Retry Behavior:
    /// - Failed sends are retried up to 3 times with exponential backoff (1s, 2s, 4s)
    /// - Messages are dropped after max retries are exhausted
    ///
    /// - Parameters:
    ///   - message: The message text to send (truncated to 500 chars if needed)
    ///   - parentMessageID: The ID of the message to reply to, or nil for a regular message
    func sendMessage(_ message: String, replyTo parentMessageID: String?) {
        guard let broadcasterID = broadcasterID,
            let botID = botID,
            let token = oauthToken,
            let clientID = clientID
        else {
            Log.warn("TwitchChatService: Not connected, queuing message for retry", category: "Twitch")
            queueMessageForRetry(message: message, parentMessageID: parentMessageID, attempts: 0)
            return
        }

        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return
        }

        let finalMessage = trimmed.truncatedForChat()

        var body: [String: Any] = [
            "broadcaster_id": broadcasterID,
            "sender_id": botID,
            "message": finalMessage,
        ]

        if let parentMessageID = parentMessageID, !parentMessageID.isEmpty {
            body["reply_parent_message_id"] = parentMessageID
        }

        sendAPIRequest(
            method: "POST",
            endpoint: "/chat/messages",
            body: body,
            token: token,
            clientID: clientID
        ) { [weak self] result in
            switch result {
            case .success(let data):
                do {
                    guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                        let dataArray = json["data"] as? [[String: Any]],
                        let messageData = dataArray.first
                    else {
                        Log.warn("TwitchChatService: Could not parse send-message response", category: "Twitch")
                        return
                    }
                    let isSent = messageData["is_sent"] as? Bool ?? false
                    if isSent {
                        // Message sent successfully
                    } else {
                        Log.warn("TwitchChatService: Message dropped by Twitch", category: "Twitch")
                    }
                } catch {
                    Log.warn("TwitchChatService: Failed to decode send-message response - \(error.localizedDescription)", category: "Twitch")
                }
            case .failure(let error):
                Log.error(
                    "TwitchChatService: Failed to send message - \(error.localizedDescription)",
                    category: "Twitch")
                self?.queueMessageForRetry(
                    message: message, parentMessageID: parentMessageID, attempts: 0)
            }
        }
    }

    /// Queues a message for retry with exponential backoff.
    private func queueMessageForRetry(message: String, parentMessageID: String?, attempts: Int) {
        guard attempts < maxMessageRetries else {
            Log.error(
                "TwitchChatService: Message dropped after \(maxMessageRetries) retry attempts",
                category: "Twitch")
            return
        }

        let pending = PendingMessage(
            message: message, parentMessageID: parentMessageID, attempts: attempts + 1)
        pendingMessagesLock.withLock { pendingMessages.append(pending) }

        let delay = pow(2.0, Double(attempts))
        Log.debug(
            "TwitchChatService: Scheduling message retry \(attempts + 1)/\(maxMessageRetries) in \(delay)s",
            category: "Twitch")

        DispatchQueue.global().asyncAfter(deadline: .now() + delay) { [weak self] in
            self?.retryPendingMessages()
        }
    }

    /// Retries pending messages from the queue.
    private func retryPendingMessages() {
        let message: PendingMessage? = pendingMessagesLock.withLock {
            guard !pendingMessages.isEmpty else { return nil }
            return pendingMessages.removeFirst()
        }

        guard let message else { return }

        // Check if we have valid credentials now
        guard broadcasterID != nil, botID != nil, oauthToken != nil, clientID != nil else {
            // Still not connected, re-queue with incremented attempts
            queueMessageForRetry(
                message: message.message,
                parentMessageID: message.parentMessageID,
                attempts: message.attempts)
            return
        }

        sendMessage(message.message, replyTo: message.parentMessageID)
    }

    // MARK: - Message Parsing

    /// Parses and handles an incoming message from EventSub.
    ///
    /// Thread Safety: Called from WebSocket receive loop (background thread).
    /// All mutations are protected. Safe to call concurrently.
    ///
    /// Processing Pipeline:
    /// 1. Validates presence of required EventSub fields
    /// 2. Sanitizes all string inputs (trim whitespace, validate non-empty)
    /// 3. Parses badges and reply context if present
    /// 4. Routes to BotCommandDispatcher if enabled
    /// 5. Fires onMessageReceived callback (background thread)
    ///
    /// Input Validation:
    /// - All strings are trimmed and validated for non-empty content
    /// - Missing required fields (messageID, username, userID, text) cause silent skip with debug log
    /// - Malformed badge/reply objects are silently skipped; message still processed
    ///
    /// Error Handling:
    /// - Invalid EventSub format is logged as debug and skipped
    /// - Command dispatcher errors are caught and logged, don't affect normal flow
    ///
    /// Callback Timing:
    /// - Callbacks fire on WebSocket background thread; callers must dispatch if needed for UI
    ///
    /// - Parameter json: The EventSub payload JSON dictionary
    func handleEventSubMessage(_ json: [String: Any]) {
        // Silently ignore messages if we're disconnecting or already disconnected
        let isDisconnecting = disconnectLock.withLock { isProcessingDisconnect }
        guard !isDisconnecting else {
            return
        }

        guard let event = json["event"] as? [String: Any] else {
            return
        }

        let messageID = (event["message_id"] as? String ?? "").trimmingCharacters(
            in: .whitespacesAndNewlines)
        let username = (event["chatter_user_name"] as? String ?? "").trimmingCharacters(
            in: .whitespacesAndNewlines)
        let userID = (event["chatter_user_id"] as? String ?? "").trimmingCharacters(
            in: .whitespacesAndNewlines)
        let broadcasterID = event["broadcaster_user_id"] as? String ?? ""
        let messageText = event["message"] as? [String: Any]
        let text = (messageText?["text"] as? String ?? "").trimmingCharacters(
            in: .whitespacesAndNewlines)

        guard !messageID.isEmpty, !username.isEmpty, !userID.isEmpty, !text.isEmpty else {
            return
        }

        var badges: [ChatMessage.Badge] = []
        if let badgeArray = event["badges"] as? [[String: Any]] {
            for badge in badgeArray {
                if let setID = badge["set_id"] as? String,
                    let id = badge["id"] as? String,
                    !setID.isEmpty, !id.isEmpty
                {
                    let info = (badge["info"] as? String ?? "").trimmingCharacters(
                        in: .whitespacesAndNewlines)
                    badges.append(ChatMessage.Badge(setID: setID, id: id, info: info))
                }
            }
        }

        var reply: ChatMessage.Reply?
        if let replyObj = event["reply"] as? [String: Any] {
            let parentMessageID = (replyObj["parent_message_id"] as? String ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let parentBody = (replyObj["parent_message_body"] as? String ?? "").trimmingCharacters(
                in: .whitespacesAndNewlines)
            let parentUserID = (replyObj["parent_user_id"] as? String ?? "").trimmingCharacters(
                in: .whitespacesAndNewlines)
            let parentUsername = (replyObj["parent_user_name"] as? String ?? "").trimmingCharacters(
                in: .whitespacesAndNewlines)

            if !parentMessageID.isEmpty && !parentUserID.isEmpty {
                reply = ChatMessage.Reply(
                    parentMessageID: parentMessageID,
                    parentMessageBody: parentBody,
                    parentUserID: parentUserID,
                    parentUsername: parentUsername
                )
            }
        }

        let chatMessage = ChatMessage(
            messageID: messageID,
            username: username,
            userID: userID,
            message: text,
            channel: broadcasterID,
            badges: badges,
            reply: reply
        )

        if commandsEnabled {
            let isModerator = badges.contains { $0.setID == "moderator" }
            let isBroadcaster = badges.contains { $0.setID == "broadcaster" }
            let bypassCooldown = isModerator || isBroadcaster
            if let response = commandDispatcher.processMessage(
                text, userID: userID, isModerator: bypassCooldown
            ) {
                sendMessage(response, replyTo: messageID)
            }
        }

        onMessageReceived?(chatMessage)
    }

    // MARK: - API Requests

    /// Sends an API request to the Twitch Helix API.
    ///
    /// Notes:
    /// - This helper performs a standard HTTP request using `URLSession`.
    /// - The completion handler is executed on the URLSession callback
    ///   queue (background thread). UI updates should be dispatched to the
    ///   main queue by callers.
    /// - HTTP errors and parsing failures are returned via the `Result`.
    ///
    /// - Parameters:
    ///   - method: The HTTP method (GET, POST, etc.)
    ///   - endpoint: The API endpoint path (e.g., "/chat/messages")
    ///   - body: Optional JSON body dictionary
    ///   - token: OAuth access token
    ///   - clientID: Twitch application client ID
    ///   - completion: Callback with the result (Data or Error)
    private func sendAPIRequest(
        method: String,
        endpoint: String,
        body: [String: Any]?,
        token: String,
        clientID: String,
        completion: @escaping (Result<Data, Error>) -> Void
    ) {
        // Check if rate limited; queue if necessary
        if queueRequestIfRateLimited(
            endpoint: endpoint,
            request: { [weak self] () in
                self?.sendAPIRequest(
                    method: method,
                    endpoint: endpoint,
                    body: body,
                    token: token,
                    clientID: clientID,
                    completion: completion
                )
            })
        {
            return  // Request was queued
        }

        guard let url = URL(string: apiBaseURL + endpoint) else {
            completion(.failure(ConnectionError.networkError("Invalid URL")))
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue(clientID, forHTTPHeaderField: "Client-ID")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        if let body = body {
            do {
                request.httpBody = try JSONSerialization.data(withJSONObject: body)
            } catch {
                Log.error("TwitchChatService: Failed to serialize request body - \(error.localizedDescription)", category: "Twitch")
                completion(.failure(ConnectionError.networkError("Failed to serialize request body")))
                return
            }
        }

        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            if let error = error {
                completion(.failure(error))
                return
            }

            // Update rate limit state from response headers
            if let httpResponse = response as? HTTPURLResponse {
                self?.updateRateLimitState(endpoint: endpoint, from: httpResponse.allHeaderFields)
            }

            guard let data = data else {
                completion(.failure(ConnectionError.networkError("No response data")))
                return
            }

            // Log non-2xx responses instead of silently passing them as success
            if let httpResponse = response as? HTTPURLResponse,
               !(200..<300).contains(httpResponse.statusCode) {
                let responseText = String(data: data, encoding: .utf8) ?? "No response body"
                Log.warn("TwitchChatService: API \(endpoint) returned HTTP \(httpResponse.statusCode) - \(responseText)", category: "Twitch")
            }

            completion(.success(data))
        }.resume()
    }

    /// Async wrapper for `sendAPIRequest` using structured concurrency.
    private func sendAPIRequest(
        method: String,
        endpoint: String,
        body: [String: Any]?,
        token: String,
        clientID: String
    ) async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            sendAPIRequest(
                method: method,
                endpoint: endpoint,
                body: body,
                token: token,
                clientID: clientID
            ) { result in
                continuation.resume(with: result)
            }
        }
    }

    // MARK: - WebSocket Management

    /// Connects to the Twitch EventSub WebSocket endpoint.
    private func connectToEventSub() {
        guard let url = URL(string: "wss://eventsub.wss.twitch.tv/ws") else {
            Log.error("TwitchChatService: Invalid EventSub URL", category: "Twitch")
            setConnected(false)
            onConnectionStateChanged?(false)
            NotificationCenter.default.post(
                name: TwitchChatService.connectionStateChanged,
                object: nil,
                userInfo: ["isConnected": false]
            )
            return
        }

        let task = urlSession.webSocketTask(with: url)
        webSocketLock.lock()
        webSocketTask = task
        webSocketLock.unlock()

        Log.info("TwitchChatService: Starting EventSub WebSocket connection", category: "Twitch")
        task.resume()

        // Start a timer to detect if session_welcome doesn't arrive in time
        startSessionWelcomeTimeout()

        receiveWebSocketMessage()
    }

    /// Starts a timeout timer for receiving the session_welcome message.
    private func startSessionWelcomeTimeout() {
        cancelSessionWelcomeTimeout()
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            let timer = Timer.scheduledTimer(
                withTimeInterval: AppConstants.Twitch.sessionWelcomeTimeout,
                repeats: false
            ) { [weak self] _ in
                self?.handleSessionWelcomeTimeout()
            }
            self.sessionTimerLock.withLock {
                self.sessionWelcomeTimer = timer
            }
        }
    }

    /// Called when session_welcome timeout expires.
    private func handleSessionWelcomeTimeout() {
        let hasSession = webSocketLock.withLock { sessionID != nil }
        guard !hasSession else { return }  // If we already got a welcome, ignore

        Log.error(
            "TwitchChatService: Session welcome timeout - WebSocket may not be responding",
            category: "Twitch")
        setConnected(false)
        onConnectionStateChanged?(false)
        NotificationCenter.default.post(
            name: TwitchChatService.connectionStateChanged,
            object: nil,
            userInfo: ["isConnected": false]
        )

        // Close the stale connection and attempt reconnect
        disconnectFromEventSub()

        let (channelName, token, clientID) = getReconnectionCredentials()
        let isReachable = networkReachableLock.withLock { isNetworkReachable }

        if let channelName = channelName, let token = token, let clientID = clientID,
            !channelName.isEmpty && !token.isEmpty && !clientID.isEmpty && isReachable
        {
            Log.info(
                "TwitchChatService: Attempting reconnection after session welcome timeout",
                category: "Twitch")
            attemptReconnect()
        }
    }

    /// Cancels the session welcome timeout timer.
    private func cancelSessionWelcomeTimeout() {
        sessionTimerLock.withLock {
            sessionWelcomeTimer?.invalidate()
            sessionWelcomeTimer = nil
        }
    }

    /// Disconnects from the EventSub WebSocket and clears session state.
    nonisolated private func disconnectFromEventSub() {
        // Mark disconnected first so UI consumers see the updated state
        self.setConnected(false)
        webSocketLock.lock()
        let task = webSocketTask
        webSocketTask = nil
        sessionID = nil
        webSocketLock.unlock()
        task?.cancel(with: .goingAway, reason: nil)

        // Cancel the session welcome timer
        sessionTimerLock.withLock {
            sessionWelcomeTimer?.invalidate()
            sessionWelcomeTimer = nil
        }

        Log.debug("TwitchChatService: EventSub WebSocket disconnected", category: "Twitch")
    }

    private func receiveWebSocketMessage() {
        let task: URLSessionWebSocketTask? = webSocketLock.withLock { webSocketTask }
        guard let task else {
            Log.debug(
                "TwitchChatService: WebSocket task is nil, stopping receive loop", category: "Twitch")
            return
        }

        task.receive { [weak self] result in
            guard let self = self else { return }

            switch result {
            case .success(let message):
                switch message {
                case .string(let text):
                    self.handleWebSocketMessage(text)
                case .data(let data):
                    if let text = String(data: data, encoding: .utf8) {
                        self.handleWebSocketMessage(text)
                    }
                @unknown default:
                    break
                }

                self.receiveWebSocketMessage()

            case .failure(let error):
                // Suppress errors caused by intentional disconnect (e.g., leaveChannel())
                let isDisconnecting = self.disconnectLock.withLock { self.isProcessingDisconnect }
                guard !isDisconnecting else {
                    return
                }

                let nsError = error as NSError
                let errorCode = nsError.code
                let errorDomain = nsError.domain

                // Provide specific logging for timeout errors
                if errorDomain == NSURLErrorDomain && errorCode == NSURLErrorTimedOut {
                    Log.error(
                        "TwitchChatService: WebSocket connection timed out. This may be due to network issues, firewall blocking, or Twitch service problems.",
                        category: "Twitch")
                } else {
                    Log.error(
                        "TwitchChatService: WebSocket connection error: \(error.localizedDescription) (Domain: \(errorDomain), Code: \(errorCode))",
                        category: "Twitch")
                }

                self.setConnected(false)
                self.onConnectionStateChanged?(false)
                NotificationCenter.default.post(
                    name: TwitchChatService.connectionStateChanged,
                    object: nil,
                    userInfo: ["isConnected": false, "error": error.localizedDescription]
                )

                // Attempt automatic reconnection if network is available and credentials exist
                let (channelName, token, clientID) = self.getReconnectionCredentials()
                let isReachable = self.networkReachableLock.withLock { self.isNetworkReachable }

                if let channelName = channelName, let token = token, let clientID = clientID,
                    !channelName.isEmpty && !token.isEmpty && !clientID.isEmpty && isReachable
                {
                    Log.info("TwitchChatService: Attempting automatic reconnection", category: "Twitch")
                    self.attemptReconnect()
                }
            }
        }
    }

    /// Handles a received WebSocket message.
    private func handleWebSocketMessage(_ text: String) {
        guard let data = text.data(using: .utf8) else {
            Log.warn("TwitchChatService: WebSocket message is not valid UTF-8", category: "Twitch")
            return
        }

        let json: [String: Any]
        do {
            guard let parsed = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                Log.warn("TwitchChatService: WebSocket message is not a JSON object", category: "Twitch")
                return
            }
            json = parsed
        } catch {
            Log.warn("TwitchChatService: Failed to parse WebSocket message JSON - \(error.localizedDescription)", category: "Twitch")
            return
        }

        guard let metadata = json["metadata"] as? [String: Any],
            let messageType = metadata["message_type"] as? String,
            let messageID = metadata["message_id"] as? String,
            !messageID.isEmpty,
            let messageTimestamp = metadata["message_timestamp"] as? String,
            !messageTimestamp.isEmpty
        else {
            Log.warn("TwitchChatService: EventSub message missing required metadata fields", category: "Twitch")
            return
        }

        // Reject messages older than 10 minutes to prevent replay attacks
        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        var timestamp = isoFormatter.date(from: messageTimestamp)
        if timestamp == nil {
            // Fallback: try without fractional seconds
            let fallbackFormatter = ISO8601DateFormatter()
            timestamp = fallbackFormatter.date(from: messageTimestamp)
            if timestamp == nil {
                Log.warn("TwitchChatService: Failed to parse EventSub timestamp: \(messageTimestamp)", category: "Twitch")
            }
        }
        if let timestamp {
            let age = Date().timeIntervalSince(timestamp)
            if age > 600 {
                Log.warn("TwitchChatService: Rejecting stale EventSub message (age: \(Int(age))s)", category: "Twitch")
                return
            }
        }

        switch messageType {
        case "session_welcome":
            handleSessionWelcome(json)
        case "notification":
            handleNotification(json)
        case "session_keepalive":
            break
        default:
            break
        }
    }

    /// Handles the session_welcome message from EventSub.
    private func handleSessionWelcome(_ json: [String: Any]) {
        guard let payload = json["payload"] as? [String: Any],
            let session = payload["session"] as? [String: Any],
            let sessionID = session["id"] as? String
        else {
            Log.error("TwitchChatService: Failed to parse session ID", category: "Twitch")
            return
        }

        // Cancel the welcome timeout since we got the welcome message
        cancelSessionWelcomeTimeout()

        webSocketLock.lock()
        self.sessionID = sessionID
        webSocketLock.unlock()
        Log.info(
            "TwitchChatService: EventSub session established with ID: \(sessionID)", category: "Twitch")

        // Ensure connected state is set properly
        setConnected(true)
        onConnectionStateChanged?(true)

        NotificationCenter.default.post(
            name: TwitchChatService.connectionStateChanged,
            object: nil,
            userInfo: ["isConnected": true]
        )

        subscribeToChannelChatMessage()
    }

    /// Handles notification messages containing EventSub events.
    ///
    /// - Parameter json: The notification message JSON
    private func handleNotification(_ json: [String: Any]) {
        guard let payload = json["payload"] as? [String: Any] else { return }

        // Validate subscription type before processing
        if let subscription = payload["subscription"] as? [String: Any],
            let subType = subscription["type"] as? String
        {
            guard subType == "channel.chat.message" else {
                Log.info("TwitchChatService: Ignoring unexpected EventSub type: \(subType)", category: "Twitch")
                return
            }
        } else {
            Log.warn("TwitchChatService: EventSub notification missing subscription type", category: "Twitch")
            return
        }

        handleEventSubMessage(payload)
    }

    // MARK: - EventSub Subscriptions

    /// Subscribes to the channel.chat.message EventSub event.
    private func subscribeToChannelChatMessage() {
        let currentSessionID: String? = webSocketLock.withLock { sessionID }
        guard let sessionID = currentSessionID,
            let broadcasterID = broadcasterID,
            let botID = botID,
            let token = oauthToken,
            let clientID = clientID
        else {
            Log.error(
                "TwitchChatService: Missing credentials for EventSub subscription", category: "Twitch")
            setConnected(false)
            onConnectionStateChanged?(false)
            NotificationCenter.default.post(
                name: TwitchChatService.connectionStateChanged,
                object: nil,
                userInfo: ["isConnected": false]
            )
            return
        }

        let subscriptionBody: [String: Any] = [
            "type": "channel.chat.message",
            "version": "1",
            "condition": [
                "broadcaster_user_id": broadcasterID,
                "user_id": botID,
            ],
            "transport": [
                "method": "websocket",
                "session_id": sessionID,
            ],
        ]

        guard let url = URL(string: apiBaseURL + "/eventsub/subscriptions") else {
            Log.error("TwitchChatService: Invalid EventSub subscriptions URL", category: "Twitch")
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue(clientID, forHTTPHeaderField: "Client-ID")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: subscriptionBody)
        } catch {
            Log.error("TwitchChatService: Failed to serialize EventSub subscription body - \(error.localizedDescription)", category: "Twitch")
            return
        }

        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            if let error = error {
                Log.error(
                    "TwitchChatService: EventSub subscription error - \(error.localizedDescription)",
                    category: "Twitch")
                self?.setConnected(false)
                self?.onConnectionStateChanged?(false)
                NotificationCenter.default.post(
                    name: TwitchChatService.connectionStateChanged,
                    object: nil,
                    userInfo: ["isConnected": false]
                )
                return
            }

            if let http = response as? HTTPURLResponse {
                if (200..<300).contains(http.statusCode) {
                    Log.info("TwitchChatService: Connected to chat", category: "Twitch")
                    if self?.shouldSendConnectionMessageOnSubscribe == true {
                        self?.sendConnectionMessage()
                    }
                } else {
                    let responseText =
                        data.flatMap { String(data: $0, encoding: .utf8) } ?? "No response"
                    Log.error(
                        "TwitchChatService: EventSub subscription failed - HTTP \(http.statusCode) - \(responseText)",
                        category: "Twitch")
                    self?.setConnected(false)
                    self?.onConnectionStateChanged?(false)
                    NotificationCenter.default.post(
                        name: TwitchChatService.connectionStateChanged,
                        object: nil,
                        userInfo: ["isConnected": false]
                    )
                }
            }
        }.resume()
    }

    // MARK: - Username Resolution

    /// Result of checking whether a Twitch channel exists.
    enum ChannelValidationResult {
        case exists
        case notFound
        case authenticationFailed
        case error(String)
    }

    /// Validates whether a Twitch channel name exists by resolving it to a user ID.
    ///
    /// Wraps `resolveUsername()` and translates thrown errors into a `ChannelValidationResult`.
    ///
    /// - Parameters:
    ///   - channelName: The Twitch channel name to validate
    ///   - token: OAuth access token
    ///   - clientID: Twitch application client ID
    /// - Returns: A `ChannelValidationResult` indicating whether the channel exists
    func validateChannelExists(_ channelName: String, token: String, clientID: String) async -> ChannelValidationResult {
        do {
            let userID = try await resolveUsername(channelName, token: token, clientID: clientID)
            return userID.isEmpty ? .notFound : .exists
        } catch let error as ConnectionError {
            switch error {
            case .authenticationFailed:
                return .authenticationFailed
            case .networkError(let msg) where msg == "Unable to resolve username":
                return .notFound
            default:
                return .error(error.localizedDescription)
            }
        } catch {
            return .error(error.localizedDescription)
        }
    }

    /// Resolves a Twitch username to a user ID.
    ///
    /// - Parameters:
    ///   - username: The Twitch username to resolve
    ///   - token: OAuth access token
    ///   - clientID: Twitch application client ID
    /// - Returns: The user ID
    /// - Throws: `ConnectionError` if the username cannot be resolved
    func resolveUsername(_ username: String, token: String, clientID: String) async throws -> String
    {
        let sanitizedUsername = username.trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        guard !sanitizedUsername.isEmpty else {
            throw ConnectionError.networkError("Username cannot be empty")
        }

        guard
            let encodedUsername = sanitizedUsername.addingPercentEncoding(
                withAllowedCharacters: .urlQueryAllowed)
        else {
            throw ConnectionError.networkError("Invalid username format")
        }

        guard let url = URL(string: apiBaseURL + "/users?login=\(encodedUsername)") else {
            throw ConnectionError.networkError("Invalid users endpoint")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue(clientID, forHTTPHeaderField: "Client-ID")
        request.timeoutInterval = 15

        do {
            let (data, response) = try await URLSession.shared.data(for: request)

            guard let http = response as? HTTPURLResponse else {
                throw ConnectionError.networkError("No HTTP response")
            }

            guard (200..<300).contains(http.statusCode) else {
                if http.statusCode == 401 {
                    throw ConnectionError.authenticationFailed
                }
                throw ConnectionError.networkError("HTTP \(http.statusCode)")
            }

            let json: [String: Any]
            do {
                guard let parsed = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                    throw ConnectionError.networkError("Username response is not a JSON object")
                }
                json = parsed
            } catch {
                // Catch JSON parsing errors directly
                if let connectionError = error as? ConnectionError {
                    throw connectionError
                }
                throw ConnectionError.networkError("Failed to decode username response: \(error.localizedDescription)")
            }

            guard let dataArray = json["data"] as? [[String: Any]],
                let first = dataArray.first,
                let userID = first["id"] as? String,
                !userID.isEmpty
            else {
                throw ConnectionError.networkError("Unable to resolve username")
            }

            return userID
        } catch let error as ConnectionError {
            throw error
        } catch {
            Log.error(
                "TwitchChatService: Failed to resolve username - \(error.localizedDescription)",
                category: "Twitch")
            throw ConnectionError.networkError(error.localizedDescription)
        }
    }

}
