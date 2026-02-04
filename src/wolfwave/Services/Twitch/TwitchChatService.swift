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
    private let urlSession = URLSession.shared
    nonisolated(unsafe) private var sessionID: String?

    private var broadcasterID: String?
    private var botID: String?

    var shouldSendConnectionMessageOnSubscribe = true

    private var oauthToken: String?
    private var clientID: String?
    private var botUsername: String?

    var debugLoggingEnabled = false
    var getCurrentSongInfo: (() -> String)?
    var getLastSongInfo: (() -> String)?

    var commandsEnabled = true
    var currentSongCommandEnabled = true
    var lastSongCommandEnabled = true

    var onMessageReceived: ((ChatMessage) -> Void)?
    var onConnectionStateChanged: ((Bool) -> Void)?

    static let connectionStateChanged = NSNotification.Name("TwitchChatConnectionStateChanged")

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
    private let networkMonitorQueue = DispatchQueue(
        label: "com.mrdemonwolf.wolfwave.networkmonitor")

    nonisolated(unsafe) private var isNetworkReachable = true
    private let networkReachableLock = NSLock()

    nonisolated(unsafe) private var reconnectionAttempts = 0
    private let reconnectionLock = NSLock()

    private let maxReconnectionAttempts = 5

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
                    "Twitch: Approaching rate limit on \(endpoint): \(state.remaining)/\(state.limit) remaining",
                    category: "TwitchChat")
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
            "Twitch: Request queued due to rate limit. Retry after \(String(format: "%.1f", waitTime))s",
            category: "TwitchChat")

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
        networkPathMonitor = monitor

        monitor.pathUpdateHandler = { [weak self] path in
            self?.handleNetworkPathChange(path)
        }

        monitor.start(queue: networkMonitorQueue)
    }

    /// Stops network connectivity monitoring
    nonisolated private func stopNetworkMonitoring() {
        if let monitor = networkPathMonitor {
            monitor.cancel()
            networkPathMonitor = nil
        }
    }

    /// Handles network path changes and triggers reconnection if needed
    nonisolated private func handleNetworkPathChange(_ path: NWPath) {
        let isReachable = path.status == .satisfied
        let wasReachable = networkReachableLock.withLock { isNetworkReachable }

        networkReachableLock.withLock { isNetworkReachable = isReachable }

        if !wasReachable && isReachable {
            // Network became available after being unavailable
            attemptReconnect()
        } else if wasReachable && !isReachable {
            // Network became unavailable
            Log.warn("Twitch: Network unavailable, disconnecting", category: "TwitchChat")
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
            return
        }

        let attempts = reconnectionLock.withLock { reconnectionAttempts }

        if attempts >= maxReconnectionAttempts {
            Log.error("Twitch: Max reconnection attempts reached", category: "TwitchChat")
            return
        }

        // Exponential backoff: 1s, 2s, 4s, 8s, 16s
        let delaySeconds = min(pow(2.0, Double(attempts)), 16.0)

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
                } catch {
                    self.reconnectionLock.withLock {
                        self.reconnectionAttempts += 1
                    }

                    // If still under max attempts and network is reachable, schedule next attempt
                    let updatedAttempts = self.reconnectionLock.withLock {
                        self.reconnectionAttempts
                    }
                    let isReachable = self.networkReachableLock.withLock { self.isNetworkReachable }
                    if updatedAttempts < self.maxReconnectionAttempts && isReachable {
                        self.attemptReconnect()
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
            Log.error("Twitch: Invalid credentials for channel join", category: "TwitchChat")
            throw ConnectionError.invalidCredentials
        }

        guard !clientID.isEmpty else {
            Log.error("Twitch: Missing client ID for channel join", category: "TwitchChat")
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
            self?.currentSongCommandEnabled ?? true
        }

        commandDispatcher.setLastSongCommandEnabled { [weak self] in
            self?.lastSongCommandEnabled ?? true
        }

        // Don't set connected state here - wait for EventSub session_welcome
        // The connection state will be updated in handleSessionWelcome() when the session is actually established
        Log.info("Twitch: Joining channel \(broadcasterID)", category: "TwitchChat")

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
        Log.info(
            "Twitch: connectToChannel called for channel: \(channelName)", category: "TwitchChat")

        guard !channelName.isEmpty, !token.isEmpty else {
            Log.error("Twitch: Invalid channel name or token", category: "TwitchChat")
            throw ConnectionError.invalidCredentials
        }

        guard !clientID.isEmpty else {
            Log.error("Twitch: Missing client ID for channel connect", category: "TwitchChat")
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
            Log.debug(
                "Twitch: Resolved bot identity - username: \(resolvedUsername)",
                category: "TwitchChat")
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

        Log.debug(
            "Twitch: Calling joinChannel with broadcasterID: \(broadcasterUserID), botID: \(botUserID)",
            category: "TwitchChat")

        try joinChannel(
            broadcasterID: broadcasterUserID,
            botID: botUserID,
            token: token,
            clientID: clientID
        )

        Log.info(
            "Twitch: joinChannel completed, connection process initiated", category: "TwitchChat")

        // Store credentials for automatic reconnection (protected by reconnectionLock)
        setReconnectionCredentials(channelName: channelName, token: token, clientID: clientID)
        reconnectionLock.withLock { reconnectionAttempts = 0 }

        // Start network monitoring for automatic reconnection
        if networkPathMonitor == nil {
            startNetworkMonitoring()
        }

        Log.info("Twitch: Connected to channel \(channelName)", category: "TwitchChat")
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

        Log.debug(
            "Twitch: Resolved bot identity (static) - username: \(resolvedUsername)",
            category: "TwitchChat")
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
            Log.error("Twitch: Failed to construct users endpoint URL", category: "TwitchChat")
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
                    "Twitch: Authentication failed (401) - invalid or expired OAuth token",
                    category: "TwitchChat")
                throw ConnectionError.authenticationFailed
            }
            Log.error(
                "Twitch: Users endpoint error HTTP \(http.statusCode)", category: "TwitchChat")
            throw ConnectionError.networkError("Users endpoint returned \(http.statusCode)")
        }

        guard
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let dataArray = json["data"] as? [[String: Any]],
            let first = dataArray.first,
            let userID = first["id"] as? String,
            let login = first["login"] as? String
        else {
            Log.error("Twitch: Failed to parse user identity from response", category: "TwitchChat")
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
        Log.info("Twitch: leaveChannel() called", category: "TwitchChat")
        // Mark that we're disconnecting to prevent stale message processing
        disconnectLock.withLock { isProcessingDisconnect = true }

        disconnectFromEventSub()
        
        // Clear reconnection credentials (protected by reconnectionLock)
        setReconnectionCredentials(channelName: nil, token: nil, clientID: nil)
        reconnectionLock.withLock { reconnectionAttempts = 0 }

        // Clear reconnection credentials (protected by reconnectionLock)
        setReconnectionCredentials(channelName: nil, token: nil, clientID: nil)
        reconnectionLock.withLock { reconnectionAttempts = 0 }

        broadcasterID = nil
        botID = nil
        oauthToken = nil
        clientID = nil

        // Clear callbacks so no messages are processed
        onMessageReceived = nil
        onConnectionStateChanged = nil

        // Note: We do NOT clear onMessageReceived, getCurrentSongInfo, or getLastSongInfo
        // These callbacks are set by the AppDelegate and should persist across reconnections
        // Only clear the connection state callback
        onConnectionStateChanged = nil

        // Update internal state and notify listeners that we've left
        self.setConnected(false)
        Log.debug(
            "Twitch: Posting connectionStateChanged notification with isConnected=false",
            category: "TwitchChat")
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

        Log.info("Twitch: Left channel", category: "TwitchChat")
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
            Log.error("Twitch: Invalid validate URL", category: "TwitchChat")
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
                        "Twitch: Stored OAuth token is invalid or expired", category: "TwitchChat")
                } else {
                    Log.warn(
                        "Twitch: Token validate HTTP \(http.statusCode)", category: "TwitchChat")
                }
                return false
            }

            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                Log.warn("Twitch: Could not parse token validate response", category: "TwitchChat")
                return false
            }

            // optional: check scopes
            if let scopes = json["scopes"] as? [String] {
                let missing = requiredScopes.filter { !scopes.contains($0) }
                if !missing.isEmpty {
                    Log.warn(
                        "Twitch: Token missing required scopes: \(missing.joined(separator: ", "))",
                        category: "TwitchChat")
                    return false
                }
            }

            return true
        } catch {
            Log.error(
                "Twitch: Token validate request failed - \(error.localizedDescription)",
                category: "TwitchChat")
            return false
        }
    }

    /// Sends the connection confirmation message to the channel.
    ///
    /// Called automatically when the bot successfully subscribes to channel chat messages.
    /// Sends: "WolfWave Application is connected! 🎵"
    func sendConnectionMessage() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            guard let self = self else { return }
            let hasSent = self.connectionLock.withLock { self.hasSentConnectionMessage }
            if hasSent {
                return
            }
            self.connectionLock.withLock { self.hasSentConnectionMessage = true }
            self.sendMessage("WolfWave Application is connected! 🎵")
        }
    }

    /// Sends a message to the current channel.
    ///
    /// Notes:
    /// - Messages are sent via the Helix `/chat/messages` endpoint.
    /// - Twitch enforces rate limits; callers must handle failed sends and
    ///   avoid spamming the API.
    /// - Messages longer than 500 characters are truncated.
    /// - The method is fire-and-forget; failures are logged and surfaced
    ///   via the `Log` utility.
    ///
    /// - Parameter message: The message text to send
    // MARK: - Message Sending
    // IMPORTANT: Message sending is NOT queued. If connection is lost, the message is silently dropped.
    // Implement higher-level retry logic at the caller if guaranteed delivery is required.
    // Rate limits: Twitch enforces per-channel message rate limits. Exceeding limits will cause
    // temporary message delivery failures which are logged but not thrown.

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
    /// Error Handling:
    /// - If not connected, a warning is logged and the message is dropped
    /// - API failures are logged but not thrown; implement retry at caller if needed
    /// - Twitch "dropped" responses are logged as warnings
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
            Log.warn("Twitch: Not connected", category: "TwitchChat")
            return
        }

        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return
        }

        let finalMessage = trimmed.count > 500 ? String(trimmed.prefix(497)) + "..." : trimmed

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
        ) { result in
            switch result {
            case .success(let data):
                if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                    let dataArray = json["data"] as? [[String: Any]],
                    let messageData = dataArray.first
                {
                    let isSent = messageData["is_sent"] as? Bool ?? false
                    if isSent {
                        // Message sent successfully
                    } else {
                        Log.warn("Twitch: Message dropped by Twitch", category: "TwitchChat")
                    }
                } else {
                    // Message send response empty
                }
            case .failure(let error):
                Log.error(
                    "Twitch: Failed to send message - \(error.localizedDescription)",
                    category: "TwitchChat")
            }
        }
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
            if let response = commandDispatcher.processMessage(text) {
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
            request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        }

        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            if let error = error {
                completion(.failure(error))
                return
            }

            // Update rate limit state from response headers
            if let httpResponse = response as? HTTPURLResponse {
                self?.updateRateLimitState(endpoint: endpoint, from: httpResponse.allHeaderFields)

                // Log rate limit status for debugging
                if let remaining = httpResponse.allHeaderFields["Ratelimit-Remaining"] as? String {
                    Log.debug(
                        "Twitch: Rate limit remaining: \(remaining)",
                        category: "TwitchChat")
                }
            }

            guard let data = data else {
                completion(.failure(ConnectionError.networkError("No response data")))
                return
            }

            completion(.success(data))
        }.resume()
    }

    // MARK: - WebSocket Management

    /// Connects to the Twitch EventSub WebSocket endpoint.
    private func connectToEventSub() {
        guard let url = URL(string: "wss://eventsub.wss.twitch.tv/ws") else {
            Log.error("Twitch: Invalid EventSub URL", category: "TwitchChat")
            setConnected(false)
            onConnectionStateChanged?(false)
            NotificationCenter.default.post(
                name: TwitchChatService.connectionStateChanged,
                object: nil,
                userInfo: ["isConnected": false]
            )
            return
        }

        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 60  // Increased from 30 to 60 seconds
        config.timeoutIntervalForResource = 300
        config.waitsForConnectivity = true
        config.requestCachePolicy = .reloadIgnoringLocalCacheData

        let session = URLSession(configuration: config, delegate: nil, delegateQueue: nil)
        webSocketTask = session.webSocketTask(with: url)

        Log.info("Twitch: Starting EventSub WebSocket connection", category: "TwitchChat")
        webSocketTask?.resume()

        // Start a timer to detect if session_welcome doesn't arrive in time
        startSessionWelcomeTimeout()

        receiveWebSocketMessage()
    }

    /// Starts a timeout timer for receiving the session_welcome message.
    private func startSessionWelcomeTimeout() {
        sessionTimerLock.withLock {
            sessionWelcomeTimer?.invalidate()
            sessionWelcomeTimer = Timer.scheduledTimer(withTimeInterval: 10.0, repeats: false) {
                [weak self] _ in
                self?.handleSessionWelcomeTimeout()
            }
        }
    }

    /// Called when session_welcome timeout expires.
    private func handleSessionWelcomeTimeout() {
        guard sessionID == nil else { return }  // If we already got a welcome, ignore

        Log.error(
            "Twitch: Session welcome timeout - WebSocket may not be responding",
            category: "TwitchChat")
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
                "Twitch: Attempting reconnection after session welcome timeout",
                category: "TwitchChat")
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
        webSocketTask?.cancel(with: .goingAway, reason: nil)
        webSocketTask = nil
        sessionID = nil

        // Cancel the session welcome timer
        sessionTimerLock.withLock {
            sessionWelcomeTimer?.invalidate()
            sessionWelcomeTimer = nil
        }

        Log.debug("Twitch: EventSub WebSocket disconnected", category: "TwitchChat")
    }

    private func receiveWebSocketMessage() {
        guard let task = webSocketTask else {
            Log.debug(
                "Twitch: WebSocket task is nil, stopping receive loop", category: "TwitchChat")
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
                let nsError = error as NSError
                let errorCode = nsError.code
                let errorDomain = nsError.domain

                // Provide specific logging for timeout errors
                if errorDomain == NSURLErrorDomain && errorCode == NSURLErrorTimedOut {
                    Log.error(
                        "Twitch: WebSocket connection timed out. This may be due to network issues, firewall blocking, or Twitch service problems.",
                        category: "TwitchChat")
                } else {
                    Log.error(
                        "Twitch: WebSocket connection error: \(error.localizedDescription) (Domain: \(errorDomain), Code: \(errorCode))",
                        category: "TwitchChat")
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
                    Log.info("Twitch: Attempting automatic reconnection", category: "TwitchChat")
                    self.attemptReconnect()
                }
            }
        }
    }

    /// Handles a received WebSocket message.
    private func handleWebSocketMessage(_ text: String) {
        guard let data = text.data(using: .utf8),
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            return
        }

        guard let metadata = json["metadata"] as? [String: Any],
            let messageType = metadata["message_type"] as? String
        else {
            return
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
        Log.info("Twitch: handleSessionWelcome called", category: "TwitchChat")

        guard let payload = json["payload"] as? [String: Any],
            let session = payload["session"] as? [String: Any],
            let sessionID = session["id"] as? String
        else {
            Log.error("Twitch: Failed to parse session ID", category: "TwitchChat")
            return
        }

        // Cancel the welcome timeout since we got the welcome message
        cancelSessionWelcomeTimeout()

        self.sessionID = sessionID
        Log.info(
            "Twitch: EventSub session established with ID: \(sessionID)", category: "TwitchChat")

        // Ensure connected state is set properly
        setConnected(true)
        onConnectionStateChanged?(true)

        Log.debug(
            "Twitch: Posting connectionStateChanged notification with isConnected=true",
            category: "TwitchChat")
        NotificationCenter.default.post(
            name: TwitchChatService.connectionStateChanged,
            object: nil,
            userInfo: ["isConnected": true]
        )
        Log.debug("Twitch: Notification posted successfully", category: "TwitchChat")

        subscribeToChannelChatMessage()
    }

    /// Handles notification messages containing EventSub events.
    ///
    /// - Parameter json: The notification message JSON
    private func handleNotification(_ json: [String: Any]) {
        guard let payload = json["payload"] as? [String: Any] else { return }
        handleEventSubMessage(payload)
    }

    // MARK: - EventSub Subscriptions

    /// Subscribes to the channel.chat.message EventSub event.
    private func subscribeToChannelChatMessage() {
        guard let sessionID = sessionID,
            let broadcasterID = broadcasterID,
            let botID = botID,
            let token = oauthToken,
            let clientID = clientID
        else {
            Log.error(
                "Twitch: Missing credentials for EventSub subscription", category: "TwitchChat")
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
            Log.error("Twitch: Invalid EventSub subscriptions URL", category: "TwitchChat")
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue(clientID, forHTTPHeaderField: "Client-ID")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: subscriptionBody)

        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            if let error = error {
                Log.error(
                    "Twitch: EventSub subscription error - \(error.localizedDescription)",
                    category: "TwitchChat")
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
                    Log.info("Twitch: Connected to chat", category: "TwitchChat")
                    Log.debug(
                        "Twitch: shouldSendConnectionMessageOnSubscribe = \(self?.shouldSendConnectionMessageOnSubscribe ?? false)",
                        category: "TwitchChat")
                    if self?.shouldSendConnectionMessageOnSubscribe == true {
                        self?.sendConnectionMessage()
                    } else {
                        Log.debug(
                            "Twitch: Suppressed connection message on subscribe",
                            category: "TwitchChat")
                    }
                } else {
                    let responseText =
                        data.flatMap { String(data: $0, encoding: .utf8) } ?? "No response"
                    Log.error(
                        "Twitch: EventSub subscription failed - HTTP \(http.statusCode) - \(responseText)",
                        category: "TwitchChat")
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

            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                let dataArray = json["data"] as? [[String: Any]],
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
                "Twitch: Failed to resolve username - \(error.localizedDescription)",
                category: "TwitchChat")
            throw ConnectionError.networkError(error.localizedDescription)
        }
    }

}
