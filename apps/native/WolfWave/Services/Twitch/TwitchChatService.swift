//
//  TwitchChatService.swift
//  WolfWave
//
//  Created by Nathanial Henniges on 2026-01-08.
//  Copyright © 2026 MrDemonWolf, Inc. All rights reserved.
//

import Foundation
import Network

// MARK: - Helix Response Models

/// `GET /helix/users` response. Used by `fetchBotIdentity` and `resolveUsername`.
nonisolated private struct HelixUsersResponse: Decodable {
    struct User: Decodable {
        let id: String
        let login: String
        let displayName: String?
    }
    let data: [User]
}

/// `GET https://id.twitch.tv/oauth2/validate` response. Used by `validateToken`.
nonisolated private struct TwitchValidateResponse: Decodable {
    let scopes: [String]?
}

/// `POST /helix/chat/messages` response. Used by `sendMessage` to confirm delivery.
nonisolated private struct HelixSendMessageResponse: Decodable {
    struct SentMessage: Decodable {
        let isSent: Bool
    }
    let data: [SentMessage]
}

/// `GET /helix/streams` response. Used by `seedStreamLiveState`.
nonisolated private struct HelixStreamsResponse: Decodable {
    struct Stream: Decodable {
        let id: String
    }
    let data: [Stream]
}

/// Maps an `HTTPClient.HTTPError` to the matching `TwitchChatService.ConnectionError`.
/// Preserves the existing 401 → `authenticationFailed` mapping; everything else
/// becomes `.networkError(...)` with the underlying description.
nonisolated func mapHelixError(_ error: Error) -> TwitchChatService.ConnectionError {
    if let httpError = error as? HTTPClient.HTTPError {
        switch httpError {
        case .unexpectedStatus(401, _):
            return .authenticationFailed
        case .unexpectedStatus(let code, _):
            return .networkError("HTTP \(code)")
        case .invalidResponse:
            return .networkError("No HTTP response")
        case .decodingFailed:
            return .networkError("Unable to decode response")
        case .transport(let underlying):
            return .networkError(underlying.localizedDescription)
        }
    }
    if let connectionError = error as? TwitchChatService.ConnectionError {
        return connectionError
    }
    return .networkError(error.localizedDescription)
}

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
/// - `actor`-isolated. The actor's own mutable state lives inside its isolation
///   domain with no locks. The only locks are in the `ProviderRegistry` mirror
///   class and the shared `Atomic` boxes that exist so the sync dispatcher
///   bridge can read state without re-entering the actor.
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

        /// Twitch chat roles derived from a sender's badges.
        ///
        /// Pure and testable so the song-request permission gate can't silently
        /// regress (e.g. dropping the `founder` synonym for `subscriber`).
        struct Roles: Sendable {
            let isModerator: Bool
            let isBroadcaster: Bool
            let isSubscriber: Bool
            let isVIP: Bool
        }

        /// Derives chat roles from the message's badge set.
        ///
        /// - Note: `founder` is the badge Twitch gives a channel's earliest
        ///   subscribers in place of `subscriber`; both count as a subscriber so
        ///   the subscriber-only request gate doesn't wrongly deny founders.
        var roles: Roles {
            Roles(
                isModerator: badges.contains { $0.setID == "moderator" },
                isBroadcaster: badges.contains { $0.setID == "broadcaster" },
                isSubscriber: badges.contains { $0.setID == "subscriber" || $0.setID == "founder" },
                isVIP: badges.contains { $0.setID == "vip" }
            )
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

    /// How a `revocation` EventSub message should be handled.
    ///
    /// Twitch revokes a subscription when the user de-authorizes the app
    /// (`authorization_revoked`), removes their account (`user_removed`), or the
    /// subscription version is retired (`version_removed`). Only the first means
    /// the token is dead; the others are recoverable by re-subscribing.
    enum RevocationDisposition: Sendable, Equatable {
        /// Token is no longer valid; surface the re-auth banner and stop reconnecting.
        case reauth
        /// Subscription was dropped but the token is fine; re-subscribe.
        case resubscribe
        /// Unrecognized status; do nothing (log only).
        case ignore
    }

    // MARK: - EventSub Decision Helpers (nonisolated, pure, testable)

    /// Extracts a session reconnect URL from a `session_reconnect` message.
    ///
    /// Reads `payload.session.reconnect_url`. Returns the trimmed string only when
    /// it is a non-empty, well-formed absolute URL; otherwise `nil` so the caller
    /// falls back to the proven fresh-connect path.
    nonisolated static func reconnectURL(from json: [String: Any]) -> String? {
        guard let payload = json["payload"] as? [String: Any],
              let session = payload["session"] as? [String: Any],
              let raw = session["reconnect_url"] as? String else {
            return nil
        }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let url = URL(string: trimmed),
              let scheme = url.scheme?.lowercased(),
              scheme == "wss" || scheme == "ws",
              url.host != nil else {
            return nil
        }
        return trimmed
    }

    /// Reads `payload.session.keepalive_timeout_seconds` from a `session_welcome`
    /// message. Returns `nil` when the field is missing or non-positive so the
    /// caller can substitute a safe default.
    nonisolated static func keepaliveTimeoutSeconds(from json: [String: Any]) -> TimeInterval? {
        guard let payload = json["payload"] as? [String: Any],
              let session = payload["session"] as? [String: Any] else {
            return nil
        }
        // Twitch sends an integer, but tolerate a numeric string too.
        if let intValue = session["keepalive_timeout_seconds"] as? Int, intValue > 0 {
            return TimeInterval(intValue)
        }
        if let doubleValue = session["keepalive_timeout_seconds"] as? Double, doubleValue > 0 {
            return doubleValue
        }
        if let stringValue = session["keepalive_timeout_seconds"] as? String,
           let parsed = TimeInterval(stringValue), parsed > 0 {
            return parsed
        }
        return nil
    }

    /// Computes the keepalive watchdog deadline: the advertised timeout plus a
    /// grace period. Clamped to a small positive minimum so a degenerate input
    /// can never produce a zero-or-negative deadline that fires immediately.
    nonisolated static func keepaliveDeadline(
        timeoutSeconds: TimeInterval,
        grace: TimeInterval
    ) -> TimeInterval {
        let safeTimeout = max(0, timeoutSeconds)
        let safeGrace = max(0, grace)
        return max(1, safeTimeout + safeGrace)
    }

    /// Maps a `revocation` subscription `(type, status)` to a disposition.
    ///
    /// `status` drives the decision; `type` is accepted for future per-type
    /// granularity and logging. `authorization_revoked` is fatal (re-auth);
    /// `user_removed` / `version_removed` are recoverable (re-subscribe).
    nonisolated static func revocationDisposition(
        type: String,
        status: String
    ) -> RevocationDisposition {
        switch status {
        case "authorization_revoked":
            return .reauth
        case "user_removed", "version_removed":
            return .resubscribe
        default:
            return .ignore
        }
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
        Notification.Name.twitchConnectionStateChanged

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

    /// Keepalive watchdog. Armed after `session_welcome` from the advertised
    /// `keepalive_timeout_seconds` (+ grace) and reset on every inbound frame.
    /// Firing means Twitch went quiet past the deadline, so we tear down and
    /// reconnect via the proven fresh-connect path.
    private var keepaliveWatchdogTask: Task<Void, Never>?

    /// Current keepalive deadline (seconds) used when the watchdog re-arms on
    /// each inbound frame. Set from the `session_welcome` payload.
    private var keepaliveDeadlineSeconds: TimeInterval = AppConstants.Twitch.keepaliveDefaultTimeoutSeconds

    /// True while a `session_reconnect` migration is in flight. The resulting
    /// `session_welcome` then only re-arms the watchdog and flips connected,
    /// skipping the `subscribeTo*` calls because subscriptions migrate with the
    /// reconnect_url session.
    private var isMigratingSession = false

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
    /// actor's mailbox. Re-entering while the actor's executor is blocked on
    /// `runSync`'s semaphore would deadlock.
    nonisolated private let providers = ProviderRegistry()

    // MARK: - UserDefaults-derived (read on demand)

    /// Whether the current song command is enabled (computed from UserDefaults on each access).
    nonisolated var currentSongCommandEnabled: Bool {
        Preferences.bool(AppConstants.UserDefaults.currentSongCommandEnabled, default: false)
    }

    /// Whether the last song command is enabled (computed from UserDefaults on each access).
    nonisolated var lastSongCommandEnabled: Bool {
        Preferences.bool(AppConstants.UserDefaults.lastSongCommandEnabled, default: false)
    }

    /// Whether the `!stats` command should respond. Both the Stats feature and
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
    nonisolated let isConnectedSnapshot = Atomic(false)

    /// Nonisolated mirror of `streamLive` so the synchronous dispatcher bridge
    /// (`!stats` enable check) can read it without re-entering the actor.
    nonisolated private let streamLiveSnapshot = Atomic(false)

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
        let chat = AsyncStream.makeStream(
            of: ChatMessage.self,
            bufferingPolicy: .bufferingNewest(AppConstants.Twitch.chatMessageStreamBuffer))
        let connection = AsyncStream.makeStream(
            of: Bool.self,
            bufferingPolicy: .bufferingNewest(AppConstants.Twitch.controlStreamBuffer))
        let skip = AsyncStream.makeStream(
            of: SkipPollResult.self,
            bufferingPolicy: .bufferingNewest(AppConstants.Twitch.controlStreamBuffer))

        self.chatMessages = chat.stream
        self.chatMessagesContinuation = chat.continuation
        self.connectionStateChanges = connection.stream
        self.connectionStateContinuation = connection.continuation
        self.skipPollResults = skip.stream
        self.skipPollResultsContinuation = skip.continuation
        self.commandDispatcher = BotCommandDispatcher()
    }

    deinit {
        // Synchronous cleanup only. Actor isolation forbids awaits in deinit.
        sessionWelcomeTask?.cancel()
        reconnectTask?.cancel()
        receiveTask?.cancel()
        keepaliveWatchdogTask?.cancel()
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

        /// Records a hard 429 backoff: marks `endpoint` saturated until
        /// `resetEpoch` (seconds since 1970) so ``awaitCapacity(endpoint:)``
        /// sleeps until the bucket is allowed to refill. Used by the reactive
        /// 429 retry path after parsing `Ratelimit-Reset` / `Retry-After`.
        func noteRateLimited(endpoint: String, untilEpoch resetEpoch: TimeInterval) {
            var state = states[endpoint] ?? RateLimitState()
            state.remaining = 0
            state.resetTime = resetEpoch
            states[endpoint] = state
        }

        /// Parses the seconds to wait after a `429 Too Many Requests` response.
        ///
        /// Prefers a `Retry-After` delta (seconds from now); falls back to
        /// `Ratelimit-Reset` (epoch seconds). Returns `nil` when neither header
        /// is present or parseable. The result is clamped to be non-negative.
        ///
        /// `nonisolated` + `static` so it is unit-testable without the actor or a
        /// live socket.
        nonisolated static func retryWaitSeconds(
            from headers: [AnyHashable: Any],
            now: TimeInterval
        ) -> TimeInterval? {
            func headerValue(_ name: String) -> String? {
                if let direct = headers[name] as? String { return direct }
                // Header lookups are case-insensitive in practice; scan keys.
                for (key, value) in headers {
                    if let keyString = key as? String,
                       keyString.caseInsensitiveCompare(name) == .orderedSame,
                       let stringValue = value as? String {
                        return stringValue
                    }
                }
                return nil
            }

            if let retryAfter = headerValue("Retry-After"),
               let seconds = TimeInterval(retryAfter.trimmingCharacters(in: .whitespaces)) {
                return max(0, seconds)
            }
            if let reset = headerValue("Ratelimit-Reset"),
               let resetEpoch = TimeInterval(reset.trimmingCharacters(in: .whitespaces)) {
                return max(0, resetEpoch - now)
            }
            return nil
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

            MetricsService.shared.recordTwitchRateLimit(
                endpoint: endpoint,
                remaining: state.remaining,
                limit: state.limit,
                resetTime: state.resetTime
            )
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
            // Backoff timing tolerates 10% jitter, lets the wakeup coalesce.
            try? await Task.sleep(for: .seconds(delaySeconds), tolerance: .seconds(delaySeconds * 0.1))
            if Task.isCancelled { return }
            await self?.attemptReconnect(channelName: channelName, token: token, clientID: clientID)
        }
    }

    private func attemptReconnect(channelName: String, token: String, clientID: String) async {
        do {
            try await connectToChannel(channelName: channelName, token: token, clientID: clientID)
            reconnectionAttempts = 0
            Log.info("TwitchChatService: Reconnection successful", category: "Twitch")
        } catch ConnectionError.authenticationFailed {
            // A 401 means the stored token is dead. Retrying with the same token
            // only burns `maxReconnectionAttempts` and never succeeds, so stop the
            // loop and surface the re-auth banner. Try one reactive token refresh
            // first; only fall back to interactive re-auth when that fails.
            Log.error(
                "TwitchChatService: Reconnect failed with 401; token is invalid or expired",
                category: "Twitch")
            await handleAuthenticationFailureDuringReconnect(
                channelName: channelName, clientID: clientID)
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

    /// Handles a 401 during reconnect. Attempts exactly ONE reactive token
    /// refresh (no loop); on success it reconnects with the fresh token, and on
    /// any failure it signals interactive re-auth and stops the reconnect loop.
    private func handleAuthenticationFailureDuringReconnect(
        channelName: String, clientID: String
    ) async {
        if let refreshed = await TwitchTokenRefresher.attemptReactiveRefresh(clientID: clientID) {
            Log.info(
                "TwitchChatService: Reactive token refresh succeeded; reconnecting",
                category: "Twitch")
            reconnectToken = refreshed
            reconnectionAttempts = 0
            do {
                try await connectToChannel(
                    channelName: channelName, token: refreshed, clientID: clientID)
                Log.info(
                    "TwitchChatService: Reconnection successful after token refresh",
                    category: "Twitch")
                return
            } catch {
                Log.warn(
                    "TwitchChatService: Reconnect after refresh failed - \(error.localizedDescription)",
                    category: "Twitch")
            }
        }
        // Refresh unavailable or failed: stop looping and ask the user to re-auth.
        signalReauthNeededAndStop()
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
        // hops to MainActor. Track-info providers are wired as async closures
        // and consumed via `processMessageAsync`. That avoids the deadlock
        // the previous `runSync` semaphore bridge introduced when an AppDelegate
        // provider hopped back to MainActor while MainActor was blocked on the
        // semaphore.
        let providers = self.providers
        let streamLiveSnapshot = self.streamLiveSnapshot
        let currentSongCommandEnabled: @Sendable () -> Bool = { [weak self] in
            self?.currentSongCommandEnabled ?? false
        }
        let lastSongCommandEnabled: @Sendable () -> Bool = { [weak self] in
            self?.lastSongCommandEnabled ?? false
        }
        // `!stats` now follows the same global gate as every other command;
        // its own enable state is just feature-on + command-on.
        let statsCommandActive: @Sendable () -> Bool = { [weak self] in
            self?.statsCommandActive ?? false
        }
        // Global "commands only while live" gate. Off → commands reply anytime.
        // On → every command (incl. !stats) waits for stream.online. Read per
        // message so toggling the setting or going live takes effect at once.
        let commandsGlobalGate: @Sendable () -> Bool = {
            guard UserDefaults.standard.bool(forKey: AppConstants.UserDefaults.commandsLiveOnly) else {
                return true
            }
            return streamLiveSnapshot.value
        }
        await MainActor.run {
            commandDispatcher.setCurrentSongInfoAsync {
                Log.debug("Twitch provider: current song closure invoked", category: "Twitch")
                guard let provider = providers.current() else {
                    Log.debug("Twitch provider: current song: no provider, default", category: "Twitch")
                    return "No track currently playing"
                }
                let result = await provider()
                Log.debug("Twitch provider: current song returned \(result.prefix(40))", category: "Twitch")
                return result
            }
            commandDispatcher.setLastSongInfoAsync {
                guard let provider = providers.last() else { return "No previous track available" }
                return await provider()
            }
            commandDispatcher.setStatsInfoAsync {
                guard let provider = providers.stats() else { return "No listening stats yet" }
                return await provider()
            }
            commandDispatcher.setCurrentSongCommandEnabled(callback: currentSongCommandEnabled)
            commandDispatcher.setLastSongCommandEnabled(callback: lastSongCommandEnabled)
            commandDispatcher.setStatsCommandEnabled(callback: statsCommandActive)
            commandDispatcher.setGlobalGate(callback: commandsGlobalGate)
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

        let response: HelixUsersResponse
        do {
            response = try await HTTPClient.shared.get(
                url: url,
                headers: HelixClient.headers(for: .init(token: token, clientID: clientID)))
        } catch {
            let mapped = mapHelixError(error)
            if case .authenticationFailed = mapped {
                Log.error(
                    "TwitchChatService: Authentication failed (401) - invalid or expired OAuth token",
                    category: "Twitch")
            } else {
                Log.error(
                    "TwitchChatService: Users endpoint failed - \(error.localizedDescription)",
                    category: "Twitch")
            }
            throw mapped
        }

        guard let first = response.data.first else {
            Log.error("TwitchChatService: Failed to parse user identity from response", category: "Twitch")
            throw ConnectionError.networkError("Unable to parse user identity")
        }

        let displayName = first.displayName ?? first.login

        botID = first.id
        botUsername = displayName

        return BotIdentity(userID: first.id, login: first.login, displayName: displayName)
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
        NotificationCenter.default.postTwitchConnectionState(isConnected: false)
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
        request.timeoutInterval = 15
        // Per Twitch docs, use "OAuth <token>" for the validate endpoint
        request.setValue("OAuth \(token)", forHTTPHeaderField: "Authorization")
        request.setValue(HTTPClient.defaultUserAgent, forHTTPHeaderField: "User-Agent")

        do {
            let (data, http) = try await HTTPClient.shared.send(request)

            guard (200..<300).contains(http.statusCode) else {
                if http.statusCode == 401 {
                    Log.warn("TwitchChatService: Stored OAuth token is invalid or expired", category: "Twitch")
                } else {
                    Log.warn("TwitchChatService: Token validate HTTP \(http.statusCode)", category: "Twitch")
                }
                return false
            }

            guard let parsed = try? JSONCoders.snakeCase.decode(TwitchValidateResponse.self, from: data) else {
                Log.warn("TwitchChatService: Could not parse token validate response", category: "Twitch")
                return false
            }

            if let scopes = parsed.scopes {
                // Vote-skip Polls mode needs the polls scope. Only require it when
                // the user has actually enabled Polls mode, so existing users are
                // not forced to re-authorize unless they opt in.
                var effectiveScopes = requiredScopes
                let defaults = UserDefaults.standard
                if defaults.bool(forKey: AppConstants.UserDefaults.voteSkipUsePolls),
                   !effectiveScopes.contains(AppConstants.Twitch.pollsScope) {
                    effectiveScopes.append(AppConstants.Twitch.pollsScope)
                }
                // Flag re-auth proactively when a redemption feature is on but its
                // scope is missing (an old token from before these features), so
                // the failure surfaces at connect instead of as a later 403.
                if defaults.bool(forKey: AppConstants.UserDefaults.songRequestChannelPointsEnabled),
                   !effectiveScopes.contains(AppConstants.Twitch.channelPointsScope) {
                    effectiveScopes.append(AppConstants.Twitch.channelPointsScope)
                }
                if defaults.bool(forKey: AppConstants.UserDefaults.songRequestBitsEnabled),
                   !effectiveScopes.contains(AppConstants.Twitch.bitsScope) {
                    effectiveScopes.append(AppConstants.Twitch.bitsScope)
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
    ///
    /// This is the public entry point used by command handlers. It delegates to
    /// `sendMessageOnce(_:replyTo:)` and, on failure, queues a fresh retry at
    /// `attempts: 0`. The drain loop does NOT call this method — it calls
    /// `sendMessageOnce` directly so the per-message attempt count is preserved
    /// across retries instead of being reset to 0.
    func sendMessage(_ message: String, replyTo parentMessageID: String?) async {
        let sent = await sendMessageOnce(message, replyTo: parentMessageID)
        if !sent {
            queueMessageForRetry(message: message, parentMessageID: parentMessageID, attempts: 0)
        }
    }

    /// Performs a single send attempt and reports success/failure WITHOUT
    /// touching the retry queue.
    ///
    /// Returns `true` when the Helix request completed (the message reached
    /// Twitch, regardless of whether Twitch later flagged it dropped), and
    /// `false` when credentials are missing or the request threw. The drain loop
    /// uses the boolean to decide whether to requeue with an incremented attempt
    /// count, so this primitive must never enqueue on its own.
    ///
    /// An empty/whitespace-only message is treated as success (nothing to send,
    /// no point retrying).
    func sendMessageOnce(_ message: String, replyTo parentMessageID: String?) async -> Bool {
        guard let broadcasterID,
              let botID,
              let token = oauthToken,
              let clientID else {
            Log.warn("TwitchChatService: Not connected, send attempt failed", category: "Twitch")
            return false
        }

        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return true }

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
                let parsed = try JSONCoders.snakeCase.decode(HelixSendMessageResponse.self, from: data)
                guard let first = parsed.data.first else {
                    Log.warn("TwitchChatService: Could not parse send-message response", category: "Twitch")
                    return true
                }
                if !first.isSent {
                    Log.warn("TwitchChatService: Message dropped by Twitch", category: "Twitch")
                }
            } catch {
                Log.warn(
                    "TwitchChatService: Failed to decode send-message response - \(error.localizedDescription)",
                    category: "Twitch")
            }
            return true
        } catch {
            Log.error(
                "TwitchChatService: Failed to send message - \(error.localizedDescription)",
                category: "Twitch")
            return false
        }
    }

    /// Applies the drop-oldest cap to a pending-message queue.
    ///
    /// Pure and `nonisolated` so it is unit-testable without spinning up the
    /// actor. Appends `pending` then trims the front until the queue is at most
    /// `cap` entries, returning the number of dropped (oldest) messages so the
    /// caller can log. With `cap <= 0` everything but nothing is kept (the new
    /// message itself is still appended, then trimmed to the cap).
    nonisolated static func appendCapped<Element>(
        _ pending: Element, to queue: inout [Element], cap: Int
    ) -> Int {
        queue.append(pending)
        guard queue.count > cap else { return 0 }
        let overflow = queue.count - max(cap, 0)
        queue.removeFirst(overflow)
        return overflow
    }

    /// Pure decision for whether a just-failed send attempt should be requeued.
    ///
    /// `attempts` is the attempt number that just failed (1-based). The message
    /// is requeued only while `attempts < maxRetries`; once the count reaches the
    /// limit the message is dropped. `nonisolated` so the bounded-retry contract
    /// is unit-testable without the actor or the network.
    nonisolated static func shouldRequeueAfterFailure(attempts: Int, maxRetries: Int) -> Bool {
        attempts < maxRetries
    }

    /// Queues a message for retry with exponential backoff.
    ///
    /// The queue is bounded by `AppConstants.Twitch.maxPendingMessages`
    /// (drop-oldest). A single long-lived drain loop (`pendingRetryTask`) walks
    /// the queue instead of one detached Task per retry.
    private func queueMessageForRetry(message: String, parentMessageID: String?, attempts: Int) {
        guard attempts < maxMessageRetries else {
            Log.error(
                "TwitchChatService: Message dropped after \(maxMessageRetries) retry attempts",
                category: "Twitch")
            return
        }

        let pending = PendingMessage(
            message: message, parentMessageID: parentMessageID, attempts: attempts + 1)
        let dropped = Self.appendCapped(
            pending, to: &pendingMessages, cap: AppConstants.Twitch.maxPendingMessages)
        if dropped > 0 {
            Log.warn(
                "TwitchChatService: Retry queue full, dropped \(dropped) oldest message(s)",
                category: "Twitch")
        }

        Log.debug(
            "TwitchChatService: Queued message retry \(attempts + 1)/\(maxMessageRetries) "
                + "(\(pendingMessages.count) pending)",
            category: "Twitch")

        startRetryDrainLoopIfNeeded()
    }

    /// Starts the single long-lived drain loop if one is not already running.
    private func startRetryDrainLoopIfNeeded() {
        guard pendingRetryTask == nil else { return }
        pendingRetryTask = Task { [weak self] in
            await self?.drainPendingMessages()
        }
    }

    /// Single long-lived drain loop. Walks the pending queue, sleeping per
    /// message according to that message's exponential backoff, until the queue
    /// drains. Exits (clearing `pendingRetryTask`) when empty so a future
    /// enqueue restarts it. Per-message attempt limits are preserved: the loop
    /// sends via `sendMessageOnce` (which never touches the queue) and, on
    /// failure, requeues with `attempts: pending.attempts + 1`, dropping the
    /// message once it reaches `maxMessageRetries`. It must NOT call
    /// `sendMessage`, whose failure path requeues at `attempts: 0` and would
    /// reset the count, allowing unbounded retries.
    private func drainPendingMessages() async {
        defer { pendingRetryTask = nil }

        while !Task.isCancelled, !pendingMessages.isEmpty {
            let pending = pendingMessages.removeFirst()

            // Backoff is keyed off the prior attempt count. `attempts` here is
            // the next attempt number (1-based), so the delay matches the old
            // `pow(2, attempts)` schedule (attempt 1 -> 2^0 = 1s).
            let delay = pow(2.0, Double(pending.attempts - 1))
            try? await Task.sleep(for: .seconds(delay), tolerance: .seconds(delay * 0.1))
            if Task.isCancelled { return }

            // Send without auto-queueing. On failure (missing credentials or a
            // failed request) requeue with the attempt count incremented, so a
            // persistently failing message stops at `maxMessageRetries` instead
            // of looping forever.
            let sent = await sendMessageOnce(pending.message, replyTo: pending.parentMessageID)
            if !sent {
                queueMessageForRetry(
                    message: pending.message,
                    parentMessageID: pending.parentMessageID,
                    attempts: pending.attempts)
            }
        }
    }

    // MARK: - Message Parsing

    /// Parses and handles an incoming message from EventSub.
    func handleEventSubMessage(_ json: [String: Any]) async {
        Log.debug("TwitchChatService: handleEventSubMessage enter (isProcessingDisconnect=\(isProcessingDisconnect))", category: "Twitch")
        if isProcessingDisconnect { return }

        guard let event = json["event"] as? [String: Any] else {
            Log.debug("TwitchChatService: handleEventSubMessage: payload has no event, bail", category: "Twitch")
            return
        }

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
            let roles = chatMessage.roles
            let bypassCooldown = roles.isModerator || roles.isBroadcaster

            let context = BotCommandContext(
                userID: userID,
                username: username,
                isModerator: roles.isModerator,
                isBroadcaster: roles.isBroadcaster,
                isSubscriber: roles.isSubscriber,
                isVIP: roles.isVIP,
                messageID: messageID
            )

            let asyncReply: @Sendable (String) -> Void = { [weak self] response in
                guard let self else { return }
                Task { await self.sendMessage(response, replyTo: messageID) }
            }

            // BotCommandDispatcher is `@MainActor`. `processMessageAsync` auto-hops
            // and awaits the async track-info providers, so MainActor isn't blocked
            // on a semaphore while the provider tries to re-enter MainActor (which
            // was the original `runSync` deadlock).
            Log.debug("TwitchChatService: dispatch enter text=\(text.prefix(40))", category: "Twitch")
            let response: String? = await commandDispatcher.processMessageAsync(
                text,
                userID: userID,
                isModerator: bypassCooldown,
                context: context,
                asyncReply: asyncReply
            )
            Log.debug("TwitchChatService: dispatch exit response=\(response?.prefix(40) ?? "nil")", category: "Twitch")
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

        let request: URLRequest
        do {
            request = try HelixClient.buildRequest(
                url: url, method: method,
                credentials: .init(token: token, clientID: clientID), body: body)
        } catch {
            Log.error(
                "TwitchChatService: Failed to serialize request body - \(error.localizedDescription)",
                category: "Twitch")
            throw ConnectionError.networkError("Failed to serialize request body")
        }

        var (data, http) = try await HTTPClient.shared.send(request)

        await rateLimiter.updateRateLimitState(
            endpoint: endpoint, from: http.allHeaderFields)

        // Reactive 429: honor the server's reset, wait for capacity, then do
        // exactly ONE bounded retry. Never loop, so a persistent 429 can't spin.
        if http.statusCode == 429 {
            let wait = RateLimiter.retryWaitSeconds(
                from: http.allHeaderFields, now: Date().timeIntervalSince1970)
            if let wait {
                Log.info(
                    "TwitchChatService: API \(endpoint) hit 429; waiting \(String(format: "%.1f", wait))s before one retry",
                    category: "Twitch")
                await rateLimiter.noteRateLimited(
                    endpoint: endpoint, untilEpoch: Date().timeIntervalSince1970 + wait)
                await rateLimiter.awaitCapacity(endpoint: endpoint)
            } else {
                Log.info(
                    "TwitchChatService: API \(endpoint) hit 429 without a reset header; one immediate retry",
                    category: "Twitch")
            }

            (data, http) = try await HTTPClient.shared.send(request)
            await rateLimiter.updateRateLimitState(
                endpoint: endpoint, from: http.allHeaderFields)
        }

        if !(200..<300).contains(http.statusCode) {
            let responseText = String(data: data, encoding: .utf8) ?? "No response body"
            Log.warn(
                "TwitchChatService: API \(endpoint) returned HTTP \(http.statusCode) - \(responseText)",
                category: "Twitch")
        }

        return data
    }

    // MARK: - WebSocket Management

    /// Default Twitch EventSub WebSocket endpoint.
    private static let defaultEventSubURL = "wss://eventsub.wss.twitch.tv/ws"

    /// Connects to a Twitch EventSub WebSocket endpoint.
    ///
    /// - Parameter urlString: Endpoint to connect to. Defaults to the standard
    ///   EventSub URL; a `session_reconnect` migration passes the server-provided
    ///   `reconnect_url` instead so subscriptions carry over to the new session.
    private func connectToEventSub(urlString: String = TwitchChatService.defaultEventSubURL) {
        guard let url = URL(string: urlString) else {
            Log.error("TwitchChatService: Invalid EventSub URL", category: "Twitch")
            setConnected(false)
            NotificationCenter.default.postTwitchConnectionState(isConnected: false)
            connectionStateContinuation.yield(false)
            return
        }

        // Defensively cancel any pre-existing task before reassigning. Call
        // paths currently route through `disconnectFromEventSub()` first, but a
        // direct double-connect would otherwise orphan a live task.
        webSocketTask?.cancel(with: .goingAway, reason: nil)

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

    // MARK: - Keepalive Watchdog

    /// Arms (or re-arms) the keepalive watchdog for `deadlineSeconds`. Cancels any
    /// existing watchdog first so there is never more than one pending. On expiry
    /// it reuses the proven transport-error teardown: `disconnectFromEventSub()`
    /// then `scheduleReconnect()`.
    private func armKeepaliveWatchdog(deadlineSeconds: TimeInterval) {
        keepaliveDeadlineSeconds = deadlineSeconds
        keepaliveWatchdogTask?.cancel()
        keepaliveWatchdogTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(deadlineSeconds))
            if Task.isCancelled { return }
            await self?.handleKeepaliveExpiry()
        }
    }

    /// Resets the keepalive watchdog to a full deadline. Called on every inbound
    /// frame. No-op until the watchdog has been armed by `session_welcome`.
    private func resetKeepaliveWatchdog() {
        guard keepaliveWatchdogTask != nil else { return }
        armKeepaliveWatchdog(deadlineSeconds: keepaliveDeadlineSeconds)
    }

    /// Cancels the keepalive watchdog.
    private func cancelKeepaliveWatchdog() {
        keepaliveWatchdogTask?.cancel()
        keepaliveWatchdogTask = nil
    }

    /// Called when no frame arrived before the keepalive deadline. Treated like a
    /// transport error: tear down and reconnect fresh (which re-subscribes).
    private func handleKeepaliveExpiry() async {
        Log.warn(
            "TwitchChatService: Keepalive watchdog fired (no frame within \(Int(keepaliveDeadlineSeconds))s); reconnecting",
            category: "Twitch")
        setConnected(false)
        NotificationCenter.default.postTwitchConnectionState(isConnected: false)
        connectionStateContinuation.yield(false)

        disconnectFromEventSub()

        if let channelName = reconnectChannelName,
           let token = reconnectToken,
           let clientID = reconnectClientID,
           !channelName.isEmpty, !token.isEmpty, !clientID.isEmpty,
           isNetworkReachable {
            scheduleReconnect()
        }
    }

    /// Called when session_welcome timeout expires.
    private func handleSessionWelcomeTimeout() async {
        guard sessionID == nil else { return } // If we already got a welcome, ignore

        // A welcome that never arrived means the (possibly migration) socket is
        // dead and we fall back to a fresh reconnect. Clear the migration flag so
        // the next fresh `session_welcome` re-subscribes normally. (disconnectFromEventSub
        // below also clears it, but reset here too so the contract is explicit and
        // independent of teardown ordering.)
        isMigratingSession = false

        Log.error(
            "TwitchChatService: Session welcome timeout - WebSocket may not be responding",
            category: "Twitch")
        setConnected(false)
        NotificationCenter.default.postTwitchConnectionState(isConnected: false)
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
        keepaliveWatchdogTask?.cancel()
        keepaliveWatchdogTask = nil
        isMigratingSession = false

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
        // A receive error on a migration socket leads to a fresh `scheduleReconnect`
        // below, NOT a reconnect_url migration. Clear the migration flag so the
        // resulting fresh `session_welcome` runs the normal `subscribeTo*` path
        // instead of being mistaken for a carried-over migrated session.
        isMigratingSession = false

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
        NotificationCenter.default.postTwitchConnectionState(
            isConnected: false, error: error.localizedDescription)
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
        // Any inbound frame is proof the connection is alive: reset the keepalive
        // watchdog before doing anything else, even if the frame later fails to
        // parse. A no-op until the watchdog has been armed by `session_welcome`.
        resetKeepaliveWatchdog()

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
        case "session_reconnect":
            await handleSessionReconnect(json)
        case "revocation":
            await handleRevocation(json)
        default:
            break
        }
    }

    /// Handles a `session_reconnect` message by migrating to the server-provided
    /// `reconnect_url`. The migrated session keeps its existing subscriptions, so
    /// the resulting `session_welcome` must NOT re-run the `subscribeTo*` calls.
    ///
    /// Safety: if the URL is missing/invalid OR anything goes wrong, fall back to
    /// the proven fresh-connect path (`disconnectFromEventSub()` +
    /// `scheduleReconnect()`), which re-subscribes. A brief event gap during the
    /// migration is acceptable; correctness beats zero-gap.
    private func handleSessionReconnect(_ json: [String: Any]) async {
        guard let url = TwitchChatService.reconnectURL(from: json) else {
            Log.warn(
                "TwitchChatService: session_reconnect missing a valid reconnect_url; reconnecting fresh",
                category: "Twitch")
            disconnectFromEventSub()
            scheduleReconnect()
            return
        }

        Log.info("TwitchChatService: Migrating EventSub session to reconnect_url", category: "Twitch")

        // Tear down only the old socket/receive loop; keep credentials and the
        // armed-deadline value. Mark migration so the next welcome skips re-subscribe.
        let oldTask = webSocketTask
        webSocketTask = nil
        sessionID = nil
        receiveTask?.cancel()
        receiveTask = nil
        keepaliveWatchdogTask?.cancel()
        keepaliveWatchdogTask = nil
        sessionWelcomeTask?.cancel()
        sessionWelcomeTask = nil

        isMigratingSession = true
        connectToEventSub(urlString: url)

        // Close the old socket only after the new connect was initiated, so the
        // new welcome can arrive without us re-entering the fresh path on close.
        oldTask?.cancel(with: .goingAway, reason: nil)
    }

    /// Handles a `revocation` message. Routes `authorization_revoked` to the
    /// shared re-auth signal and stops reconnecting; routes `user_removed` /
    /// `version_removed` to a safe full re-subscribe.
    private func handleRevocation(_ json: [String: Any]) async {
        guard let payload = json["payload"] as? [String: Any],
              let subscription = payload["subscription"] as? [String: Any] else {
            Log.warn("TwitchChatService: revocation missing subscription payload", category: "Twitch")
            return
        }
        let type = (subscription["type"] as? String) ?? ""
        let status = (subscription["status"] as? String) ?? ""

        switch TwitchChatService.revocationDisposition(type: type, status: status) {
        case .reauth:
            Log.error(
                "TwitchChatService: EventSub authorization revoked (\(type)); signaling re-auth",
                category: "Twitch")
            signalReauthNeededAndStop()
        case .resubscribe:
            Log.warn(
                "TwitchChatService: EventSub subscription revoked (\(type)/\(status)); re-subscribing",
                category: "Twitch")
            guard sessionID != nil else { return }
            await subscribeToChannelChatMessage()
            await subscribeToPollEvents()
            await subscribeToStreamEvents()
            await seedStreamLiveState()
            await subscribeToRedemptionsIfEnabled()
        case .ignore:
            Log.debug(
                "TwitchChatService: Ignoring revocation status \(status) for \(type)",
                category: "Twitch")
        }
    }

    /// Signals that interactive Twitch re-auth is required and stops the reconnect
    /// loop. Reuses the existing re-auth banner path (`Preferences` flag plus the
    /// `.twitchReauthNeededChanged` notification observed by `TwitchViewModel`).
    private func signalReauthNeededAndStop() {
        // Stop any pending/active reconnect so we don't burn attempts on a dead token.
        reconnectTask?.cancel()
        reconnectTask = nil
        reconnectionAttempts = 0

        disconnectFromEventSub()

        // Preferences is a `nonisolated enum`, safe to call from the actor.
        Preferences.setTwitchReauthNeeded(true)
        NotificationCenter.default.post(name: Notification.Name.twitchReauthNeededChanged, object: nil)
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

        // Arm the keepalive watchdog from the advertised timeout (+ grace).
        let timeout = TwitchChatService.keepaliveTimeoutSeconds(from: json)
            ?? AppConstants.Twitch.keepaliveDefaultTimeoutSeconds
        let deadline = TwitchChatService.keepaliveDeadline(
            timeoutSeconds: timeout, grace: AppConstants.Twitch.keepaliveGraceSeconds)
        armKeepaliveWatchdog(deadlineSeconds: deadline)

        setConnected(true)
        NotificationCenter.default.postTwitchConnectionState(isConnected: true)
        connectionStateContinuation.yield(true)

        // A `session_reconnect` migration carries its subscriptions to the new
        // session, so skip re-subscribing. Only fresh connects subscribe.
        if isMigratingSession {
            isMigratingSession = false
            Log.info(
                "TwitchChatService: Session migration complete; subscriptions carried over",
                category: "Twitch")
            return
        }

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

        Log.debug("TwitchChatService: handleNotification subType=\(subType)", category: "Twitch")

        switch subType {
        case AppConstants.Twitch.eventSubChatMessage:
            Log.debug("TwitchChatService: routing chat message → handleEventSubMessage", category: "Twitch")
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
            "TwitchChatService: Vote-skip poll ended: \(skipVotes) skip / \(keepVotes) keep",
            category: "Twitch")
        skipPollResultsContinuation.yield(SkipPollResult(skipVotes: skipVotes, keepVotes: keepVotes))
    }

    // MARK: - Vote-Skip Polls

    /// Creates a native Twitch poll asking chat to vote on skipping the current song.
    ///
    /// Requires the `channel:manage:polls` scope and Affiliate/Partner status.
    /// Missing either causes Twitch to reject the request, in which case this
    /// returns `false` and `SkipVoteManager` falls back to a chat tally.
    func createSkipPoll(title: String, durationSeconds: Int) async -> Bool {
        guard let broadcasterID,
              let token = oauthToken,
              let clientID else {
            Log.warn("TwitchChatService: Cannot create poll: missing credentials", category: "Twitch")
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

        let request: URLRequest
        do {
            request = try HelixClient.buildRequest(
                url: url, method: "POST",
                credentials: .init(token: token, clientID: clientID), body: body)
        } catch {
            Log.error(
                "TwitchChatService: Failed to serialize poll body - \(error.localizedDescription)",
                category: "Twitch")
            return false
        }

        do {
            let (data, http) = try await HTTPClient.shared.send(request)
            if (200..<300).contains(http.statusCode) {
                Log.info("TwitchChatService: Vote-skip poll created", category: "Twitch")
                return true
            }
            let text = String(data: data, encoding: .utf8) ?? "No response"
            Log.warn(
                "TwitchChatService: Poll creation failed: HTTP \(http.statusCode): \(text)",
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
            NotificationCenter.default.postTwitchConnectionState(isConnected: false)
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

        // Shares the EventSub POST scaffolding with every other subscription.
        // The chat subscription is the critical one: its extra success
        // side-effect is the connection confirmation message, and a failure
        // tears the connection back down.
        var sawAuthFailure = false
        let subscribed = await postEventSubSubscription(
            body: body,
            token: token,
            clientID: clientID,
            label: "channel.chat.message",
            onSuccess: {
                Log.info("TwitchChatService: Connected to chat", category: "Twitch")
                if shouldSendConnectionMessageOnSubscribe {
                    sendConnectionMessage()
                }
            },
            onFailureStatus: { status in
                // A 401 on the critical chat subscription means the token is dead.
                // The subscription runs async after `session_welcome`, so it can't
                // throw back into `attemptReconnect`; surface it as a re-auth signal.
                if status == 401 { sawAuthFailure = true }
            }
        )

        if !subscribed {
            setConnected(false)
            NotificationCenter.default.postTwitchConnectionState(isConnected: false)
            connectionStateContinuation.yield(false)
            if sawAuthFailure {
                Log.error(
                    "TwitchChatService: Chat subscription returned 401; signaling re-auth",
                    category: "Twitch")
                signalReauthNeededAndStop()
            }
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
              var components = URLComponents(string: apiBaseURL + "/streams") else { return }
        components.queryItems = [URLQueryItem(name: "user_id", value: broadcasterID)]
        guard let url = components.url else { return }

        do {
            let response: HelixStreamsResponse = try await HTTPClient.shared.get(
                url: url,
                headers: HelixClient.headers(for: .init(token: token, clientID: clientID)))
            let live = !response.data.isEmpty
            streamLive = live
            Log.info("TwitchChatService: Seeded stream-live state: live=\(live)", category: "Twitch")
        } catch {
            Log.debug(
                "TwitchChatService: Stream-live seed request failed - \(error.localizedDescription)",
                category: "Twitch")
        }
    }

    // MARK: - Redemption EventSub Subscriptions

    /// Subscribes to channel-point and/or bit EventSub events when the matching
    /// song-request features are enabled. Channel-point and bit subscriptions
    /// require the signed-in account to be the broadcaster. When a separate bot
    /// account is in use they are skipped and the UI is notified.
    private func subscribeToRedemptionsIfEnabled() async {
        let defaults = UserDefaults.standard

        // Channel-point and bit toggles are independent of the master switch, so
        // skip every redemption subscription while the feature as a whole is off.
        // Pause the managed reward first so it can't be redeemed at the source.
        guard defaults.bool(forKey: AppConstants.UserDefaults.songRequestEnabled) else {
            await pauseManagedRewardIfPossible()
            setRedemptionStatus(.ok)
            return
        }

        let channelPointsEnabled = defaults.bool(
            forKey: AppConstants.UserDefaults.songRequestChannelPointsEnabled)
        let bitsEnabled = defaults.bool(forKey: AppConstants.UserDefaults.songRequestBitsEnabled)

        // Channel points off but a reward may still exist on the channel: pause it
        // so viewers can't spend points on a request WolfWave would only refund.
        if !channelPointsEnabled {
            await pauseManagedRewardIfPossible()
        }

        guard channelPointsEnabled || bitsEnabled else {
            setRedemptionStatus(.ok)
            return
        }

        // Channel-point and bit EventSub require the broadcaster's own token.
        guard let broadcasterID, let botID, broadcasterID == botID else {
            Log.warn(
                "TwitchChatService: Redemption events need the broadcaster account, skipping",
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
            // Make sure a previously-paused reward is live again now that the
            // feature is on.
            try? await channelPointsService.setRewardPaused(
                credentials: credentials, rewardID: rewardID, paused: false)
            // Cost sync is non-fatal (the reward still works at its old cost),
            // but don't swallow the failure silently — surface it in the log.
            do {
                try await channelPointsService.updateRewardCost(
                    credentials: credentials, rewardID: rewardID, cost: cost)
            } catch {
                Log.warn(
                    "TwitchChatService: Couldn't sync channel-point reward cost; the reward still works at its current cost - \(error.localizedDescription)",
                    category: "Twitch")
            }
            await subscribeToChannelPointsRedemption()
            setRedemptionStatus(.ok)
        } catch {
            Log.error(
                "TwitchChatService: Failed to set up channel-point reward - \(error.localizedDescription)",
                category: "Twitch")
            setRedemptionStatus(.subscribeFailed)
        }
    }

    /// Pauses the WolfWave-managed channel-point reward so it can't be redeemed
    /// while channel-point requests are off. No-op when no reward was ever
    /// created or broadcaster credentials are unavailable.
    private func pauseManagedRewardIfPossible() async {
        let storedID = UserDefaults.standard.string(
            forKey: AppConstants.UserDefaults.songRequestChannelPointsRewardID) ?? ""
        guard !storedID.isEmpty, let credentials = currentChannelPointCredentials() else { return }
        do {
            try await channelPointsService.setRewardPaused(
                credentials: credentials, rewardID: storedID, paused: true)
            Log.info("TwitchChatService: Paused channel-point reward (requests off)", category: "Twitch")
        } catch {
            Log.error(
                "TwitchChatService: Failed to pause channel-point reward - \(error.localizedDescription)",
                category: "Twitch")
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
    ///
    /// - Parameters:
    ///   - onSuccess: Side effect run once on a 2xx response. Defaults to a
    ///     no-op; `subscribeToChannelChatMessage` uses it to send the connection
    ///     confirmation message.
    /// - Returns: `true` when the subscription is in place (2xx, or 409 "already
    ///   active"), `false` on any other failure. `subscribeToChannelChatMessage`
    ///   branches on this to decide whether the connection is healthy.
    @discardableResult
    private func postEventSubSubscription(
        body: [String: Any],
        token: String,
        clientID: String,
        label: String,
        onSuccess: () -> Void = {},
        onFailureStatus: (Int) -> Void = { _ in }
    ) async -> Bool {
        guard let url = URL(string: apiBaseURL + "/eventsub/subscriptions") else { return false }

        let request: URLRequest
        do {
            request = try HelixClient.buildRequest(
                url: url, method: "POST",
                credentials: .init(token: token, clientID: clientID), body: body)
        } catch {
            Log.error(
                "TwitchChatService: Failed to serialize \(label) subscription - \(error.localizedDescription)",
                category: "Twitch")
            return false
        }

        do {
            let (data, http) = try await HTTPClient.shared.send(request)
            if (200..<300).contains(http.statusCode) {
                Log.info("TwitchChatService: Subscribed to \(label)", category: "Twitch")
                onSuccess()
                return true
            } else if http.statusCode == 409 {
                Log.info("TwitchChatService: \(label) subscription already active", category: "Twitch")
                return true
            } else {
                let responseText = String(data: data, encoding: .utf8) ?? "No response"
                Log.error(
                    "TwitchChatService: \(label) subscription failed - HTTP \(http.statusCode) - \(responseText)",
                    category: "Twitch")
                if label == "channel-point redemptions" || label == "bit usage" {
                    setRedemptionStatus(http.statusCode == 403 ? .scopeMissing : .subscribeFailed)
                }
                onFailureStatus(http.statusCode)
                return false
            }
        } catch {
            Log.error(
                "TwitchChatService: \(label) subscription error - \(error.localizedDescription)",
                category: "Twitch")
            return false
        }
    }

    // MARK: - Redemption Event Handlers

    /// Handles a channel-point reward redemption. Ignores redemptions for any
    /// reward other than the WolfWave-managed one, routes the viewer's input
    /// into the song-request pipeline, then fulfils the redemption on success
    /// or cancels it (refunding the points) on failure.
    private func handleChannelPointsRedemption(_ payload: [String: Any]) {
        // Note: the enabled check happens inside the Task below (after we confirm
        // this is our reward), so a redemption that arrives while the feature is
        // off is refunded rather than silently swallowed.
        guard let event = payload["event"] as? [String: Any] else { return }

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
            guard let service = songRequestService else {
                // Service not wired up: the points were already spent, so refund
                // rather than strand the redemption in the pending state forever.
                await self.resolveRedemption(
                    credentials, rewardID: rewardID, redemptionID: redemptionID, as: .canceled)
                return
            }

            // Channel-point requests off (toggle flipped between subscribe and
            // redemption, or the reward wasn't paused in time): refund.
            guard UserDefaults.standard.bool(
                forKey: AppConstants.UserDefaults.songRequestChannelPointsEnabled) else {
                await self.sendMessage(
                    "@\(userName) channel-point song requests are off right now. Refunding your points.")
                await self.resolveRedemption(
                    credentials, rewardID: rewardID, redemptionID: redemptionID, as: .canceled)
                return
            }

            if userInput.isEmpty {
                await self.sendMessage(
                    "@\(userName) add a song name when you redeem. Refunding your points.")
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

            if boostEnabled, let boosted = await service.boost(username: userName) {
                await self.sendMessage(
                    "@\(userName) boosted \"\(boosted.title)\" to the front of the queue! (\(bits) bits)")
                return
            }

            guard !query.isEmpty else {
                if boostEnabled {
                    await self.sendMessage(
                        "@\(userName) no song of yours to boost. Include a song name in your cheer to request one.")
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
                "@\(username) added \"\(item.title)\" by \(item.artist), #\(position) in queue",
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
            let truncated = StringFormatting.truncatedWithEllipsis(query)
            return ("@\(username) no results for \"\(truncated)\". Points refunded.", .canceled)
        case .linkNotFound:
            return ("@\(username) couldn't find that on Apple Music. Points refunded.", .canceled)
        case .notAuthorized:
            return ("@\(username) song requests aren't available right now. Points refunded.", .canceled)
        case .featureDisabled:
            return ("@\(username) song requests are off right now. Points refunded.", .canceled)
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
            return "@\(username) added \"\(item.title)\" by \(item.artist), #\(position) in queue. Thanks for the bits!"
        case let .queueFull(max):
            return "@\(username) the queue is full (\(max)/\(max)). Try again soon!"
        case let .userLimitReached(max):
            return "@\(username) you already have \(max) songs queued."
        case .alreadyInQueue:
            return "@\(username) that song is already in the queue."
        case .blocked:
            return "@\(username) sorry, that song/artist is on the blocklist."
        case let .notFound(query):
            let truncated = StringFormatting.truncatedWithEllipsis(query)
            return "@\(username) no results for \"\(truncated)\"."
        case .linkNotFound:
            return "@\(username) couldn't find that on Apple Music."
        case .notAuthorized:
            return "@\(username) song requests aren't available right now."
        case .featureDisabled:
            return "@\(username) song requests are off right now."
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
        Preferences.int(AppConstants.UserDefaults.songRequestChannelPointsCost, default: 500)
    }

    /// Configured minimum bits required to trigger a request (default 100).
    nonisolated private func bitsMinimumSetting() -> Int {
        Preferences.int(AppConstants.UserDefaults.songRequestBitsMinimum, default: 100)
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

    /// Cached compiled pattern for the leading-cheermote strip. Compiling it per call on the
    /// hot chat path was wasteful. NSRegularExpression is thread-safe for matching.
    private nonisolated static let cheermotePrefixRegex = try? NSRegularExpression(
        pattern: "^(?:[Cc]heer[0-9]+\\s*)+")

    /// Removes leading `Cheer<amount>` tokens from a raw cheer message.
    nonisolated static func stripLeadingCheermotes(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard
            let regex = cheermotePrefixRegex,
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

        var request = try HelixClient.buildRequest(
            url: url, method: "GET",
            credentials: .init(token: token, clientID: clientID))
        request.timeoutInterval = 15

        do {
            let (data, http) = try await HTTPClient.shared.send(request)
            guard (200..<300).contains(http.statusCode) else {
                if http.statusCode == 401 { throw ConnectionError.authenticationFailed }
                throw ConnectionError.networkError("HTTP \(http.statusCode)")
            }

            let parsed: HelixUsersResponse
            do {
                parsed = try JSONCoders.snakeCase.decode(HelixUsersResponse.self, from: data)
            } catch {
                throw ConnectionError.networkError(
                    "Failed to decode username response: \(error.localizedDescription)")
            }

            guard let first = parsed.data.first, !first.id.isEmpty else {
                throw ConnectionError.networkError("Unable to resolve username")
            }
            return first.id
        } catch let error as ConnectionError {
            throw error
        } catch {
            Log.error(
                "TwitchChatService: Failed to resolve username - \(error.localizedDescription)",
                category: "Twitch")
            throw mapHelixError(error)
        }
    }


    /// Lock-protected registry for the three async track-info providers.
    ///
    /// Lives outside actor isolation so the sync dispatcher bridge can read
    /// providers without re-entering the actor. Tiny surface, single lock.
    /// Does not reintroduce the lock-sprawl the actor conversion removed.
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

}

