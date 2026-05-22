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
/// Thread Safety:
/// - Conforms to `@unchecked Sendable` because all mutable state is protected
///   by dedicated `NSLock` instances (not by Swift's actor isolation). This is
///   intentional for low-level WebSocket/network code that requires synchronous
///   locking semantics incompatible with actor isolation.
/// - Mutable properties are annotated with `nonisolated(unsafe)` to satisfy
///   `SWIFT_STRICT_CONCURRENCY = complete`. Each such property is guarded by
///   a specific lock — see the inline doc comments on each lock for the
///   exhaustive list of properties it protects.
/// - Callbacks occur on background queues; dispatch to main for UI updates.
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
    /// Lock protecting WebSocket session state.
    /// Guards: `webSocketTask`, `sessionID`.
    private let webSocketLock = NSLock()

    nonisolated(unsafe) private var _broadcasterID: String?
    nonisolated(unsafe) private var _botID: String?

    var shouldSendConnectionMessageOnSubscribe = true

    nonisolated(unsafe) private var _oauthToken: String?
    nonisolated(unsafe) private var _clientID: String?
    nonisolated(unsafe) private var _botUsername: String?

    var debugLoggingEnabled = false
    nonisolated(unsafe) private var _getCurrentSongInfo: (@Sendable () -> String)?
    nonisolated(unsafe) private var _getLastSongInfo: (@Sendable () -> String)?
    nonisolated(unsafe) private var _getStatsInfo: (@Sendable () -> String)?

    nonisolated(unsafe) private var _commandsEnabled = true

    /// Lock protecting credential and callback properties accessed from multiple threads.
    /// Guards: `_broadcasterID`, `_botID`, `_oauthToken`, `_clientID`, `_botUsername`,
    /// `_commandsEnabled`, `_onMessageReceived`, `_onConnectionStateChanged`,
    /// `_getCurrentSongInfo`, `_getLastSongInfo`.
    private let credentialsLock = NSLock()

    private var broadcasterID: String? {
        get { credentialsLock.withLock { _broadcasterID } }
        set { credentialsLock.withLock { _broadcasterID = newValue } }
    }

    private var botID: String? {
        get { credentialsLock.withLock { _botID } }
        set { credentialsLock.withLock { _botID = newValue } }
    }

    private var oauthToken: String? {
        get { credentialsLock.withLock { _oauthToken } }
        set { credentialsLock.withLock { _oauthToken = newValue } }
    }

    private var clientID: String? {
        get { credentialsLock.withLock { _clientID } }
        set { credentialsLock.withLock { _clientID = newValue } }
    }

    private var botUsername: String? {
        get { credentialsLock.withLock { _botUsername } }
        set { credentialsLock.withLock { _botUsername = newValue } }
    }

    var commandsEnabled: Bool {
        get { credentialsLock.withLock { _commandsEnabled } }
        set { credentialsLock.withLock { _commandsEnabled = newValue } }
    }

    var getCurrentSongInfo: (@Sendable () -> String)? {
        get { credentialsLock.withLock { _getCurrentSongInfo } }
        set { credentialsLock.withLock { _getCurrentSongInfo = newValue } }
    }

    var getLastSongInfo: (@Sendable () -> String)? {
        get { credentialsLock.withLock { _getLastSongInfo } }
        set { credentialsLock.withLock { _getLastSongInfo = newValue } }
    }

    /// Closure returning the listening-stats string for the `!stats` command.
    var getStatsInfo: (@Sendable () -> String)? {
        get { credentialsLock.withLock { _getStatsInfo } }
        set { credentialsLock.withLock { _getStatsInfo = newValue } }
    }

    /// Whether the current song command is enabled (computed from UserDefaults on each access)
    var currentSongCommandEnabled: Bool {
        UserDefaults.standard.object(forKey: AppConstants.UserDefaults.currentSongCommandEnabled) as? Bool ?? false
    }

    /// Whether the last song command is enabled (computed from UserDefaults on each access)
    var lastSongCommandEnabled: Bool {
        UserDefaults.standard.object(forKey: AppConstants.UserDefaults.lastSongCommandEnabled) as? Bool ?? false
    }

    /// Whether the `!stats` command should respond — both the Stats feature and
    /// the command itself must be enabled (computed from UserDefaults).
    var statsCommandActive: Bool {
        let stats = UserDefaults.standard.bool(forKey: AppConstants.UserDefaults.statsEnabled)
        let command = UserDefaults.standard.bool(forKey: AppConstants.UserDefaults.statsCommandEnabled)
        return stats && command
    }

    /// Wire the song request service into the command dispatcher.
    func setSongRequestService(callback: @escaping () -> SongRequestService?) {
        commandDispatcher.setSongRequestService(callback: callback)
    }

    /// Wire the song request queue into the command dispatcher.
    func setSongRequestQueue(callback: @escaping () -> SongRequestQueue?) {
        commandDispatcher.setSongRequestQueue(callback: callback)
    }

    /// Wire the skip-vote manager into the command dispatcher.
    func setSkipVoteManager(callback: @escaping () -> SkipVoteManager?) {
        commandDispatcher.setSkipVoteManager(callback: callback)
    }

    // MARK: - Redemption Wiring

    /// Helix client for the WolfWave-managed channel-point reward.
    private let channelPointsService = TwitchChannelPointsService()

    nonisolated(unsafe) private var _songRequestService: SongRequestService?

    /// Live `SongRequestService`, used by the channel-point and bit redemption
    /// handlers (the `!sr` command path goes through the dispatcher instead).
    /// Set once by `AppDelegate` at startup.
    var songRequestService: SongRequestService? {
        get { credentialsLock.withLock { _songRequestService } }
        set { credentialsLock.withLock { _songRequestService = newValue } }
    }

    nonisolated(unsafe) private var _onMessageReceived: (@Sendable (ChatMessage) -> Void)?
    nonisolated(unsafe) private var _onConnectionStateChanged: (@Sendable (Bool) -> Void)?
    nonisolated(unsafe) private var _onSkipPollEnded: (@Sendable (Int, Int) -> Void)?

    var onMessageReceived: (@Sendable (ChatMessage) -> Void)? {
        get { credentialsLock.withLock { _onMessageReceived } }
        set { credentialsLock.withLock { _onMessageReceived = newValue } }
    }

    var onConnectionStateChanged: (@Sendable (Bool) -> Void)? {
        get { credentialsLock.withLock { _onConnectionStateChanged } }
        set { credentialsLock.withLock { _onConnectionStateChanged = newValue } }
    }

    /// Invoked when a vote-skip Twitch poll finishes. Parameters: (skipVotes, keepVotes).
    var onSkipPollEnded: (@Sendable (Int, Int) -> Void)? {
        get { credentialsLock.withLock { _onSkipPollEnded } }
        set { credentialsLock.withLock { _onSkipPollEnded = newValue } }
    }


    static let connectionStateChanged = NSNotification.Name(AppConstants.Notifications.twitchConnectionStateChanged)

    nonisolated(unsafe) private var _connected = false
    nonisolated(unsafe) private var hasSentConnectionMessage = false
    nonisolated(unsafe) private var _streamLive = false
    /// Lock protecting connection state flags.
    /// Guards: `_connected`, `hasSentConnectionMessage`, `_streamLive`.
    private let connectionLock = NSLock()

    var isConnected: Bool {
        connectionLock.withLock { _connected }
    }

    /// Whether the broadcaster's stream is currently live.
    ///
    /// Maintained by the `stream.online` / `stream.offline` EventSub events and
    /// seeded by a one-shot Helix check on connect. The `!stats` command stays
    /// silent unless this is `true`.
    var isStreamLive: Bool {
        get { connectionLock.withLock { _streamLive } }
        set { connectionLock.withLock { _streamLive = newValue } }
    }

    nonisolated private func setConnected(_ value: Bool) {
        connectionLock.withLock { _connected = value }
    }

    nonisolated(unsafe) private var isProcessingDisconnect = false
    /// Lock protecting the disconnect-in-progress flag.
    /// Guards: `isProcessingDisconnect`.
    private let disconnectLock = NSLock()

    nonisolated(unsafe) private var networkPathMonitor: NWPathMonitor?
    /// Lock protecting the network path monitor lifecycle.
    /// Guards: `networkPathMonitor`.
    private let networkMonitorLock = NSLock()
    private let networkMonitorQueue = DispatchQueue(
        label: "com.mrdemonwolf.wolfwave.networkmonitor")

    nonisolated(unsafe) private var isNetworkReachable = true
    /// Lock protecting the network reachability flag.
    /// Guards: `isNetworkReachable`.
    private let networkReachableLock = NSLock()

    /// Tracks total network-triggered reconnect cycles to prevent infinite loops
    /// when the network path flaps repeatedly.
    nonisolated(unsafe) private var networkReconnectCycles = 0
    private let maxNetworkReconnectCycles = AppConstants.Twitch.maxNetworkReconnectCycles
    nonisolated(unsafe) private var lastNetworkReconnectTime: TimeInterval = 0

    nonisolated(unsafe) private var reconnectionAttempts = 0
    /// Lock protecting reconnection state and stored credentials.
    /// Guards: `reconnectionAttempts`, `networkReconnectCycles`,
    /// `lastNetworkReconnectTime`, `_reconnectChannelName`,
    /// `_reconnectToken`, `_reconnectClientID`.
    private let reconnectionLock = NSLock()

    private let maxReconnectionAttempts = AppConstants.Twitch.maxReconnectionAttempts

    nonisolated(unsafe) private var _reconnectChannelName: String?
    nonisolated(unsafe) private var _reconnectToken: String?
    nonisolated(unsafe) private var _reconnectClientID: String?

    nonisolated(unsafe) private var sessionWelcomeTimer: Timer?
    /// Lock protecting the session welcome timeout timer.
    /// Guards: `sessionWelcomeTimer`.
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
    /// Lock protecting API rate limit tracking state.
    /// Guards: `rateLimits`.
    private let rateLimitLock = NSLock()

    nonisolated(unsafe) private var requestQueue: [() -> Void] = []
    /// Lock protecting the rate-limited request queue.
    /// Guards: `requestQueue`.
    private let requestQueueLock = NSLock()

    nonisolated(unsafe) private var isProcessingQueue = false
    /// Lock protecting the queue-processing flag.
    /// Guards: `isProcessingQueue`.
    private let queueProcessingLock = NSLock()

    /// Checks whether the local rate-limit accountant believes a request to
    /// `endpoint` is safe to send right now.
    ///
    /// Counters reset automatically once their bucket window elapses.
    ///
    /// - Parameter endpoint: Helix endpoint key (e.g. `"chat/messages"`).
    /// - Returns: `true` if at least one request remains in the bucket.
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

    /// Returns the seconds to wait before retrying when the local accountant
    /// believes `endpoint` is currently saturated.
    ///
    /// - Parameter endpoint: Helix endpoint key.
    /// - Returns: Seconds until the bucket resets, or `nil` if no wait is needed.
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

    /// Records Twitch's `Ratelimit-Remaining` and `Ratelimit-Reset` headers
    /// after a Helix response so subsequent calls can throttle locally.
    ///
    /// - Parameters:
    ///   - endpoint: Helix endpoint key.
    ///   - headers: Response headers from the most recent call.
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

        commandDispatcher.setStatsInfo { [weak self] in
            self?.getStatsInfo?() ?? "No listening stats yet"
        }

        // `!stats` answers only when the feature is on AND the stream is live.
        commandDispatcher.setStatsCommandEnabled { [weak self] in
            guard let self else { return false }
            return self.statsCommandActive && self.isStreamLive
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
                // Vote-skip Polls mode needs the polls scope. Only require it when
                // the user has actually enabled Polls mode, so existing users are
                // not forced to re-authorize unless they opt in.
                var effectiveScopes = requiredScopes
                if UserDefaults.standard.bool(forKey: AppConstants.UserDefaults.voteSkipUsePolls),
                   !effectiveScopes.contains("channel:manage:polls") {
                    effectiveScopes.append("channel:manage:polls")
                }
                let missing = effectiveScopes.filter { !scopes.contains($0) }
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
    /// Lock protecting the pending message retry queue.
    /// Guards: `pendingMessages`.
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
            let isSubscriber = badges.contains { $0.setID == "subscriber" }
            let isVIP = badges.contains { $0.setID == "vip" }
            let bypassCooldown = isModerator || isBroadcaster

            let context = BotCommandContext(
                userID: userID,
                username: username,
                isModerator: isModerator,
                isBroadcaster: isBroadcaster,
                isSubscriber: isSubscriber,
                isVIP: isVIP,
                messageID: messageID
            )

            let asyncReply: (String) -> Void = { [weak self] response in
                self?.sendMessage(response, replyTo: messageID)
            }

            if let response = commandDispatcher.processMessage(
                text, userID: userID, isModerator: bypassCooldown,
                context: context, asyncReply: asyncReply
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

    /// Reads the next frame from the EventSub WebSocket and recursively
    /// schedules itself to keep the receive loop alive for the lifetime of
    /// the connection.
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
        var timestamp = try? Date.ISO8601FormatStyle(includingFractionalSeconds: true)
            .parse(messageTimestamp)
        if timestamp == nil {
            // Fallback: try without fractional seconds
            timestamp = try? Date.ISO8601FormatStyle().parse(messageTimestamp)
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
        subscribeToPollEvents()
        subscribeToStreamEvents()
        seedStreamLiveState()
        subscribeToRedemptionsIfEnabled()
    }

    /// Handles notification messages containing EventSub events.
    ///
    /// Routes each notification to the handler for its subscription type.
    ///
    /// - Parameter json: The notification message JSON
    private func handleNotification(_ json: [String: Any]) {
        guard let payload = json["payload"] as? [String: Any] else { return }

        guard let subscription = payload["subscription"] as? [String: Any],
            let subType = subscription["type"] as? String
        else {
            Log.warn("TwitchChatService: EventSub notification missing subscription type", category: "Twitch")
            return
        }

        switch subType {
        case AppConstants.Twitch.eventSubChatMessage:
            handleEventSubMessage(payload)
        case "channel.poll.end":
            handlePollEndEvent(payload)
        case AppConstants.Twitch.eventSubChannelPointsRedemption:
            handleChannelPointsRedemption(payload)
        case AppConstants.Twitch.eventSubBitsUse:
            handleBitsUse(payload)
        default:
            handleStreamStateNotification(type: subType)
        }
    }

    /// Parses a `channel.poll.end` event and, when it is our vote-skip poll,
    /// forwards the Skip/Keep tallies to `onSkipPollEnded`.
    ///
    /// - Parameter payload: The EventSub notification payload.
    private func handlePollEndEvent(_ payload: [String: Any]) {
        guard let event = payload["event"] as? [String: Any],
              let title = event["title"] as? String,
              title == TwitchChatService.skipPollTitle,
              let choices = event["choices"] as? [[String: Any]]
        else { return }

        var skipVotes = 0
        var keepVotes = 0
        for choice in choices {
            let votes = choice["votes"] as? Int ?? 0
            switch choice["title"] as? String {
            case TwitchChatService.skipPollSkipChoice: skipVotes = votes
            case TwitchChatService.skipPollKeepChoice: keepVotes = votes
            default: break
            }
        }

        Log.info("TwitchChatService: Vote-skip poll ended — \(skipVotes) skip / \(keepVotes) keep", category: "Twitch")
        onSkipPollEnded?(skipVotes, keepVotes)
    }

    // MARK: - Vote-Skip Polls

    /// Title used for vote-skip Twitch polls. Also the match key for `channel.poll.end`.
    static let skipPollTitle = "Skip the current song?"

    /// "Skip" choice label on a vote-skip poll.
    static let skipPollSkipChoice = "Skip"

    /// "Keep playing" choice label on a vote-skip poll.
    static let skipPollKeepChoice = "Keep playing"

    /// Creates a native Twitch poll asking chat to vote on skipping the current song.
    ///
    /// Requires the `channel:manage:polls` scope and Affiliate/Partner status —
    /// missing either causes Twitch to reject the request, in which case this
    /// returns `false` and `SkipVoteManager` falls back to a chat tally.
    ///
    /// - Parameters:
    ///   - title: Poll question (truncated to Twitch's 60-character limit).
    ///   - durationSeconds: Poll duration, clamped to Twitch's 15–1800 second range.
    /// - Returns: `true` when Twitch accepted the poll.
    func createSkipPoll(title: String, durationSeconds: Int) async -> Bool {
        guard let broadcasterID = broadcasterID,
              let token = oauthToken,
              let clientID = clientID
        else {
            Log.warn("TwitchChatService: Cannot create poll — missing credentials", category: "Twitch")
            return false
        }

        guard let url = URL(string: apiBaseURL + "/polls") else { return false }

        let duration = min(max(durationSeconds, 15), 1800)
        let body: [String: Any] = [
            "broadcaster_id": broadcasterID,
            "title": String(title.prefix(60)),
            "choices": [
                ["title": TwitchChatService.skipPollSkipChoice],
                ["title": TwitchChatService.skipPollKeepChoice],
            ],
            "duration": duration,
        ]

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue(clientID, forHTTPHeaderField: "Client-ID")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        } catch {
            Log.error("TwitchChatService: Failed to serialize poll body - \(error.localizedDescription)", category: "Twitch")
            return false
        }

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else { return false }
            if (200..<300).contains(http.statusCode) {
                Log.info("TwitchChatService: Vote-skip poll created", category: "Twitch")
                return true
            }
            let text = String(data: data, encoding: .utf8) ?? "No response"
            Log.warn("TwitchChatService: Poll creation failed — HTTP \(http.statusCode) — \(text)", category: "Twitch")
            return false
        } catch {
            Log.error("TwitchChatService: Poll creation request failed - \(error.localizedDescription)", category: "Twitch")
            return false
        }
    }

    /// Subscribes to `channel.poll.end` so finished vote-skip polls can be tallied.
    ///
    /// No-op unless vote-skip Polls mode is enabled. A failed subscription (e.g.
    /// missing scope) is logged but does not affect the chat connection.
    private func subscribeToPollEvents() {
        guard UserDefaults.standard.bool(forKey: AppConstants.UserDefaults.voteSkipEnabled),
              UserDefaults.standard.bool(forKey: AppConstants.UserDefaults.voteSkipUsePolls)
        else { return }

        let currentSessionID: String? = webSocketLock.withLock { sessionID }
        guard let sessionID = currentSessionID,
              let broadcasterID = broadcasterID,
              let token = oauthToken,
              let clientID = clientID
        else {
            Log.warn("TwitchChatService: Missing credentials for poll EventSub subscription", category: "Twitch")
            return
        }

        let subscriptionBody: [String: Any] = [
            "type": "channel.poll.end",
            "version": "1",
            "condition": ["broadcaster_user_id": broadcasterID],
            "transport": [
                "method": "websocket",
                "session_id": sessionID,
            ],
        ]

        guard let url = URL(string: apiBaseURL + "/eventsub/subscriptions") else { return }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue(clientID, forHTTPHeaderField: "Client-ID")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: subscriptionBody)
        } catch {
            Log.error("TwitchChatService: Failed to serialize poll EventSub body - \(error.localizedDescription)", category: "Twitch")
            return
        }

        URLSession.shared.dataTask(with: request) { data, response, _ in
            if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                let text = data.flatMap { String(data: $0, encoding: .utf8) } ?? "No response"
                Log.warn("TwitchChatService: channel.poll.end subscription failed — HTTP \(http.statusCode) — \(text)", category: "Twitch")
            } else {
                Log.info("TwitchChatService: Subscribed to vote-skip poll events", category: "Twitch")
            }
        }.resume()
    }

    /// Updates `isStreamLive` from a `stream.online` / `stream.offline` event.
    /// Other EventSub types are ignored.
    private func handleStreamStateNotification(type: String) {
        switch type {
        case "stream.online":
            isStreamLive = true
            Log.info("TwitchChatService: Stream went live", category: "Twitch")
        case "stream.offline":
            isStreamLive = false
            Log.info("TwitchChatService: Stream went offline", category: "Twitch")
        default:
            Log.debug("TwitchChatService: Ignoring unexpected EventSub type: \(type)", category: "Twitch")
        }
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

    /// Subscribes to `stream.online` / `stream.offline` so `isStreamLive` stays
    /// current. Best-effort — a failure here does not affect the chat
    /// connection. These EventSub types require no extra OAuth scope.
    private func subscribeToStreamEvents() {
        let currentSessionID: String? = webSocketLock.withLock { sessionID }
        guard let sessionID = currentSessionID,
            let broadcasterID = broadcasterID,
            let token = oauthToken,
            let clientID = clientID,
            let url = URL(string: apiBaseURL + "/eventsub/subscriptions")
        else { return }

        for eventType in ["stream.online", "stream.offline"] {
            let body: [String: Any] = [
                "type": eventType,
                "version": "1",
                "condition": ["broadcaster_user_id": broadcasterID],
                "transport": ["method": "websocket", "session_id": sessionID],
            ]
            guard let payload = try? JSONSerialization.data(withJSONObject: body) else { continue }

            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            request.setValue(clientID, forHTTPHeaderField: "Client-ID")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = payload

            URLSession.shared.dataTask(with: request) { _, response, error in
                if let error = error {
                    Log.warn(
                        "TwitchChatService: \(eventType) subscription error - \(error.localizedDescription)",
                        category: "Twitch")
                } else if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                    Log.warn(
                        "TwitchChatService: \(eventType) subscription failed - HTTP \(http.statusCode)",
                        category: "Twitch")
                } else {
                    Log.info("TwitchChatService: Subscribed to \(eventType)", category: "Twitch")
                }
            }.resume()
        }
    }

    /// Seeds `isStreamLive` with a single Helix "Get Streams" call, covering the
    /// case where the stream was already live before WolfWave connected.
    private func seedStreamLiveState() {
        guard let broadcasterID = broadcasterID,
            let token = oauthToken,
            let clientID = clientID,
            let url = URL(string: apiBaseURL + "/streams?user_id=\(broadcasterID)")
        else { return }

        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue(clientID, forHTTPHeaderField: "Client-ID")

        URLSession.shared.dataTask(with: request) { [weak self] data, _, _ in
            guard let self = self,
                let data = data,
                let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                let streams = json["data"] as? [[String: Any]]
            else { return }
            let live = !streams.isEmpty
            self.isStreamLive = live
            Log.info("TwitchChatService: Seeded stream-live state — live=\(live)", category: "Twitch")
        }.resume()
    }

    // MARK: - Redemption EventSub Subscriptions

    /// Subscribes to channel-point and/or bit EventSub events when the matching
    /// song-request features are enabled. Channel-point and bit subscriptions
    /// require the signed-in account to be the broadcaster — when a separate bot
    /// account is in use they are skipped and the UI is notified.
    ///
    /// Safe to call any time after `session_welcome`; re-subscribing an existing
    /// type is treated as a no-op (Twitch returns HTTP 409).
    private func subscribeToRedemptionsIfEnabled() {
        let defaults = UserDefaults.standard
        let channelPointsEnabled = defaults.bool(
            forKey: AppConstants.UserDefaults.songRequestChannelPointsEnabled)
        let bitsEnabled = defaults.bool(forKey: AppConstants.UserDefaults.songRequestBitsEnabled)

        guard channelPointsEnabled || bitsEnabled else {
            setRedemptionStatus(.ok)
            return
        }

        // Channel-point and bit EventSub require the broadcaster's own token.
        guard let broadcasterID, let botID, broadcasterID == botID else {
            Log.warn(
                "TwitchChatService: Redemption events need the broadcaster account — skipping",
                category: "Twitch")
            setRedemptionStatus(.botAccount)
            return
        }

        setRedemptionStatus(.ok)

        if channelPointsEnabled {
            Task { await ensureSongRequestRewardAndSubscribe() }
        }
        if bitsEnabled {
            subscribeToBitsUse()
        }
    }

    /// Re-evaluates redemption subscriptions against the current settings.
    /// Called by the settings UI after the streamer changes a redemption
    /// toggle. A no-op when not connected.
    func refreshRedemptionSubscriptions() {
        guard isConnected else { return }
        subscribeToRedemptionsIfEnabled()
    }

    /// Ensures the WolfWave channel-point reward exists, syncs its cost, and
    /// subscribes to its redemption events.
    private func ensureSongRequestRewardAndSubscribe() async {
        guard let credentials = currentChannelPointCredentials() else { return }
        let cost = channelPointsCostSetting()
        do {
            let rewardID = try await channelPointsService.ensureReward(
                credentials: credentials, cost: cost)
            try? await channelPointsService.updateRewardCost(
                credentials: credentials, rewardID: rewardID, cost: cost)
            subscribeToChannelPointsRedemption()
            setRedemptionStatus(.ok)
        } catch {
            Log.error(
                "TwitchChatService: Failed to set up channel-point reward - \(error.localizedDescription)",
                category: "Twitch")
            setRedemptionStatus(.subscribeFailed)
        }
    }

    /// Subscribes to `channel.channel_points_custom_reward_redemption.add`.
    private func subscribeToChannelPointsRedemption() {
        guard let broadcasterID else { return }
        postEventSubSubscription(
            type: AppConstants.Twitch.eventSubChannelPointsRedemption,
            condition: ["broadcaster_user_id": broadcasterID],
            label: "channel-point redemptions")
    }

    /// Subscribes to `channel.bits.use`.
    private func subscribeToBitsUse() {
        guard let broadcasterID else { return }
        postEventSubSubscription(
            type: AppConstants.Twitch.eventSubBitsUse,
            condition: ["broadcaster_user_id": broadcasterID],
            label: "bit usage")
    }

    /// Posts an EventSub subscription request over the active WebSocket session.
    ///
    /// - Parameters:
    ///   - type: EventSub subscription type.
    ///   - version: Subscription version (default `"1"`).
    ///   - condition: The subscription `condition` object.
    ///   - label: Human-readable label used in logs.
    private func postEventSubSubscription(
        type: String,
        version: String = "1",
        condition: [String: Any],
        label: String
    ) {
        let currentSessionID: String? = webSocketLock.withLock { sessionID }
        guard let sessionID = currentSessionID,
            let token = oauthToken,
            let clientID = clientID
        else {
            Log.error(
                "TwitchChatService: Missing credentials for \(label) subscription", category: "Twitch")
            return
        }

        let body: [String: Any] = [
            "type": type,
            "version": version,
            "condition": condition,
            "transport": ["method": "websocket", "session_id": sessionID],
        ]

        guard let url = URL(string: apiBaseURL + "/eventsub/subscriptions") else { return }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue(clientID, forHTTPHeaderField: "Client-ID")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        } catch {
            Log.error(
                "TwitchChatService: Failed to serialize \(label) subscription - \(error.localizedDescription)",
                category: "Twitch")
            return
        }

        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            if let error {
                Log.error(
                    "TwitchChatService: \(label) subscription error - \(error.localizedDescription)",
                    category: "Twitch")
                return
            }
            guard let http = response as? HTTPURLResponse else { return }
            if (200..<300).contains(http.statusCode) {
                Log.info("TwitchChatService: Subscribed to \(label)", category: "Twitch")
            } else if http.statusCode == 409 {
                Log.info(
                    "TwitchChatService: \(label) subscription already active", category: "Twitch")
            } else {
                let responseText = data.flatMap { String(data: $0, encoding: .utf8) } ?? "No response"
                Log.error(
                    "TwitchChatService: \(label) subscription failed - HTTP \(http.statusCode) - \(responseText)",
                    category: "Twitch")
                self?.setRedemptionStatus(http.statusCode == 403 ? .scopeMissing : .subscribeFailed)
            }
        }.resume()
    }

    // MARK: - Redemption Event Handlers

    /// Handles a channel-point reward redemption. Ignores redemptions for any
    /// reward other than the WolfWave-managed one, routes the viewer's input
    /// into the song-request pipeline, then fulfils the redemption on success
    /// or cancels it (refunding the points) on failure.
    private func handleChannelPointsRedemption(_ payload: [String: Any]) {
        guard
            UserDefaults.standard.bool(
                forKey: AppConstants.UserDefaults.songRequestChannelPointsEnabled),
            let event = payload["event"] as? [String: Any]
        else { return }

        let rewardID = ((event["reward"] as? [String: Any])?["id"] as? String) ?? ""
        let storedRewardID = UserDefaults.standard.string(
            forKey: AppConstants.UserDefaults.songRequestChannelPointsRewardID) ?? ""
        guard !rewardID.isEmpty, rewardID == storedRewardID else { return }

        let redemptionID = (event["id"] as? String) ?? ""
        let userName = ((event["user_name"] as? String) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let userInput = ((event["user_input"] as? String) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !redemptionID.isEmpty, !userName.isEmpty else { return }

        let credentials = currentChannelPointCredentials()

        Task { @MainActor in
            guard let service = self.songRequestService else { return }

            if userInput.isEmpty {
                self.sendMessage(
                    "@\(userName) add a song name when you redeem — refunding your points.")
                await self.resolveRedemption(
                    credentials, rewardID: rewardID, redemptionID: redemptionID, as: .canceled)
                return
            }

            let result = await service.processRequest(
                query: userInput,
                username: userName,
                source: .channelPoints(redemptionID: redemptionID, rewardID: rewardID))
            let (message, resolution) = self.redemptionOutcome(for: result, username: userName)
            self.sendMessage(message)
            await self.resolveRedemption(
                credentials, rewardID: rewardID, redemptionID: redemptionID, as: resolution)
        }
    }

    /// Handles a `channel.bits.use` event. Below the configured minimum the
    /// cheer is ignored. When boosting is enabled and the cheerer already has a
    /// queued song, that song jumps to the front; otherwise the cheer message
    /// (cheermote tokens stripped) is treated as a new request.
    private func handleBitsUse(_ payload: [String: Any]) {
        let defaults = UserDefaults.standard
        guard
            defaults.bool(forKey: AppConstants.UserDefaults.songRequestBitsEnabled),
            let event = payload["event"] as? [String: Any]
        else { return }

        let bits = (event["bits"] as? Int) ?? 0
        guard bits > 0, bits >= bitsMinimumSetting() else { return }

        let userName = ((event["user_name"] as? String) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !userName.isEmpty else { return }

        let boostEnabled = defaults.bool(
            forKey: AppConstants.UserDefaults.songRequestBitsBoostEnabled)
        let query = Self.cleanBitsMessage(event["message"] as? [String: Any])

        Task { @MainActor in
            guard let service = self.songRequestService else { return }

            if boostEnabled, let boosted = service.queue.boost(username: userName) {
                self.sendMessage(
                    "@\(userName) boosted \"\(boosted.title)\" to the front of the queue! (\(bits) bits)")
                return
            }

            guard !query.isEmpty else {
                if boostEnabled {
                    self.sendMessage(
                        "@\(userName) no song of yours to boost — include a song name in your cheer to request one.")
                }
                return
            }

            let result = await service.processRequest(
                query: query, username: userName, source: .bits(amount: bits))
            self.sendMessage(self.bitsOutcomeMessage(for: result, username: userName))
        }
    }

    // MARK: - Redemption Helpers

    /// Resolves a channel-point redemption via Helix, logging any failure.
    private func resolveRedemption(
        _ credentials: TwitchChannelPointsService.Credentials?,
        rewardID: String,
        redemptionID: String,
        as resolution: TwitchChannelPointsService.Resolution
    ) async {
        guard let credentials else { return }
        do {
            try await channelPointsService.resolveRedemption(
                credentials: credentials,
                rewardID: rewardID,
                redemptionID: redemptionID,
                as: resolution)
        } catch {
            Log.error(
                "TwitchChatService: Failed to \(resolution.rawValue) redemption - \(error.localizedDescription)",
                category: "Twitch")
        }
    }

    /// Maps a request result to a chat message and a redemption resolution.
    private func redemptionOutcome(
        for result: SongRequestService.RequestResult,
        username: String
    ) -> (message: String, resolution: TwitchChannelPointsService.Resolution) {
        switch result {
        case let .added(item, position):
            return (
                "@\(username) added \"\(item.title)\" by \(item.artist) — #\(position) in queue",
                .fulfilled)
        case let .queueFull(max):
            return ("@\(username) the queue is full (\(max)). Points refunded.", .canceled)
        case let .userLimitReached(max):
            return (
                "@\(username) you already have \(max) songs queued. Points refunded.", .canceled)
        case .alreadyInQueue:
            return ("@\(username) that song is already queued. Points refunded.", .canceled)
        case .blocked:
            return ("@\(username) that song is on the blocklist. Points refunded.", .canceled)
        case let .notFound(query):
            let truncated = query.count > 30 ? String(query.prefix(30)) + "..." : query
            return ("@\(username) no results for \"\(truncated)\". Points refunded.", .canceled)
        case .linkNotFound:
            return (
                "@\(username) couldn't find that on Apple Music. Points refunded.", .canceled)
        case .notAuthorized:
            return (
                "@\(username) song requests aren't available right now. Points refunded.",
                .canceled)
        case let .error(message):
            return ("@\(username) \(message) Points refunded.", .canceled)
        }
    }

    /// Builds a chat reply for a bit-cheer song request.
    private func bitsOutcomeMessage(
        for result: SongRequestService.RequestResult,
        username: String
    ) -> String {
        switch result {
        case let .added(item, position):
            return "@\(username) added \"\(item.title)\" by \(item.artist) — #\(position) in queue. Thanks for the bits!"
        case let .queueFull(max):
            return "@\(username) the queue is full (\(max)/\(max)). Try again soon!"
        case let .userLimitReached(max):
            return "@\(username) you already have \(max) songs queued."
        case .alreadyInQueue:
            return "@\(username) that song is already in the queue."
        case .blocked:
            return "@\(username) sorry, that song/artist is on the blocklist."
        case let .notFound(query):
            let truncated = query.count > 30 ? String(query.prefix(30)) + "..." : query
            return "@\(username) no results for \"\(truncated)\"."
        case .linkNotFound:
            return "@\(username) couldn't find that on Apple Music."
        case .notAuthorized:
            return "@\(username) song requests aren't available right now."
        case let .error(message):
            return "@\(username) \(message)"
        }
    }

    /// Current broadcaster credentials for Helix channel-point calls, or `nil`
    /// when any credential is missing.
    private func currentChannelPointCredentials() -> TwitchChannelPointsService.Credentials? {
        guard let broadcasterID, let token = oauthToken, let clientID,
            !broadcasterID.isEmpty, !token.isEmpty, !clientID.isEmpty
        else { return nil }
        return TwitchChannelPointsService.Credentials(
            broadcasterID: broadcasterID, token: token, clientID: clientID)
    }

    /// Configured channel-point cost for the managed reward (default 500).
    private func channelPointsCostSetting() -> Int {
        let stored = UserDefaults.standard.integer(
            forKey: AppConstants.UserDefaults.songRequestChannelPointsCost)
        return stored > 0 ? stored : 500
    }

    /// Configured minimum bits required to trigger a request (default 100).
    private func bitsMinimumSetting() -> Int {
        let stored = UserDefaults.standard.integer(
            forKey: AppConstants.UserDefaults.songRequestBitsMinimum)
        return stored > 0 ? stored : 100
    }

    /// Persists the redemption integration health for the settings UI.
    private func setRedemptionStatus(_ status: RedemptionStatus) {
        UserDefaults.standard.set(
            status.rawValue, forKey: AppConstants.UserDefaults.songRequestRedemptionStatus)
    }

    /// Extracts the viewer's song query from a `channel.bits.use` message,
    /// dropping cheermote tokens.
    static func cleanBitsMessage(_ message: [String: Any]?) -> String {
        guard let message else { return "" }

        if let fragments = message["fragments"] as? [[String: Any]] {
            let textParts = fragments.compactMap { fragment -> String? in
                guard (fragment["type"] as? String) == "text" else { return nil }
                return fragment["text"] as? String
            }
            let joined = textParts.joined().trimmingCharacters(in: .whitespacesAndNewlines)
            if !joined.isEmpty { return joined }
        }

        let raw = (message["text"] as? String) ?? ""
        return stripLeadingCheermotes(raw)
    }

    /// Removes leading `Cheer<amount>` tokens from a raw cheer message.
    static func stripLeadingCheermotes(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard
            let regex = try? NSRegularExpression(pattern: "^(?:[Cc]heer[0-9]+\\s*)+"),
            let match = regex.firstMatch(
                in: trimmed, range: NSRange(trimmed.startIndex..., in: trimmed)),
            let range = Range(match.range, in: trimmed)
        else {
            return trimmed
        }
        var stripped = trimmed
        stripped.removeSubrange(range)
        return stripped.trimmingCharacters(in: .whitespacesAndNewlines)
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
