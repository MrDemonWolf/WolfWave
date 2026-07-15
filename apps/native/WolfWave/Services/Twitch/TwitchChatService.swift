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
nonisolated struct HelixUsersResponse: Decodable {
    struct User: Decodable {
        let id: String
        let login: String
        let displayName: String?
    }
    let data: [User]
}

/// `GET https://id.twitch.tv/oauth2/validate` response. Used by `validateToken`.
nonisolated struct TwitchValidateResponse: Decodable {
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
nonisolated struct HelixStreamsResponse: Decodable {
    struct Stream: Decodable {
        let id: String
        /// ISO-8601 stream start time, e.g. `2026-06-08T18:04:21Z`. Anchors the
        /// `!stats` "This stream" window when seeding mid-broadcast. Decoded from
        /// the JSON `started_at` field via the snake-case key strategy.
        let startedAt: String?
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

    /// Bounded, time-limited store of seen EventSub `message_id`s.
    ///
    /// Twitch EventSub is at-least-once delivery: duplicate notification frames
    /// (especially around `session_reconnect`) would re-run chat commands,
    /// channel-point redemptions, and bits events. IDs are remembered for `ttl`
    /// seconds (matching the 10-minute replay-age window in
    /// `handleWebSocketMessage`) and the store is capped, evicting oldest-first,
    /// so it can never grow without bound. A plain value type with an injectable
    /// clock so the insert/prune/duplicate contract is unit-testable without the
    /// actor or a live socket.
    struct EventSubMessageDeduplicator {
        /// How long a message ID stays remembered. Matches the replay-age
        /// rejection window applied to `metadata.message_timestamp`.
        private let ttl: TimeInterval
        /// Maximum number of remembered IDs; the oldest are evicted first.
        private let maxEntries: Int
        private var seen: [String: Date] = [:]

        init(ttl: TimeInterval = 600, maxEntries: Int = 500) {
            self.ttl = ttl
            self.maxEntries = max(1, maxEntries)
        }

        /// Records `id` as seen at `now` and reports whether it was already
        /// seen within the `ttl` window. Expired entries are pruned first; the
        /// size cap evicts the oldest entries after insertion.
        mutating func isDuplicate(_ id: String, now: Date = Date()) -> Bool {
            seen = seen.filter { now.timeIntervalSince($0.value) <= ttl }
            if seen[id] != nil { return true }
            seen[id] = now
            if seen.count > maxEntries {
                let overflowKeys = seen.sorted { $0.value < $1.value }
                    .prefix(seen.count - maxEntries)
                    .map(\.key)
                for key in overflowKeys { seen.removeValue(forKey: key) }
            }
            return false
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

    let apiBaseURL = AppConstants.Twitch.apiBaseURL
    /// `BotCommandDispatcher` is `@MainActor` (project default). The actor
    /// holds it as `nonisolated` (it's auto-Sendable since it's MainActor) and
    /// hops to `MainActor.run` for every call into it.
    nonisolated let commandDispatcher: BotCommandDispatcher
    let channelPointsService = TwitchChannelPointsService()
    private let rateLimiter = RateLimiter()

    let urlSession: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 60
        config.timeoutIntervalForResource = 300
        config.waitsForConnectivity = true
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: config)
    }()

    let maxReconnectionAttempts = AppConstants.Twitch.maxReconnectionAttempts
    let maxNetworkReconnectCycles = AppConstants.Twitch.maxNetworkReconnectCycles
    private let maxMessageRetries = AppConstants.Twitch.maxMessageRetries

    // MARK: - WebSocket / Session

    var webSocketTask: URLSessionWebSocketTask?
    var sessionID: String?
    var receiveTask: Task<Void, Never>?

    /// Keepalive watchdog. Armed after `session_welcome` from the advertised
    /// `keepalive_timeout_seconds` (+ grace) and reset on every inbound frame.
    /// Firing means Twitch went quiet past the deadline, so we tear down and
    /// reconnect via the proven fresh-connect path.
    var keepaliveWatchdogTask: Task<Void, Never>?

    /// Current keepalive deadline (seconds) used when the watchdog re-arms on
    /// each inbound frame. Set from the `session_welcome` payload.
    var keepaliveDeadlineSeconds: TimeInterval = AppConstants.Twitch.keepaliveDefaultTimeoutSeconds

    /// True while a `session_reconnect` migration is in flight. The resulting
    /// `session_welcome` then only re-arms the watchdog and flips connected,
    /// skipping the `subscribeTo*` calls because subscriptions migrate with the
    /// reconnect_url session.
    var isMigratingSession = false

    /// Dedup store for inbound EventSub frames. Twitch delivers at-least-once,
    /// so `handleWebSocketMessage` drops any frame whose `metadata.message_id`
    /// was already seen. Actor-isolated, mutated only on the actor.
    var messageDeduplicator = EventSubMessageDeduplicator()

    // MARK: - Credentials

    var broadcasterID: String?
    var botID: String?
    var oauthToken: String?
    var clientID: String?
    var botUsername: String?

    /// Live `SongRequestService`, used by the channel-point and bit redemption
    /// handlers. Set once by `AppDelegate` at startup via `setSongRequestService(_:)`.
    var songRequestService: SongRequestService?

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
    var streamLive = false {
        didSet { streamLiveSnapshot.set(streamLive) }
    }

    /// When the current stream went live, or `nil` when offline. Anchors the
    /// `!stats` command's "This stream" window. Seeded from Helix `started_at` on
    /// connect and updated by the `stream.online` / `stream.offline` events.
    var streamLiveSince: Date? {
        didSet { streamSinceSnapshot.set(streamLiveSince) }
    }

    /// Nonisolated mirror of `_connected` so MainActor UI code (status chips,
    /// menu bar enable state) can read it without `await`.
    nonisolated let isConnectedSnapshot = Atomic(false)

    /// Nonisolated read of the connection state, mirroring the actor-isolated
    /// `isConnected`. Lets synchronous MainActor callers (menu bar, status
    /// chips, settings panes) check the connection without `await` instead of
    /// reaching through `isConnectedSnapshot.value` at every site.
    nonisolated var currentlyConnected: Bool { isConnectedSnapshot.value }

    /// Nonisolated mirror of `streamLive` so the synchronous dispatcher bridge
    /// (`!stats` enable check) can read it without re-entering the actor.
    nonisolated private let streamLiveSnapshot = Atomic(false)

    /// Nonisolated mirror of `streamLiveSince` so the synchronous `!stats`
    /// provider (MainActor) can read the stream's start time without `await`.
    nonisolated private let streamSinceSnapshot = Atomic<Date?>(nil)

    /// When the current stream went live, or `nil` when offline. Readable from any
    /// isolation (mirrors the actor-isolated `streamLiveSince`).
    nonisolated var currentStreamLiveSince: Date? { streamSinceSnapshot.value }

    var isConnected: Bool { _connected }

    /// Whether the broadcaster's stream is currently live.
    ///
    /// Maintained by the `stream.online` / `stream.offline` EventSub events and
    /// seeded by a one-shot Helix check on connect. The `!stats` command stays
    /// silent unless this is `true`.
    var isStreamLive: Bool { streamLive }

    func setConnected(_ value: Bool) {
        _connected = value
    }

    /// Broadcasts a connection-state transition to every consumer surface: the
    /// actor's `_connected` flag (and its atomic mirror), the NotificationCenter
    /// post observed by the UI, and every per-subscriber connection-state
    /// stream. The single write path for connection-state transitions.
    ///
    /// - Parameter error: Optional failure description attached to the
    ///   notification payload (transport errors only).
    func broadcastConnectionState(_ connected: Bool, error: String? = nil) {
        setConnected(connected)
        NotificationCenter.default.postTwitchConnectionState(isConnected: connected, error: error)
        connectionStateHub.yield(connected)
    }

    // MARK: - Disconnect / Network State

    var isProcessingDisconnect = false
    var networkPathMonitor: NWPathMonitor?
    let networkMonitorQueue = DispatchQueue(
        label: "com.mrdemonwolf.wolfwave.networkmonitor")
    var isNetworkReachable = true

    // MARK: - Reconnection State

    var reconnectionAttempts = 0
    var reconnectTask: Task<Void, Never>?
    var sessionWelcomeTask: Task<Void, Never>?
    private var connectionMessageTask: Task<Void, Never>?

    /// Tracks total network-triggered reconnect cycles to prevent infinite loops
    /// when the network path flaps repeatedly.
    var networkReconnectCycles = 0
    var lastNetworkReconnectTime: TimeInterval = 0

    var reconnectChannelName: String?
    var reconnectToken: String?
    var reconnectClientID: String?

    // MARK: - Pending Messages

    private var pendingMessages: [PendingMessage] = []
    private var pendingRetryTask: Task<Void, Never>?

    // MARK: - Redemption Pipeline Tasks

    /// In-flight channel-point / bits pipeline tasks, keyed so each removes
    /// itself on completion. Tracked so `leaveChannel()` and `deinit` cancel
    /// them instead of letting them outlive the connection (every other
    /// long-running task in this actor is tracked the same way).
    var redemptionTasks: [UUID: Task<Void, Never>] = [:]

    // MARK: - AsyncStream Outputs

    /// Stream of chat messages received via EventSub `channel.chat.message`.
    nonisolated let chatMessages: AsyncStream<ChatMessage>
    /// Stream of finished vote-skip poll tallies.
    nonisolated let skipPollResults: AsyncStream<SkipPollResult>

    let chatMessagesContinuation: AsyncStream<ChatMessage>.Continuation
    let skipPollResultsContinuation: AsyncStream<SkipPollResult>.Continuation

    /// Fan-out registry backing `connectionStateChanges()`. One continuation
    /// per live subscriber; `broadcastConnectionState` yields to all of them.
    nonisolated private let connectionStateHub = ConnectionStateHub()

    /// Returns a fresh stream of connection state transitions (`true` = connected).
    ///
    /// Each call registers its own subscriber, so multiple consumers all
    /// receive every transition, and cancelling one consumer (e.g. a settings
    /// window closing its view model) never finishes anyone else's stream.
    nonisolated func connectionStateChanges() -> AsyncStream<Bool> {
        connectionStateHub.subscribe()
    }

    // MARK: - Init / Deinit

    /// Marked `@MainActor` so `BotCommandDispatcher()` (a MainActor type under
    /// project default isolation) can be constructed at init time. AppDelegate
    /// runs on MainActor; tests call from MainActor (Swift Testing) or wrap.
    @MainActor init() {
        let chat = AsyncStream.makeStream(
            of: ChatMessage.self,
            bufferingPolicy: .bufferingNewest(AppConstants.Twitch.chatMessageStreamBuffer))
        let skip = AsyncStream.makeStream(
            of: SkipPollResult.self,
            bufferingPolicy: .bufferingNewest(AppConstants.Twitch.controlStreamBuffer))

        self.chatMessages = chat.stream
        self.chatMessagesContinuation = chat.continuation
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
        redemptionTasks.values.forEach { $0.cancel() }
        networkPathMonitor?.cancel()
        webSocketTask?.cancel(with: .goingAway, reason: nil)
        chatMessagesContinuation.finish()
        connectionStateHub.finish()
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

    // Network monitoring + reconnection lifecycle lives in TwitchChatService+Connection.swift

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
        // Live values for custom-command variables (`$song`, `$lastsong`). Reuses
        // the same now-playing providers the built-in `!song` / `!last` commands
        // read, so a custom command like "!np → Now playing: $song" stays in sync.
        let customCommandVariables: @Sendable () async -> CustomCommandVariables = {
            let song: String
            if let provider = providers.current() { song = await provider() } else { song = "" }
            let last: String
            if let provider = providers.last() { last = await provider() } else { last = "" }
            return CustomCommandVariables(currentSong: song, lastSong: last)
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
            commandDispatcher.setCustomCommandVariablesProvider(customCommandVariables)
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

    // Bot identity + token/username resolution lives in TwitchChatService+Auth.swift

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

        // Signal in-flight redemption pipelines to stop chatting; each still
        // resolves (fulfils/refunds) its redemption so viewer points never
        // strand in the pending state.
        redemptionTasks.values.forEach { $0.cancel() }
        redemptionTasks.removeAll()

        broadcasterID = nil
        botID = nil
        oauthToken = nil
        clientID = nil
        hasSentConnectionMessage = false

        broadcastConnectionState(false)

        Log.info("TwitchChatService: Left channel", category: "Twitch")
    }

    // Token validation lives in TwitchChatService+Auth.swift

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
    /// `attempts: 0`. The drain loop does NOT call this method; it calls
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
        } catch ConnectionError.authenticationFailed {
            // Token rejected mid-session. Surface the re-auth banner and stop
            // the reconnect loop instead of silently dropping every send.
            Log.error(
                "TwitchChatService: Send rejected (401/403) - token invalid. Signaling re-auth.",
                category: "Twitch")
            signalReauthNeededAndStop()
            return false
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

    // EventSub message parsing (handleEventSubMessage) lives in TwitchChatService+EventSub.swift

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
            // 401/403 are never a success for any caller: the token is expired
            // or missing the required scope. Throw so callers don't decode a
            // success-shaped struct from the error body and silently treat the
            // request as sent (which would make the bot go dark with no signal).
            if http.statusCode == 401 || http.statusCode == 403 {
                throw ConnectionError.authenticationFailed
            }
        }

        return data
    }

    // WebSocket connection management lives in TwitchChatService+Connection.swift

    // Keepalive watchdog + WebSocket receive loop live in TwitchChatService+Connection.swift

    // EventSub message routing (handleWebSocketMessage, handleSessionReconnect,
    // handleRevocation, signalReauthNeededAndStop, handleSessionWelcome,
    // handleNotification, handlePollEndEvent) lives in TwitchChatService+EventSub.swift

    // Vote-skip polls, stream-state handling, and EventSub subscriptions
    // (createSkipPoll, subscribeToPollEvents, handleStreamStateNotification,
    // subscribeToChannelChatMessage, subscribeToStreamEvents, seedStreamLiveState,
    // postEventSubSubscription) live in TwitchChatService+EventSub.swift

    // Redemption EventSub subscriptions (subscribeToRedemptionsIfEnabled,
    // refreshRedemptionSubscriptions, ensureSongRequestRewardAndSubscribe,
    // pauseManagedRewardIfPossible, subscribeToChannelPointsRedemption,
    // subscribeToBitsUse) live in TwitchChatService+Redemptions.swift

    // Redemption event handlers (handleChannelPointsRedemption,
    // runChannelPointsRedemption, clearRedemptionTask, handleBitsUse, runBitsUse)
    // live in TwitchChatService+Redemptions.swift

    // Redemption helpers (resolveRedemption, redemptionOutcome, bitsOutcomeMessage,
    // currentChannelPointCredentials, channelPointsCostSetting, bitsMinimumSetting,
    // setRedemptionStatus, cleanBitsMessage, stripLeadingCheermotes) live in
    // TwitchChatService+Redemptions.swift

    // Channel/username resolution (validateChannelExists, resolveUsername) lives in
    // TwitchChatService+Auth.swift

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

    /// Lock-protected fan-out registry for connection-state subscribers.
    ///
    /// A single shared `AsyncStream` is unicast: the first consumer's
    /// cancellation finishes the shared continuation, silently dropping every
    /// later yield for the process lifetime, and two concurrent consumers
    /// split events arbitrarily. Instead, each `subscribe()` call returns a
    /// fresh stream backed by its own continuation, `yield(_:)` broadcasts to
    /// every live subscriber, and a stream's termination removes only that
    /// subscriber (mirrors `NetworkInfoService.pathUpdates()`). Its own type
    /// so the fan-out contract is unit-testable without the actor or a socket.
    final class ConnectionStateHub: @unchecked Sendable {
        private let lock = NSLock()
        private var continuations: [UUID: AsyncStream<Bool>.Continuation] = [:]

        /// Returns a fresh connection-state stream for one subscriber. The
        /// subscriber is registered synchronously, so yields after this call
        /// returns are buffered even before iteration starts.
        func subscribe() -> AsyncStream<Bool> {
            AsyncStream(bufferingPolicy: .bufferingNewest(AppConstants.Twitch.controlStreamBuffer)) { continuation in
                let id = UUID()
                lock.withLock { continuations[id] = continuation }
                continuation.onTermination = { [weak self] _ in
                    guard let self else { return }
                    self.lock.withLock { _ = self.continuations.removeValue(forKey: id) }
                }
            }
        }

        /// Yields `value` to every live subscriber.
        func yield(_ value: Bool) {
            let subscribers = lock.withLock { continuations }
            for continuation in subscribers.values { continuation.yield(value) }
        }

        /// Finishes every subscriber's stream and empties the registry.
        func finish() {
            let subscribers = lock.withLock {
                let snapshot = continuations
                continuations.removeAll()
                return snapshot
            }
            for continuation in subscribers.values { continuation.finish() }
        }
    }

}

