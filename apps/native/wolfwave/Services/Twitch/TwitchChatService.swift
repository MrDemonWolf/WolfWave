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
/// - EventSub subscriptions (channel.chat.message, channel.poll.end, redemptions)
/// - Chat message routing to bot commands
/// - Chat message sending and replies
/// - Token validation and user identity resolution
///
/// Concurrency:
/// - `actor`-isolated. All mutable state lives inside the actor's isolation
///   domain; no locks, no `nonisolated(unsafe)` properties.
/// - Side-effect "callbacks" (chat messages, connection state, vote-skip poll
///   results) are surfaced as `AsyncStream`s on the `nonisolated` interface.
/// - Track-info providers (`!song`, `!last`, `!stats`) are async closures;
///   AppDelegate hops to `@MainActor` inside them.
/// - Rate-limit bookkeeping lives in a nested `RateLimiter` actor so heavy
///   request flows don't serialize the entire chat-message pipeline.
///
/// Usage:
/// ```swift
/// let service = TwitchChatService()
/// try await service.connectToChannel(
///     channelName: "streamer",
///     token: oauthToken,
///     clientID: clientID
/// )
/// try await service.sendMessage("Hello, chat!")
/// ```
actor TwitchChatService {

    // MARK: - Nested Types

    struct ChatMessage: Sendable {
        let messageID: String
        let username: String
        let userID: String
        let message: String
        let channel: String
        let badges: [Badge]
        let reply: Reply?

        struct Badge: Sendable {
            let setID: String
            let id: String
            let info: String
        }

        struct Reply: Sendable {
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

    struct BotIdentity: Sendable {
        let userID: String
        let login: String
        let displayName: String
    }

    /// Result of checking whether a Twitch channel exists.
    enum ChannelValidationResult: Sendable {
        case exists
        case notFound
        case authenticationFailed
        case error(String)
    }

    /// Tuple-style payload posted on a `channel.poll.end` for a vote-skip poll.
    struct SkipPollResult: Sendable {
        let skipVotes: Int
        let keepVotes: Int
    }

    /// Rate-limit bucket state for one Helix endpoint.
    struct RateLimitState: Sendable {
        var remaining: Int = 0
        var resetTime: TimeInterval = 0
        var limit: Int = 0
    }

    /// Pending message awaiting retry.
    private struct PendingMessage: Sendable {
        let message: String
        let parentMessageID: String?
        var attempts: Int
    }

    // MARK: - Static Constants

    nonisolated static let connectionStateChanged =
        NSNotification.Name(AppConstants.Notifications.twitchConnectionStateChanged)

    /// Title used for vote-skip Twitch polls. Also the match key for `channel.poll.end`.
    nonisolated static let skipPollTitle = "Skip the current song?"
    /// "Skip" choice label on a vote-skip poll.
    nonisolated static let skipPollSkipChoice = "Skip"
    /// "Keep playing" choice label on a vote-skip poll.
    nonisolated static let skipPollKeepChoice = "Keep playing"

    // MARK: - Configuration

    private let apiBaseURL = AppConstants.Twitch.apiBaseURL
    /// `BotCommandDispatcher` is `@MainActor` (project default). The actor
    /// holds it as `nonisolated` (it's auto-Sendable since it's MainActor) and
    /// hops to `MainActor.run` for every call into it.
    nonisolated let commandDispatcher: BotCommandDispatcher
    private let channelPointsService = TwitchChannelPointsService()
    private let rateLimiter = RateLimiter()

    private let urlSession: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 60
        config.timeoutIntervalForResource = 300
        config.waitsForConnectivity = true
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: config)
    }()

    private let maxReconnectionAttempts = AppConstants.Twitch.maxReconnectionAttempts
    private let maxNetworkReconnectCycles = AppConstants.Twitch.maxNetworkReconnectCycles
    private let maxMessageRetries = AppConstants.Twitch.maxMessageRetries

    // MARK: - WebSocket / Session

    private var webSocketTask: URLSessionWebSocketTask?
    private var sessionID: String?
    private var receiveTask: Task<Void, Never>?

    // MARK: - Credentials

    private var broadcasterID: String?
    private var botID: String?
    private var oauthToken: String?
    private var clientID: String?
    private var botUsername: String?

    /// Live `SongRequestService`, used by the channel-point and bit redemption
    /// handlers. Set once by `AppDelegate` at startup via `setSongRequestService(_:)`.
    private var songRequestService: SongRequestService?

    // MARK: - Toggles

    var shouldSendConnectionMessageOnSubscribe = true
    var debugLoggingEnabled = false
    private(set) var commandsEnabled = true

    // MARK: - Track-Info Providers (async, nonisolated)

    /// Providers live in a nonisolated lock-protected registry so the sync
    /// dispatcher bridge (`runSync`) can read them without re-entering the
    /// actor's mailbox — re-entering while the actor's executor is blocked on
    /// `runSync`'s semaphore would deadlock.
    nonisolated private let providers = ProviderRegistry()

    // MARK: - UserDefaults-derived (read on demand)

    /// Whether the current song command is enabled (computed from UserDefaults on each access).
    nonisolated var currentSongCommandEnabled: Bool {
        UserDefaults.standard.object(forKey: AppConstants.UserDefaults.currentSongCommandEnabled) as? Bool ?? false
    }

    /// Whether the last song command is enabled (computed from UserDefaults on each access).
    nonisolated var lastSongCommandEnabled: Bool {
        UserDefaults.standard.object(forKey: AppConstants.UserDefaults.lastSongCommandEnabled) as? Bool ?? false
    }

    /// Whether the `!stats` command should respond — both the Stats feature and
    /// the command itself must be enabled (computed from UserDefaults).
    nonisolated var statsCommandActive: Bool {
        let stats = UserDefaults.standard.bool(forKey: AppConstants.UserDefaults.statsEnabled)
        let command = UserDefaults.standard.bool(forKey: AppConstants.UserDefaults.statsCommandEnabled)
        return stats && command
    }

    // MARK: - Connection State

    private var _connected = false {
        didSet { isConnectedSnapshot.set(_connected) }
    }
    private var hasSentConnectionMessage = false
    private var streamLive = false {
        didSet { streamLiveSnapshot.set(streamLive) }
    }

    /// Nonisolated mirror of `_connected` so MainActor UI code (status chips,
    /// menu bar enable state) can read it without `await`.
    nonisolated let isConnectedSnapshot = AtomicBool()

    /// Nonisolated mirror of `streamLive` so the synchronous dispatcher bridge
    /// (`!stats` enable check) can read it without re-entering the actor.
    nonisolated private let streamLiveSnapshot = AtomicBool()

    var isConnected: Bool { _connected }

    /// Whether the broadcaster's stream is currently live.
    ///
    /// Maintained by the `stream.online` / `stream.offline` EventSub events and
    /// seeded by a one-shot Helix check on connect. The `!stats` command stays
    /// silent unless this is `true`.
    var isStreamLive: Bool { streamLive }

    private func setConnected(_ value: Bool) {
        _connected = value
    }

    // MARK: - Disconnect / Network State

    private var isProcessingDisconnect = false
    private var networkPathMonitor: NWPathMonitor?
    private let networkMonitorQueue = DispatchQueue(
        label: "com.mrdemonwolf.wolfwave.networkmonitor")
    private var isNetworkReachable = true

    // MARK: - Reconnection State

    private var reconnectionAttempts = 0
    private var reconnectTask: Task<Void, Never>?
    private var sessionWelcomeTask: Task<Void, Never>?
    private var connectionMessageTask: Task<Void, Never>?

    /// Tracks total network-triggered reconnect cycles to prevent infinite loops
    /// when the network path flaps repeatedly.
    private var networkReconnectCycles = 0
    private var lastNetworkReconnectTime: TimeInterval = 0

    private var reconnectChannelName: String?
    private var reconnectToken: String?
    private var reconnectClientID: String?

    // MARK: - Pending Messages

    private var pendingMessages: [PendingMessage] = []
    private var pendingRetryTask: Task<Void, Never>?

    // MARK: - AsyncStream Outputs

    /// Stream of chat messages received via EventSub `channel.chat.message`.
    nonisolated let chatMessages: AsyncStream<ChatMessage>
    /// Stream of connection state transitions (`true` = connected).
    nonisolated let connectionStateChanges: AsyncStream<Bool>
    /// Stream of finished vote-skip poll tallies.
    nonisolated let skipPollResults: AsyncStream<SkipPollResult>

    private let chatMessagesContinuation: AsyncStream<ChatMessage>.Continuation
    private let connectionStateContinuation: AsyncStream<Bool>.Continuation
    private let skipPollResultsContinuation: AsyncStream<SkipPollResult>.Continuation

    // MARK: - Init / Deinit

    /// Marked `@MainActor` so `BotCommandDispatcher()` (a MainActor type under
    /// project default isolation) can be constructed at init time. AppDelegate
    /// runs on MainActor; tests call from MainActor (Swift Testing) or wrap.
    @MainActor init() {
        let chat = AsyncStream.makeStream(of: ChatMessage.self, bufferingPolicy: .unbounded)
        let connection = AsyncStream.makeStream(of: Bool.self, bufferingPolicy: .unbounded)
        let skip = AsyncStream.makeStream(of: SkipPollResult.self, bufferingPolicy: .unbounded)

        self.chatMessages = chat.stream
        self.chatMessagesContinuation = chat.continuation
        self.connectionStateChanges = connection.stream
        self.connectionStateContinuation = connection.continuation
        self.skipPollResults = skip.stream
        self.skipPollResultsContinuation = skip.continuation
        self.commandDispatcher = BotCommandDispatcher()
    }

    deinit {
        // Synchronous cleanup only — actor isolation forbids awaits in deinit.
        sessionWelcomeTask?.cancel()
        reconnectTask?.cancel()
        receiveTask?.cancel()
        connectionMessageTask?.cancel()
        pendingRetryTask?.cancel()
        networkPathMonitor?.cancel()
        webSocketTask?.cancel(with: .goingAway, reason: nil)
        chatMessagesContinuation.finish()
        connectionStateContinuation.finish()
        skipPollResultsContinuation.finish()
    }

    // MARK: - Wiring (called once at app startup)

    /// Wire the song request service into the command dispatcher.
    /// Hops to `MainActor` because `BotCommandDispatcher` is `@MainActor`.
    func setSongRequestService(callback: @escaping @Sendable () -> SongRequestService?) async {
        await MainActor.run { commandDispatcher.setSongRequestService(callback: callback) }
    }

    /// Wire the song request queue into the command dispatcher.
    func setSongRequestQueue(callback: @escaping @Sendable () -> SongRequestQueue?) async {
        await MainActor.run { commandDispatcher.setSongRequestQueue(callback: callback) }
    }

    /// Wire the skip-vote manager into the command dispatcher.
    func setSkipVoteManager(callback: @escaping @Sendable () -> SkipVoteManager?) async {
        await MainActor.run { commandDispatcher.setSkipVoteManager(callback: callback) }
    }

    /// Set the live `SongRequestService` used by redemption handlers.
    func setSongRequestServiceReference(_ service: SongRequestService?) {
        self.songRequestService = service
    }

    /// Provide the `!song` lookup. Called from MainActor by AppDelegate.
    nonisolated func setCurrentSongInfoProvider(_ provider: (@Sendable () async -> String)?) {
        providers.setCurrent(provider)
    }

    /// Provide the `!last` lookup.
    nonisolated func setLastSongInfoProvider(_ provider: (@Sendable () async -> String)?) {
        providers.setLast(provider)
    }

    /// Provide the `!stats` lookup.
    nonisolated func setStatsInfoProvider(_ provider: (@Sendable () async -> String)?) {
        providers.setStats(provider)
    }

    /// Toggle whether bot commands are processed.
    func setCommandsEnabled(_ enabled: Bool) {
        self.commandsEnabled = enabled
    }

    /// Toggle verbose debug logging.
    func setDebugLoggingEnabled(_ enabled: Bool) {
        self.debugLoggingEnabled = enabled
    }

    /// Toggle whether the connection confirmation message is sent on subscribe.
    func setShouldSendConnectionMessageOnSubscribe(_ value: Bool) {
        self.shouldSendConnectionMessageOnSubscribe = value
    }

    // MARK: - Rate Limiter (nested actor)

    /// Tracks Helix per-endpoint rate-limit headers and waits for the bucket to
    /// reset when saturated. Lives in its own isolation domain so heavy API
    /// usage doesn't block the chat-message receive loop.
    actor RateLimiter {
        private var states: [String: RateLimitState] = [:]

        /// Returns the seconds to wait before retrying when the local accountant
        /// believes `endpoint` is currently saturated, or `nil` if no wait is needed.
        func waitTimeIfRateLimited(endpoint: String) -> TimeInterval? {
            guard let state = states[endpoint] else { return nil }
            let now = Date().timeIntervalSince1970
            let timeUntilReset = state.resetTime - now
            if state.remaining <= 0 && timeUntilReset > 0 {
                return timeUntilReset
            }
            return nil
        }

        /// Sleeps until `endpoint`'s bucket has capacity. Loops in case multiple
        /// callers race for the same window.
        func awaitCapacity(endpoint: String) async {
            while let wait = waitTimeIfRateLimited(endpoint: endpoint) {
                try? await Task.sleep(for: .seconds(wait))
            }
        }

        /// Records Twitch's `Ratelimit-*` headers after a Helix response.
        func updateRateLimitState(endpoint: String, from headers: [AnyHashable: Any]) {
            var state = states[endpoint] ?? RateLimitState()

            if let remaining = headers["Ratelimit-Remaining"] as? String,
               let remainingInt = Int(remaining) {
                state.remaining = remainingInt
            }
            if let reset = headers["Ratelimit-Reset"] as? String,
               let resetInt = TimeInterval(reset) {
                state.resetTime = resetInt
            }
            if let limit = headers["Ratelimit-Limit"] as? String,
               let limitInt = Int(limit) {
                state.limit = limitInt
            }

            states[endpoint] = state

            if state.remaining <= 5 && state.remaining > 0 {
                Log.warn(
                    "TwitchChatService: Approaching rate limit on \(endpoint): \(state.remaining)/\(state.limit) remaining",
                    category: "Twitch")
            }
        }
    }

    // MARK: - Network Monitoring

    /// Starts monitoring network connectivity and sets up automatic reconnection.
    private func startNetworkMonitoring() {
        let monitor = NWPathMonitor()
        networkPathMonitor = monitor

        monitor.pathUpdateHandler = { [weak self] path in
            Task { await self?.handleNetworkPathChange(path) }
        }

        monitor.start(queue: networkMonitorQueue)
    }

    /// Stops network connectivity monitoring.
    private func stopNetworkMonitoring() {
        networkPathMonitor?.cancel()
        networkPathMonitor = nil
    }

    /// Handles network path changes and triggers reconnection if needed.
    ///
    /// Rate-limits network-triggered reconnects to prevent infinite loops when
    /// the network path flaps rapidly between available/unavailable states.
    private func handleNetworkPathChange(_ path: NWPath) async {
        let isReachable = path.status == .satisfied
        let wasReachable = isNetworkReachable
        isNetworkReachable = isReachable

        if !wasReachable && isReachable {
            let now = Date().timeIntervalSince1970
            // Reset cycle counter if enough time has passed
            if now - lastNetworkReconnectTime > AppConstants.Twitch.networkReconnectCooldown {
                networkReconnectCycles = 0
            }

            guard networkReconnectCycles < maxNetworkReconnectCycles else {
                Log.error(
                    "TwitchChatService: Max network reconnect cycles reached, not reconnecting",
                    category: "Twitch")
                return
            }

            networkReconnectCycles += 1
            lastNetworkReconnectTime = now
            // Reset per-attempt counter for the new cycle
            reconnectionAttempts = 0
            scheduleReconnect()
        } else if wasReachable && !isReachable {
            Log.warn("TwitchChatService: Network unavailable, disconnecting", category: "Twitch")
            disconnectFromEventSub()
        }
    }

    // MARK: - Reconnection

    /// Schedules a reconnection attempt with exponential backoff. Cancels any
    /// existing scheduled attempt so we never have two pending at once.
    private func scheduleReconnect() {
        guard let channelName = reconnectChannelName,
              let token = reconnectToken,
              let clientID = reconnectClientID else {
            Log.debug("TwitchChatService: Cannot reconnect - missing credentials", category: "Twitch")
            return
        }

        let attempts = reconnectionAttempts

        if attempts >= maxReconnectionAttempts {
            Log.error(
                "TwitchChatService: Max reconnection attempts reached (\(maxReconnectionAttempts))",
                category: "Twitch")
            // Reset attempts after hitting the limit to allow manual reconnection later
            reconnectionAttempts = 0
            return
        }

        // Exponential backoff: 1s, 2s, 4s, 8s, 16s
        let delaySeconds = min(pow(2.0, Double(attempts)), 16.0)

        Log.info(
            "TwitchChatService: Scheduling reconnection attempt \(attempts + 1)/\(maxReconnectionAttempts) in \(String(format: "%.1f", delaySeconds))s",
            category: "Twitch")

        reconnectTask?.cancel()
        reconnectTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delaySeconds))
            if Task.isCancelled { return }
            await self?.attemptReconnect(channelName: channelName, token: token, clientID: clientID)
        }
    }

    private func attemptReconnect(channelName: String, token: String, clientID: String) async {
        do {
            try await connectToChannel(channelName: channelName, token: token, clientID: clientID)
            reconnectionAttempts = 0
            Log.info("TwitchChatService: Reconnection successful", category: "Twitch")
        } catch {
            reconnectionAttempts += 1
            Log.warn(
                "TwitchChatService: Reconnection attempt failed: \(error.localizedDescription)",
                category: "Twitch")
            if reconnectionAttempts < maxReconnectionAttempts && isNetworkReachable {
                scheduleReconnect()
            } else if !isNetworkReachable {
                Log.info(
                    "TwitchChatService: Network no longer reachable, stopping reconnection attempts",
                    category: "Twitch")
            }
        }
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
    ) async throws {
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
        self.hasSentConnectionMessage = false
        self.isProcessingDisconnect = false

        // Wire dispatcher providers. The dispatcher is `@MainActor`, so wiring
        // hops to MainActor. The sync provider closures read the async
        // providers through a nonisolated `ProviderRegistry` + `runSync`
        // semaphore bridge — that's safe because dispatcher.processMessage is
        // also called via MainActor.run, never re-entering this actor.
        let providers = self.providers
        let streamLiveSnapshot = self.streamLiveSnapshot
        let currentSongCommandEnabled: @Sendable () -> Bool = { [weak self] in
            self?.currentSongCommandEnabled ?? false
        }
        let lastSongCommandEnabled: @Sendable () -> Bool = { [weak self] in
            self?.lastSongCommandEnabled ?? false
        }
        let statsCommandActiveAndLive: @Sendable () -> Bool = { [weak self] in
            guard let self else { return false }
            guard self.statsCommandActive else { return false }
            return streamLiveSnapshot.value
        }
        await MainActor.run {
            commandDispatcher.setCurrentSongInfo {
                guard let provider = providers.current() else { return "No track currently playing" }
                return Self.runSync { await provider() } ?? "No track currently playing"
            }
            commandDispatcher.setLastSongInfo {
                guard let provider = providers.last() else { return "No previous track available" }
                return Self.runSync { await provider() } ?? "No previous track available"
            }
            commandDispatcher.setStatsInfo {
                guard let provider = providers.stats() else { return "No listening stats yet" }
                return Self.runSync { await provider() } ?? "No listening stats yet"
            }
            commandDispatcher.setCurrentSongCommandEnabled(callback: currentSongCommandEnabled)
            commandDispatcher.setLastSongCommandEnabled(callback: lastSongCommandEnabled)
            commandDispatcher.setStatsCommandEnabled(callback: statsCommandActiveAndLive)
        }

        // Don't set connected state here - wait for EventSub session_welcome
        connectToEventSub()
    }

    /// Connects to a Twitch channel by name, resolving usernames to IDs.
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

        guard let botUserID else { throw ConnectionError.invalidCredentials }

        let broadcasterUserID = try await resolveUsername(
            channelName, token: token, clientID: clientID)

        guard !broadcasterUserID.isEmpty else {
            throw ConnectionError.networkError("Could not resolve channel name to user ID")
        }

        try await joinChannel(
            broadcasterID: broadcasterUserID,
            botID: botUserID,
            token: token,
            clientID: clientID)

        // Store credentials for automatic reconnection
        reconnectChannelName = channelName
        reconnectToken = token
        reconnectClientID = clientID
        reconnectionAttempts = 0
        networkReconnectCycles = 0

        if networkPathMonitor == nil {
            startNetworkMonitoring()
        }

        Log.info("TwitchChatService: Connected to channel \(channelName)", category: "Twitch")
    }

    /// Resolves and stores the bot's identity (user ID and username).
    func resolveBotIdentity(token: String, clientID: String) async throws {
        guard !token.isEmpty else { throw ConnectionError.invalidCredentials }
        guard !clientID.isEmpty else { throw ConnectionError.missingClientID }

        let identity = try await fetchBotIdentity(token: token, clientID: clientID)
        let resolvedUsername = identity.displayName.isEmpty ? identity.login : identity.displayName

        try KeychainService.saveTwitchUsername(resolvedUsername)
        try KeychainService.saveTwitchBotUserID(identity.userID)
    }

    /// Static method to resolve bot identity without an instance.
    static func resolveBotIdentityStatic(token: String, clientID: String) async throws {
        guard !token.isEmpty else { throw ConnectionError.invalidCredentials }
        guard !clientID.isEmpty else { throw ConnectionError.missingClientID }

        // `init()` is `@MainActor`; hop to construct.
        let service = await MainActor.run { TwitchChatService() }
        let identity = try await service.fetchBotIdentity(token: token, clientID: clientID)
        let resolvedUsername = identity.displayName.isEmpty ? identity.login : identity.displayName

        try KeychainService.saveTwitchUsername(resolvedUsername)
        try KeychainService.saveTwitchBotUserID(identity.userID)
    }

    /// Resolves the Twitch Client ID from Info.plist (set via Config.xcconfig at build time).
    nonisolated static func resolveClientID() -> String? {
        if let plistValue = Bundle.main.object(forInfoDictionaryKey: "TWITCH_CLIENT_ID") as? String,
           !plistValue.isEmpty,
           !plistValue.hasPrefix("$(") {
            return plistValue
        }
        if let env = ProcessInfo.processInfo.environment["TWITCH_CLIENT_ID"], !env.isEmpty {
            return env
        }
        return nil
    }

    /// Fetches the bot's identity (user ID and usernames) from Twitch.
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
            if let connectionError = error as? ConnectionError { throw connectionError }
            Log.error("TwitchChatService: Failed to decode user identity JSON - \(error.localizedDescription)", category: "Twitch")
            throw ConnectionError.networkError("Unable to decode user identity JSON: \(error.localizedDescription)")
        }

        guard let dataArray = json["data"] as? [[String: Any]],
              let first = dataArray.first,
              let userID = first["id"] as? String,
              let login = first["login"] as? String else {
            Log.error("TwitchChatService: Failed to parse user identity from response", category: "Twitch")
            throw ConnectionError.networkError("Unable to parse user identity")
        }

        let displayName = first["display_name"] as? String ?? login

        botID = userID
        botUsername = displayName

        return BotIdentity(userID: userID, login: login, displayName: displayName)
    }

    /// Leaves the current channel and disconnects from EventSub.
    func leaveChannel() {
        Log.info("TwitchChatService:leaveChannel() called", category: "Twitch")
        isProcessingDisconnect = true

        disconnectFromEventSub()

        // Clear reconnection credentials
        reconnectChannelName = nil
        reconnectToken = nil
        reconnectClientID = nil
        reconnectionAttempts = 0
        reconnectTask?.cancel()
        reconnectTask = nil

        broadcasterID = nil
        botID = nil
        oauthToken = nil
        clientID = nil
        hasSentConnectionMessage = false

        setConnected(false)
        NotificationCenter.default.post(
            name: TwitchChatService.connectionStateChanged,
            object: nil,
            userInfo: ["isConnected": false]
        )
        connectionStateContinuation.yield(false)

        Log.info("TwitchChatService: Left channel", category: "Twitch")
    }

    /// Validates an OAuth token with Twitch and verifies required scopes.
    func validateToken(
        _ token: String,
        requiredScopes: [String] = ["user:read:chat", "user:write:chat"]
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
                    Log.warn("TwitchChatService: Stored OAuth token is invalid or expired", category: "Twitch")
                } else {
                    Log.warn("TwitchChatService: Token validate HTTP \(http.statusCode)", category: "Twitch")
                }
                return false
            }

            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                Log.warn("TwitchChatService: Could not parse token validate response", category: "Twitch")
                return false
            }

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
    func sendConnectionMessage() {
        connectionMessageTask?.cancel()
        connectionMessageTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(AppConstants.Twitch.connectionMessageDelay))
            if Task.isCancelled { return }
            await self?.sendConnectionMessageIfNeeded()
        }
    }

    private func sendConnectionMessageIfNeeded() async {
        guard !hasSentConnectionMessage else { return }
        hasSentConnectionMessage = true
        await sendMessage(AppConstants.Twitch.connectionMessage)
    }

    // MARK: - Message Sending

    /// Sends a message to the current channel.
    func sendMessage(_ message: String) async {
        await sendMessage(message, replyTo: nil)
    }

    /// Sends a message that replies to another message.
    func sendMessage(_ message: String, replyTo parentMessageID: String?) async {
        guard let broadcasterID,
              let botID,
              let token = oauthToken,
              let clientID else {
            Log.warn("TwitchChatService: Not connected, queuing message for retry", category: "Twitch")
            queueMessageForRetry(message: message, parentMessageID: parentMessageID, attempts: 0)
            return
        }

        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let finalMessage = trimmed.truncatedForChat()

        var body: [String: Any] = [
            "broadcaster_id": broadcasterID,
            "sender_id": botID,
            "message": finalMessage,
        ]
        if let parentMessageID, !parentMessageID.isEmpty {
            body["reply_parent_message_id"] = parentMessageID
        }

        do {
            let data = try await sendAPIRequest(
                method: "POST",
                endpoint: "/chat/messages",
                body: body,
                token: token,
                clientID: clientID)
            do {
                guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let dataArray = json["data"] as? [[String: Any]],
                      let messageData = dataArray.first else {
                    Log.warn("TwitchChatService: Could not parse send-message response", category: "Twitch")
                    return
                }
                let isSent = messageData["is_sent"] as? Bool ?? false
                if !isSent {
                    Log.warn("TwitchChatService: Message dropped by Twitch", category: "Twitch")
                }
            } catch {
                Log.warn(
                    "TwitchChatService: Failed to decode send-message response - \(error.localizedDescription)",
                    category: "Twitch")
            }
        } catch {
            Log.error(
                "TwitchChatService: Failed to send message - \(error.localizedDescription)",
                category: "Twitch")
            queueMessageForRetry(message: message, parentMessageID: parentMessageID, attempts: 0)
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
        pendingMessages.append(pending)

        let delay = pow(2.0, Double(attempts))
        Log.debug(
            "TwitchChatService: Scheduling message retry \(attempts + 1)/\(maxMessageRetries) in \(delay)s",
            category: "Twitch")

        Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            await self?.retryPendingMessages()
        }
    }

    /// Retries pending messages from the queue.
    private func retryPendingMessages() async {
        guard !pendingMessages.isEmpty else { return }
        let message = pendingMessages.removeFirst()

        // Check if we have valid credentials now
        guard broadcasterID != nil, botID != nil, oauthToken != nil, clientID != nil else {
            queueMessageForRetry(
                message: message.message,
                parentMessageID: message.parentMessageID,
                attempts: message.attempts)
            return
        }

        await sendMessage(message.message, replyTo: message.parentMessageID)
    }

    // MARK: - Message Parsing

    /// Parses and handles an incoming message from EventSub.
    func handleEventSubMessage(_ json: [String: Any]) async {
        if isProcessingDisconnect { return }

        guard let event = json["event"] as? [String: Any] else { return }

        let messageID = (event["message_id"] as? String ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let username = (event["chatter_user_name"] as? String ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let userID = (event["chatter_user_id"] as? String ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let broadcasterID = event["broadcaster_user_id"] as? String ?? ""
        let messageText = event["message"] as? [String: Any]
        let text = (messageText?["text"] as? String ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !messageID.isEmpty, !username.isEmpty, !userID.isEmpty, !text.isEmpty else { return }

        var badges: [ChatMessage.Badge] = []
        if let badgeArray = event["badges"] as? [[String: Any]] {
            for badge in badgeArray {
                if let setID = badge["set_id"] as? String,
                   let id = badge["id"] as? String,
                   !setID.isEmpty, !id.isEmpty {
                    let info = (badge["info"] as? String ?? "")
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    badges.append(ChatMessage.Badge(setID: setID, id: id, info: info))
                }
            }
        }

        var reply: ChatMessage.Reply?
        if let replyObj = event["reply"] as? [String: Any] {
            let parentMessageID = (replyObj["parent_message_id"] as? String ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let parentBody = (replyObj["parent_message_body"] as? String ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let parentUserID = (replyObj["parent_user_id"] as? String ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let parentUsername = (replyObj["parent_user_name"] as? String ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)

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

            let asyncReply: @Sendable (String) -> Void = { [weak self] response in
                guard let self else { return }
                Task { await self.sendMessage(response, replyTo: messageID) }
            }

            // BotCommandDispatcher is `@MainActor` — hop to call it.
            let response: String? = await MainActor.run {
                commandDispatcher.processMessage(
                    text,
                    userID: userID,
                    isModerator: bypassCooldown,
                    context: context,
                    asyncReply: asyncReply
                )
            }
            if let response {
                await sendMessage(response, replyTo: messageID)
            }
        }

        chatMessagesContinuation.yield(chatMessage)
    }

    // MARK: - API Requests

    /// Sends an API request to the Twitch Helix API.
    ///
    /// Blocks (via `Task.sleep`) when the local rate-limit accountant says the
    /// endpoint is saturated; records returned `Ratelimit-*` headers.
    private func sendAPIRequest(
        method: String,
        endpoint: String,
        body: [String: Any]?,
        token: String,
        clientID: String
    ) async throws -> Data {
        // Wait for rate-limit capacity before sending.
        if let waitTime = await rateLimiter.waitTimeIfRateLimited(endpoint: endpoint) {
            Log.info(
                "TwitchChatService: Request queued due to rate limit. Retry after \(String(format: "%.1f", waitTime))s",
                category: "Twitch")
            await rateLimiter.awaitCapacity(endpoint: endpoint)
        }

        guard let url = URL(string: apiBaseURL + endpoint) else {
            throw ConnectionError.networkError("Invalid URL")
        }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue(clientID, forHTTPHeaderField: "Client-ID")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        if let body {
            do {
                request.httpBody = try JSONSerialization.data(withJSONObject: body)
            } catch {
                Log.error(
                    "TwitchChatService: Failed to serialize request body - \(error.localizedDescription)",
                    category: "Twitch")
                throw ConnectionError.networkError("Failed to serialize request body")
            }
        }

        let (data, response) = try await URLSession.shared.data(for: request)

        if let httpResponse = response as? HTTPURLResponse {
            await rateLimiter.updateRateLimitState(
                endpoint: endpoint, from: httpResponse.allHeaderFields)

            if !(200..<300).contains(httpResponse.statusCode) {
                let responseText = String(data: data, encoding: .utf8) ?? "No response body"
                Log.warn(
                    "TwitchChatService: API \(endpoint) returned HTTP \(httpResponse.statusCode) - \(responseText)",
                    category: "Twitch")
            }
        }

        return data
    }

    // MARK: - WebSocket Management

    /// Connects to the Twitch EventSub WebSocket endpoint.
    private func connectToEventSub() {
        guard let url = URL(string: "wss://eventsub.wss.twitch.tv/ws") else {
            Log.error("TwitchChatService: Invalid EventSub URL", category: "Twitch")
            setConnected(false)
            NotificationCenter.default.post(
                name: TwitchChatService.connectionStateChanged,
                object: nil,
                userInfo: ["isConnected": false]
            )
            connectionStateContinuation.yield(false)
            return
        }

        let task = urlSession.webSocketTask(with: url)
        webSocketTask = task

        Log.info("TwitchChatService: Starting EventSub WebSocket connection", category: "Twitch")
        task.resume()

        startSessionWelcomeTimeout()
        startReceiveLoop()
    }

    /// Starts a timeout task that fires if `session_welcome` doesn't arrive in time.
    private func startSessionWelcomeTimeout() {
        sessionWelcomeTask?.cancel()
        sessionWelcomeTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(AppConstants.Twitch.sessionWelcomeTimeout))
            if Task.isCancelled { return }
            await self?.handleSessionWelcomeTimeout()
        }
    }

    /// Cancels the session welcome timeout.
    private func cancelSessionWelcomeTimeout() {
        sessionWelcomeTask?.cancel()
        sessionWelcomeTask = nil
    }

    /// Called when session_welcome timeout expires.
    private func handleSessionWelcomeTimeout() async {
        guard sessionID == nil else { return } // If we already got a welcome, ignore

        Log.error(
            "TwitchChatService: Session welcome timeout - WebSocket may not be responding",
            category: "Twitch")
        setConnected(false)
        NotificationCenter.default.post(
            name: TwitchChatService.connectionStateChanged,
            object: nil,
            userInfo: ["isConnected": false]
        )
        connectionStateContinuation.yield(false)

        disconnectFromEventSub()

        if let channelName = reconnectChannelName,
           let token = reconnectToken,
           let clientID = reconnectClientID,
           !channelName.isEmpty, !token.isEmpty, !clientID.isEmpty,
           isNetworkReachable {
            Log.info(
                "TwitchChatService: Attempting reconnection after session welcome timeout",
                category: "Twitch")
            scheduleReconnect()
        }
    }

    /// Disconnects from the EventSub WebSocket and clears session state.
    private func disconnectFromEventSub() {
        setConnected(false)
        let task = webSocketTask
        webSocketTask = nil
        sessionID = nil
        task?.cancel(with: .goingAway, reason: nil)

        sessionWelcomeTask?.cancel()
        sessionWelcomeTask = nil
        receiveTask?.cancel()
        receiveTask = nil

        Log.debug("TwitchChatService: EventSub WebSocket disconnected", category: "Twitch")
    }

    /// Drives the WebSocket receive loop. Replaces the recursive
    /// `task.receive { ... }` callback chain with a structured async loop
    /// that keeps frame ordering and integrates cleanly with actor isolation.
    private func startReceiveLoop() {
        receiveTask?.cancel()
        let task = webSocketTask
        receiveTask = Task { [weak self] in
            guard let task else { return }
            while !Task.isCancelled {
                do {
                    let message = try await task.receive()
                    switch message {
                    case .string(let text):
                        await self?.handleWebSocketMessage(text)
                    case .data(let data):
                        if let text = String(data: data, encoding: .utf8) {
                            await self?.handleWebSocketMessage(text)
                        }
                    @unknown default:
                        break
                    }
                } catch {
                    let isDisconnecting = await self?.isProcessingDisconnect ?? true
                    if isDisconnecting { return }
                    await self?.handleReceiveError(error)
                    return
                }
            }
        }
    }

    /// Handles a WebSocket receive error: logs, updates state, and attempts reconnect.
    private func handleReceiveError(_ error: Error) async {
        let nsError = error as NSError
        let errorCode = nsError.code
        let errorDomain = nsError.domain

        if errorDomain == NSURLErrorDomain && errorCode == NSURLErrorTimedOut {
            Log.error(
                "TwitchChatService: WebSocket connection timed out. This may be due to network issues, firewall blocking, or Twitch service problems.",
                category: "Twitch")
        } else {
            Log.error(
                "TwitchChatService: WebSocket connection error: \(error.localizedDescription) (Domain: \(errorDomain), Code: \(errorCode))",
                category: "Twitch")
        }

        setConnected(false)
        NotificationCenter.default.post(
            name: TwitchChatService.connectionStateChanged,
            object: nil,
            userInfo: ["isConnected": false, "error": error.localizedDescription]
        )
        connectionStateContinuation.yield(false)

        if let channelName = reconnectChannelName,
           let token = reconnectToken,
           let clientID = reconnectClientID,
           !channelName.isEmpty, !token.isEmpty, !clientID.isEmpty,
           isNetworkReachable {
            Log.info("TwitchChatService: Attempting automatic reconnection", category: "Twitch")
            scheduleReconnect()
        }
    }

    /// Handles a received WebSocket message.
    private func handleWebSocketMessage(_ text: String) async {
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
            Log.warn(
                "TwitchChatService: Failed to parse WebSocket message JSON - \(error.localizedDescription)",
                category: "Twitch")
            return
        }

        guard let metadata = json["metadata"] as? [String: Any],
              let messageType = metadata["message_type"] as? String,
              let messageID = metadata["message_id"] as? String, !messageID.isEmpty,
              let messageTimestamp = metadata["message_timestamp"] as? String, !messageTimestamp.isEmpty else {
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
                Log.warn(
                    "TwitchChatService: Failed to parse EventSub timestamp: \(messageTimestamp)",
                    category: "Twitch")
            }
        }
        if let timestamp {
            let age = Date().timeIntervalSince(timestamp)
            if age > 600 {
                Log.warn(
                    "TwitchChatService: Rejecting stale EventSub message (age: \(Int(age))s)",
                    category: "Twitch")
                return
            }
        }

        switch messageType {
        case "session_welcome":
            await handleSessionWelcome(json)
        case "notification":
            await handleNotification(json)
        case "session_keepalive":
            break
        default:
            break
        }
    }

    /// Handles the session_welcome message from EventSub.
    private func handleSessionWelcome(_ json: [String: Any]) async {
        guard let payload = json["payload"] as? [String: Any],
              let session = payload["session"] as? [String: Any],
              let sessionID = session["id"] as? String else {
            Log.error("TwitchChatService: Failed to parse session ID", category: "Twitch")
            return
        }

        cancelSessionWelcomeTimeout()
        self.sessionID = sessionID
        Log.info(
            "TwitchChatService: EventSub session established with ID: \(sessionID)",
            category: "Twitch")

        setConnected(true)
        NotificationCenter.default.post(
            name: TwitchChatService.connectionStateChanged,
            object: nil,
            userInfo: ["isConnected": true]
        )
        connectionStateContinuation.yield(true)

        await subscribeToChannelChatMessage()
        await subscribeToPollEvents()
        await subscribeToStreamEvents()
        await seedStreamLiveState()
        await subscribeToRedemptionsIfEnabled()
    }

    /// Handles notification messages containing EventSub events.
    private func handleNotification(_ json: [String: Any]) async {
        guard let payload = json["payload"] as? [String: Any] else { return }
        guard let subscription = payload["subscription"] as? [String: Any],
              let subType = subscription["type"] as? String else {
            Log.warn(
                "TwitchChatService: EventSub notification missing subscription type",
                category: "Twitch")
            return
        }

        switch subType {
        case AppConstants.Twitch.eventSubChatMessage:
            await handleEventSubMessage(payload)
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
    /// forwards the Skip/Keep tallies to the `skipPollResults` stream.
    private func handlePollEndEvent(_ payload: [String: Any]) {
        guard let event = payload["event"] as? [String: Any],
              let title = event["title"] as? String,
              title == TwitchChatService.skipPollTitle,
              let choices = event["choices"] as? [[String: Any]] else { return }

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

        Log.info(
            "TwitchChatService: Vote-skip poll ended — \(skipVotes) skip / \(keepVotes) keep",
            category: "Twitch")
        skipPollResultsContinuation.yield(SkipPollResult(skipVotes: skipVotes, keepVotes: keepVotes))
    }

    // MARK: - Vote-Skip Polls

    /// Creates a native Twitch poll asking chat to vote on skipping the current song.
    ///
    /// Requires the `channel:manage:polls` scope and Affiliate/Partner status —
    /// missing either causes Twitch to reject the request, in which case this
    /// returns `false` and `SkipVoteManager` falls back to a chat tally.
    func createSkipPoll(title: String, durationSeconds: Int) async -> Bool {
        guard let broadcasterID,
              let token = oauthToken,
              let clientID else {
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
            Log.error(
                "TwitchChatService: Failed to serialize poll body - \(error.localizedDescription)",
                category: "Twitch")
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
            Log.warn(
                "TwitchChatService: Poll creation failed — HTTP \(http.statusCode) — \(text)",
                category: "Twitch")
            return false
        } catch {
            Log.error(
                "TwitchChatService: Poll creation request failed - \(error.localizedDescription)",
                category: "Twitch")
            return false
        }
    }

    /// Subscribes to `channel.poll.end` so finished vote-skip polls can be tallied.
    private func subscribeToPollEvents() async {
        guard UserDefaults.standard.bool(forKey: AppConstants.UserDefaults.voteSkipEnabled),
              UserDefaults.standard.bool(forKey: AppConstants.UserDefaults.voteSkipUsePolls) else { return }

        guard let sessionID,
              let broadcasterID,
              let token = oauthToken,
              let clientID else {
            Log.warn(
                "TwitchChatService: Missing credentials for poll EventSub subscription",
                category: "Twitch")
            return
        }

        let body: [String: Any] = [
            "type": "channel.poll.end",
            "version": "1",
            "condition": ["broadcaster_user_id": broadcasterID],
            "transport": ["method": "websocket", "session_id": sessionID],
        ]
        await postEventSubSubscription(body: body, token: token, clientID: clientID, label: "channel.poll.end")
    }

    /// Updates `streamLive` from a `stream.online` / `stream.offline` event.
    private func handleStreamStateNotification(type: String) {
        switch type {
        case "stream.online":
            streamLive = true
            Log.info("TwitchChatService: Stream went live", category: "Twitch")
        case "stream.offline":
            streamLive = false
            Log.info("TwitchChatService: Stream went offline", category: "Twitch")
        default:
            Log.debug("TwitchChatService: Ignoring unexpected EventSub type: \(type)", category: "Twitch")
        }
    }

    // MARK: - EventSub Subscriptions

    /// Subscribes to the channel.chat.message EventSub event.
    private func subscribeToChannelChatMessage() async {
        guard let sessionID,
              let broadcasterID,
              let botID,
              let token = oauthToken,
              let clientID else {
            Log.error(
                "TwitchChatService: Missing credentials for EventSub subscription",
                category: "Twitch")
            setConnected(false)
            NotificationCenter.default.post(
                name: TwitchChatService.connectionStateChanged,
                object: nil,
                userInfo: ["isConnected": false]
            )
            connectionStateContinuation.yield(false)
            return
        }

        let body: [String: Any] = [
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
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        } catch {
            Log.error(
                "TwitchChatService: Failed to serialize EventSub subscription body - \(error.localizedDescription)",
                category: "Twitch")
            return
        }

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            if let http = response as? HTTPURLResponse {
                if (200..<300).contains(http.statusCode) {
                    Log.info("TwitchChatService: Connected to chat", category: "Twitch")
                    if shouldSendConnectionMessageOnSubscribe {
                        sendConnectionMessage()
                    }
                } else {
                    let responseText = String(data: data, encoding: .utf8) ?? "No response"
                    Log.error(
                        "TwitchChatService: EventSub subscription failed - HTTP \(http.statusCode) - \(responseText)",
                        category: "Twitch")
                    setConnected(false)
                    NotificationCenter.default.post(
                        name: TwitchChatService.connectionStateChanged,
                        object: nil,
                        userInfo: ["isConnected": false]
                    )
                    connectionStateContinuation.yield(false)
                }
            }
        } catch {
            Log.error(
                "TwitchChatService: EventSub subscription error - \(error.localizedDescription)",
                category: "Twitch")
            setConnected(false)
            NotificationCenter.default.post(
                name: TwitchChatService.connectionStateChanged,
                object: nil,
                userInfo: ["isConnected": false]
            )
            connectionStateContinuation.yield(false)
        }
    }

    /// Subscribes to `stream.online` / `stream.offline` so `streamLive` stays current.
    private func subscribeToStreamEvents() async {
        guard let sessionID,
              let broadcasterID,
              let token = oauthToken,
              let clientID else { return }

        for eventType in ["stream.online", "stream.offline"] {
            let body: [String: Any] = [
                "type": eventType,
                "version": "1",
                "condition": ["broadcaster_user_id": broadcasterID],
                "transport": ["method": "websocket", "session_id": sessionID],
            ]
            await postEventSubSubscription(body: body, token: token, clientID: clientID, label: eventType)
        }
    }

    /// Seeds `streamLive` with a single Helix "Get Streams" call.
    private func seedStreamLiveState() async {
        guard let broadcasterID,
              let token = oauthToken,
              let clientID,
              let url = URL(string: apiBaseURL + "/streams?user_id=\(broadcasterID)") else { return }

        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue(clientID, forHTTPHeaderField: "Client-ID")

        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let streams = json["data"] as? [[String: Any]] else { return }
            let live = !streams.isEmpty
            streamLive = live
            Log.info("TwitchChatService: Seeded stream-live state — live=\(live)", category: "Twitch")
        } catch {
            Log.debug(
                "TwitchChatService: Stream-live seed request failed - \(error.localizedDescription)",
                category: "Twitch")
        }
    }

    // MARK: - Redemption EventSub Subscriptions

    /// Subscribes to channel-point and/or bit EventSub events when the matching
    /// song-request features are enabled. Channel-point and bit subscriptions
    /// require the signed-in account to be the broadcaster — when a separate bot
    /// account is in use they are skipped and the UI is notified.
    private func subscribeToRedemptionsIfEnabled() async {
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
            await ensureSongRequestRewardAndSubscribe()
        }
        if bitsEnabled {
            await subscribeToBitsUse()
        }
    }

    /// Re-evaluates redemption subscriptions against the current settings.
    /// Called by the settings UI after the streamer changes a redemption toggle.
    func refreshRedemptionSubscriptions() async {
        guard isConnected else { return }
        await subscribeToRedemptionsIfEnabled()
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
            await subscribeToChannelPointsRedemption()
            setRedemptionStatus(.ok)
        } catch {
            Log.error(
                "TwitchChatService: Failed to set up channel-point reward - \(error.localizedDescription)",
                category: "Twitch")
            setRedemptionStatus(.subscribeFailed)
        }
    }

    private func subscribeToChannelPointsRedemption() async {
        guard let broadcasterID, let token = oauthToken, let clientID, let sessionID else { return }
        let body: [String: Any] = [
            "type": AppConstants.Twitch.eventSubChannelPointsRedemption,
            "version": "1",
            "condition": ["broadcaster_user_id": broadcasterID],
            "transport": ["method": "websocket", "session_id": sessionID],
        ]
        await postEventSubSubscription(body: body, token: token, clientID: clientID, label: "channel-point redemptions")
    }

    private func subscribeToBitsUse() async {
        guard let broadcasterID, let token = oauthToken, let clientID, let sessionID else { return }
        let body: [String: Any] = [
            "type": AppConstants.Twitch.eventSubBitsUse,
            "version": "1",
            "condition": ["broadcaster_user_id": broadcasterID],
            "transport": ["method": "websocket", "session_id": sessionID],
        ]
        await postEventSubSubscription(body: body, token: token, clientID: clientID, label: "bit usage")
    }

    /// Posts an EventSub subscription request. Logs success/failure and updates
    /// redemption status on 403 (scope) / non-2xx (subscribeFailed).
    private func postEventSubSubscription(
        body: [String: Any],
        token: String,
        clientID: String,
        label: String
    ) async {
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

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else { return }
            if (200..<300).contains(http.statusCode) {
                Log.info("TwitchChatService: Subscribed to \(label)", category: "Twitch")
            } else if http.statusCode == 409 {
                Log.info("TwitchChatService: \(label) subscription already active", category: "Twitch")
            } else {
                let responseText = String(data: data, encoding: .utf8) ?? "No response"
                Log.error(
                    "TwitchChatService: \(label) subscription failed - HTTP \(http.statusCode) - \(responseText)",
                    category: "Twitch")
                if label == "channel-point redemptions" || label == "bit usage" {
                    setRedemptionStatus(http.statusCode == 403 ? .scopeMissing : .subscribeFailed)
                }
            }
        } catch {
            Log.error(
                "TwitchChatService: \(label) subscription error - \(error.localizedDescription)",
                category: "Twitch")
        }
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
        let songRequestService = self.songRequestService

        Task { [weak self] in
            guard let self else { return }
            guard let service = songRequestService else { return }

            if userInput.isEmpty {
                await self.sendMessage(
                    "@\(userName) add a song name when you redeem — refunding your points.")
                await self.resolveRedemption(
                    credentials, rewardID: rewardID, redemptionID: redemptionID, as: .canceled)
                return
            }

            let result = await service.processRequest(
                query: userInput,
                username: userName,
                source: .channelPoints(redemptionID: redemptionID, rewardID: rewardID))
            let (message, resolution) = await self.redemptionOutcome(for: result, username: userName)
            await self.sendMessage(message)
            await self.resolveRedemption(
                credentials, rewardID: rewardID, redemptionID: redemptionID, as: resolution)
        }
    }

    /// Handles a `channel.bits.use` event.
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
        let songRequestService = self.songRequestService

        Task { [weak self] in
            guard let self else { return }
            guard let service = songRequestService else { return }

            if boostEnabled, let boosted = await service.queue.boost(username: userName) {
                await self.sendMessage(
                    "@\(userName) boosted \"\(boosted.title)\" to the front of the queue! (\(bits) bits)")
                return
            }

            guard !query.isEmpty else {
                if boostEnabled {
                    await self.sendMessage(
                        "@\(userName) no song of yours to boost — include a song name in your cheer to request one.")
                }
                return
            }

            let result = await service.processRequest(
                query: query, username: userName, source: .bits(amount: bits))
            await self.sendMessage(await self.bitsOutcomeMessage(for: result, username: userName))
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
            return ("@\(username) you already have \(max) songs queued. Points refunded.", .canceled)
        case .alreadyInQueue:
            return ("@\(username) that song is already queued. Points refunded.", .canceled)
        case .blocked:
            return ("@\(username) that song is on the blocklist. Points refunded.", .canceled)
        case let .notFound(query):
            let truncated = query.count > 30 ? String(query.prefix(30)) + "..." : query
            return ("@\(username) no results for \"\(truncated)\". Points refunded.", .canceled)
        case .linkNotFound:
            return ("@\(username) couldn't find that on Apple Music. Points refunded.", .canceled)
        case .notAuthorized:
            return ("@\(username) song requests aren't available right now. Points refunded.", .canceled)
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
              !broadcasterID.isEmpty, !token.isEmpty, !clientID.isEmpty else { return nil }
        return TwitchChannelPointsService.Credentials(
            broadcasterID: broadcasterID, token: token, clientID: clientID)
    }

    /// Configured channel-point cost for the managed reward (default 500).
    nonisolated private func channelPointsCostSetting() -> Int {
        let stored = UserDefaults.standard.integer(
            forKey: AppConstants.UserDefaults.songRequestChannelPointsCost)
        return stored > 0 ? stored : 500
    }

    /// Configured minimum bits required to trigger a request (default 100).
    nonisolated private func bitsMinimumSetting() -> Int {
        let stored = UserDefaults.standard.integer(
            forKey: AppConstants.UserDefaults.songRequestBitsMinimum)
        return stored > 0 ? stored : 100
    }

    /// Persists the redemption integration health for the settings UI.
    nonisolated private func setRedemptionStatus(_ status: RedemptionStatus) {
        UserDefaults.standard.set(
            status.rawValue, forKey: AppConstants.UserDefaults.songRequestRedemptionStatus)
    }

    /// Extracts the viewer's song query from a `channel.bits.use` message,
    /// dropping cheermote tokens.
    nonisolated static func cleanBitsMessage(_ message: [String: Any]?) -> String {
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
    nonisolated static func stripLeadingCheermotes(_ text: String) -> String {
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

    /// Validates whether a Twitch channel name exists by resolving it to a user ID.
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
    func resolveUsername(_ username: String, token: String, clientID: String) async throws -> String {
        let sanitizedUsername = username
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        guard !sanitizedUsername.isEmpty else {
            throw ConnectionError.networkError("Username cannot be empty")
        }
        guard let encodedUsername = sanitizedUsername.addingPercentEncoding(
            withAllowedCharacters: .urlQueryAllowed) else {
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
                if http.statusCode == 401 { throw ConnectionError.authenticationFailed }
                throw ConnectionError.networkError("HTTP \(http.statusCode)")
            }

            let json: [String: Any]
            do {
                guard let parsed = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                    throw ConnectionError.networkError("Username response is not a JSON object")
                }
                json = parsed
            } catch {
                if let connectionError = error as? ConnectionError { throw connectionError }
                throw ConnectionError.networkError(
                    "Failed to decode username response: \(error.localizedDescription)")
            }

            guard let dataArray = json["data"] as? [[String: Any]],
                  let first = dataArray.first,
                  let userID = first["id"] as? String,
                  !userID.isEmpty else {
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

    // MARK: - Sync Bridge

    /// Synchronously invokes an `async` operation by spinning a `DispatchSemaphore`.
    ///
    /// Used only by the dispatcher's legacy sync provider closures (`!song`,
    /// `!last`, `!stats`) — those closures are called from
    /// `BotCommandDispatcher.processMessage`, which is itself called from
    /// inside the actor. Re-entering the actor synchronously from there is
    /// safe because the providers ultimately hop to `@MainActor` to read
    /// AppDelegate state, never back into this actor.
    ///
    /// Long-term, the dispatcher should expose an `async` `processMessage` so
    /// this bridge can be removed; tracked under G5 follow-up.
    nonisolated private static func runSync<T: Sendable>(_ work: @escaping @Sendable () async -> T) -> T? {
        let semaphore = DispatchSemaphore(value: 0)
        let box = SendableBox<T>()
        Task.detached {
            box.value = await work()
            semaphore.signal()
        }
        semaphore.wait()
        return box.value
    }

    /// Sendable box used by `runSync` to ship a value across the semaphore.
    private final class SendableBox<T: Sendable>: @unchecked Sendable {
        var value: T?
    }

    /// Lock-protected registry for the three async track-info providers.
    ///
    /// Lives outside actor isolation so the sync dispatcher bridge can read
    /// providers without re-entering the actor. Tiny surface, single lock —
    /// does not reintroduce the lock-sprawl the actor conversion removed.
    final class ProviderRegistry: @unchecked Sendable {
        private let lock = NSLock()
        private var _current: (@Sendable () async -> String)?
        private var _last: (@Sendable () async -> String)?
        private var _stats: (@Sendable () async -> String)?

        func setCurrent(_ provider: (@Sendable () async -> String)?) {
            lock.withLock { _current = provider }
        }
        func setLast(_ provider: (@Sendable () async -> String)?) {
            lock.withLock { _last = provider }
        }
        func setStats(_ provider: (@Sendable () async -> String)?) {
            lock.withLock { _stats = provider }
        }
        func current() -> (@Sendable () async -> String)? { lock.withLock { _current } }
        func last() -> (@Sendable () async -> String)? { lock.withLock { _last } }
        func stats() -> (@Sendable () async -> String)? { lock.withLock { _stats } }
    }

    /// Lock-protected boolean mirror of an actor-isolated flag.
    ///
    /// Used by the sync dispatcher bridge (`!stats` gating) to read state
    /// without re-entering the actor.
    final class AtomicBool: @unchecked Sendable {
        private let lock = NSLock()
        private var _value = false
        var value: Bool { lock.withLock { _value } }
        func set(_ newValue: Bool) { lock.withLock { _value = newValue } }
    }
}
