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
    let clientID: String?
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

/// What a live token-validation request proves about the Polls OAuth scope.
nonisolated enum PollScopeValidation: Equatable, Sendable {
    case present
    case missing
    case indeterminate
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

    /// Result of one attempt to send a chat message.
    ///
    /// Only ``retryableFailure`` enters the bounded retry queue. A permanent
    /// rejection (bad request, missing permission, Automod drop, or an
    /// indeterminate success payload) must not be retried: doing so either wastes
    /// requests or risks posting a duplicate message after Twitch already
    /// accepted the original request.
    enum ChatSendOutcome: Sendable, Equatable {
        case sent
        case retryableFailure
        case permanentFailure
    }

    /// Classification for a final Helix HTTP response after the one inline
    /// rate-limit retry has already been attempted.
    enum HelixResponseDisposition: Sendable, Equatable {
        case success
        case authenticationFailure
        case retryableFailure
        case permanentFailure
    }

    /// Internal error used to preserve the retryability classification from the
    /// Helix HTTP layer through response decoding.
    private enum HelixRequestError: Error {
        case retryableHTTP(statusCode: Int)
        case permanentHTTP(statusCode: Int)
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

    /// Outcome of checking a stored OAuth token with Twitch.
    ///
    /// Only ``invalid`` authorizes callers to expire the local session. Network
    /// failures, rate limits, server errors, and malformed success payloads are
    /// deliberately ``temporarilyUnavailable`` so an outage cannot erase or
    /// revoke otherwise usable credentials.
    enum TokenValidationResult: Sendable, Equatable {
        case valid
        case invalid
        case temporarilyUnavailable
    }

    /// Tuple-style payload posted on a `channel.poll.end` for a vote-skip poll.
    struct SkipPollResult: Sendable {
        let pollID: String
        let skipVotes: Int
        let keepVotes: Int
    }

    /// How a `revocation` EventSub message should be handled.
    ///
    /// Twitch revocation statuses have materially different recovery paths.
    /// Keeping those paths explicit prevents terminal permission/account states
    /// from entering an endless reconnect loop while still recovering transport
    /// and maintenance revocations with the normal bounded backoff.
    enum RevocationDisposition: Sendable, Equatable {
        /// Token is no longer valid; surface the re-auth banner and stop reconnecting.
        case reauth
        /// The Twitch account no longer exists; stop without asking for re-auth.
        case accountUnavailable
        /// Twitch retired the subscription version; a client update is required.
        case clientUpdateRequired
        /// Moderator/chat access was removed; the channel capability is terminal.
        case permissionLost
        /// Twitch maintenance or WebSocket delivery failure; reconnect with backoff.
        case reconnect
        /// Unrecognized status; do nothing (log only).
        case ignore
    }

    // MARK: - EventSub Decision Helpers (nonisolated, pure, testable)

    private nonisolated static let minimumKeepaliveTimeoutSeconds: TimeInterval = 10
    private nonisolated static let maximumKeepaliveTimeoutSeconds: TimeInterval = 600
    nonisolated static let maximumKeepaliveDeadlineSeconds: TimeInterval =
        maximumKeepaliveTimeoutSeconds + AppConstants.Twitch.keepaliveGraceSeconds

    private nonisolated static func validatedKeepaliveTimeout(
        _ seconds: TimeInterval
    ) -> TimeInterval? {
        guard seconds.isFinite,
              seconds.rounded(.towardZero) == seconds,
              seconds >= minimumKeepaliveTimeoutSeconds,
              seconds <= maximumKeepaliveTimeoutSeconds else { return nil }
        return seconds
    }

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
              scheme == "wss",
              url.host != nil else {
            return nil
        }
        return trimmed
    }

    /// Reads `payload.session.keepalive_timeout_seconds` from a `session_welcome`
    /// message. Returns `nil` when the field is missing, non-integral, or outside
    /// the documented 10...600-second range so the caller uses a safe default.
    nonisolated static func keepaliveTimeoutSeconds(from json: [String: Any]) -> TimeInterval? {
        guard let payload = json["payload"] as? [String: Any],
              let session = payload["session"] as? [String: Any] else {
            return nil
        }
        // Twitch sends an integer, but tolerate a numeric string too.
        if let intValue = session["keepalive_timeout_seconds"] as? Int {
            guard intValue >= Int(minimumKeepaliveTimeoutSeconds),
                  intValue <= Int(maximumKeepaliveTimeoutSeconds) else { return nil }
            return TimeInterval(intValue)
        }
        if let doubleValue = session["keepalive_timeout_seconds"] as? Double {
            return validatedKeepaliveTimeout(doubleValue)
        }
        if let stringValue = session["keepalive_timeout_seconds"] as? String,
           let parsed = TimeInterval(
               stringValue.trimmingCharacters(in: .whitespacesAndNewlines)) {
            return validatedKeepaliveTimeout(parsed)
        }
        return nil
    }

    /// Computes the keepalive watchdog deadline: the advertised timeout plus a
    /// grace period. Invalid values fall back to the protocol default, and the
    /// result is capped so watchdog sleep can never receive an unsafe duration.
    nonisolated static func keepaliveDeadline(
        timeoutSeconds: TimeInterval,
        grace: TimeInterval
    ) -> TimeInterval {
        let safeTimeout = validatedKeepaliveTimeout(timeoutSeconds)
            ?? AppConstants.Twitch.keepaliveDefaultTimeoutSeconds
        let safeGrace = grace.isFinite ? max(0, grace) : 0
        let deadline = safeTimeout + safeGrace
        guard deadline.isFinite else {
            return AppConstants.Twitch.keepaliveDefaultTimeoutSeconds
                + AppConstants.Twitch.keepaliveGraceSeconds
        }
        return min(deadline, maximumKeepaliveDeadlineSeconds)
    }

    nonisolated static func normalizedKeepaliveDeadline(
        _ seconds: TimeInterval
    ) -> TimeInterval {
        guard seconds.isFinite,
              seconds >= minimumKeepaliveTimeoutSeconds,
              seconds <= maximumKeepaliveDeadlineSeconds else {
            return keepaliveDeadline(
                timeoutSeconds: AppConstants.Twitch.keepaliveDefaultTimeoutSeconds,
                grace: AppConstants.Twitch.keepaliveGraceSeconds)
        }
        return seconds
    }

    /// Classifies a Helix response without conflating permanent client errors
    /// with transient capacity/transport failures.
    nonisolated static func helixResponseDisposition(
        for statusCode: Int
    ) -> HelixResponseDisposition {
        switch statusCode {
        case 200..<300:
            return .success
        case 401:
            return .authenticationFailure
        case 408, 425, 429, 500...599:
            return .retryableFailure
        default:
            return .permanentFailure
        }
    }

    /// Only explicitly transient outcomes may enter the bounded retry queue.
    nonisolated static func shouldRetryChatSend(_ outcome: ChatSendOutcome) -> Bool {
        outcome == .retryableFailure
    }

    /// Returns the next 1-based reconnect attempt, or `nil` once the configured
    /// cap has been consumed. The counter advances when an attempt begins and is
    /// reset after EventSub sends `session_welcome` or an accepted network-
    /// recovery cycle starts a fresh bounded budget.
    nonisolated static func nextReconnectAttempt(
        after attempts: Int,
        maximum: Int
    ) -> Int? {
        guard attempts >= 0, attempts < maximum else { return nil }
        return attempts + 1
    }

    /// Cheap off-MainActor prefilter for the command dispatcher. All built-in,
    /// alias, and custom triggers are normalized to a leading `!`. Skipping
    /// leading whitespace preserves the dispatcher's existing trim behavior.
    nonisolated static func isPotentialCommand(_ message: String) -> Bool {
        message.first(where: { !$0.isWhitespace }) == "!"
    }

    /// Maps a `revocation` subscription `(type, status)` to a disposition.
    ///
    /// `status` drives the decision; `type` is accepted for future per-type
    /// granularity and logging. The mapping follows Twitch's EventSub status
    /// table and deliberately separates terminal identity/version/permission
    /// outcomes from transient WebSocket and maintenance failures.
    nonisolated static func revocationDisposition(
        type: String,
        status: String
    ) -> RevocationDisposition {
        _ = type
        switch status {
        case "authorization_revoked":
            return .reauth
        case "user_removed":
            return .accountUnavailable
        case "version_removed":
            return .clientUpdateRequired
        case "moderator_removed", "chat_user_banned":
            return .permissionLost
        case "beta_maintenance",
             "websocket_disconnected",
             "websocket_failed_ping_pong",
             "websocket_received_inbound_traffic",
             "websocket_connection_unused",
             "websocket_internal_error",
             "websocket_network_timeout",
             "websocket_network_error",
             "websocket_failed_to_reconnect":
            return .reconnect
        default:
            return .ignore
        }
    }

    /// Time-limited store of seen EventSub `message_id`s, optionally count-capped.
    ///
    /// Twitch EventSub is at-least-once delivery: duplicate notification frames
    /// (especially around `session_reconnect`) would re-run chat commands,
    /// channel-point redemptions, and bits events. IDs are remembered for `ttl`
    /// seconds (matching the 10-minute replay-age window in
    /// `handleWebSocketMessage`). The general transport store is count-capped;
    /// command reservations use TTL-only retention so unrelated chat cannot
    /// evict them. A plain value type with an injectable clock keeps the
    /// insert/prune/duplicate contract testable without the actor or a socket.
    struct EventSubMessageDeduplicator {
        private struct Entry {
            let id: String
            let seenAt: Date
        }

        /// How long a message ID stays remembered. Matches the replay-age
        /// rejection window applied to `metadata.message_timestamp`.
        private let ttl: TimeInterval
        /// Optional maximum number of remembered IDs; oldest are evicted first.
        private let maxEntries: Int?
        private var seen: [String: Date] = [:]
        /// Append-only insertion order with a moving head. This makes normal
        /// prune/evict operations O(1) amortized instead of filtering and sorting
        /// the complete dictionary for every busy-chat frame.
        private var insertionOrder: [Entry] = []
        private var insertionHead = 0

        var entryCount: Int { seen.count }

        init(ttl: TimeInterval = 600, maxEntries: Int? = 500) {
            self.ttl = ttl
            self.maxEntries = maxEntries.map { max(1, $0) }
        }

        /// Records `id` as seen at `now` and reports whether it was already
        /// seen within the `ttl` window. Expired entries are pruned first; the
        /// optional size cap evicts the oldest entries after insertion.
        mutating func isDuplicate(_ id: String, now: Date = Date()) -> Bool {
            pruneExpired(now: now)
            if seen[id] != nil { return true }

            seen[id] = now
            insertionOrder.append(Entry(id: id, seenAt: now))

            if let maxEntries {
                while seen.count > maxEntries, insertionHead < insertionOrder.count {
                    let oldest = insertionOrder[insertionHead]
                    insertionHead += 1
                    // An ID can be reinserted after an earlier entry expired or was
                    // evicted. Remove only if this queue node is still authoritative.
                    if seen[oldest.id] == oldest.seenAt {
                        seen.removeValue(forKey: oldest.id)
                    }
                }
            }
            compactInsertionOrderIfNeeded()
            return false
        }

        private mutating func pruneExpired(now: Date) {
            while insertionHead < insertionOrder.count {
                let oldest = insertionOrder[insertionHead]
                guard now.timeIntervalSince(oldest.seenAt) > ttl else { break }
                insertionHead += 1
                if seen[oldest.id] == oldest.seenAt {
                    seen.removeValue(forKey: oldest.id)
                }
            }
            compactInsertionOrderIfNeeded()
        }

        /// Periodically reclaims consumed prefix storage. The occasional O(n)
        /// copy is amortized over hundreds of O(1) frame operations.
        private mutating func compactInsertionOrderIfNeeded() {
            guard insertionHead >= 256,
                  insertionHead * 2 >= insertionOrder.count else { return }
            insertionOrder.removeFirst(insertionHead)
            insertionHead = 0
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
    let channelPointsService: TwitchChannelPointsService
    let redemptionResolutionOutbox: TwitchRedemptionResolutionOutbox
    let redemptionClientIDProvider: @Sendable () -> String?
    let eventSubWebSocketFactory: (@Sendable (URL) -> URLSessionWebSocketTask)?
    let eventSubWebSocketResume: @Sendable (URLSessionWebSocketTask) -> Void
    let eventSubWebSocketReceive: @Sendable (URLSessionWebSocketTask) async throws
        -> URLSessionWebSocketTask.Message
    private let rateLimiter = RateLimiter()

    let urlSession: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 60
        config.timeoutIntervalForResource = 300
        config.waitsForConnectivity = true
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: config)
    }()
    /// Narrow injection seam for EventSub subscription POST/DELETE tests.
    let eventSubHTTPClient: HTTPClient
    /// Helix request client used by chat sends and other actor-owned API calls.
    let helixHTTPClient: HTTPClient

    let maxReconnectionAttempts = AppConstants.Twitch.maxReconnectionAttempts
    let maxNetworkReconnectCycles = AppConstants.Twitch.maxNetworkReconnectCycles
    private let maxMessageRetries = AppConstants.Twitch.maxMessageRetries

    // MARK: - WebSocket / Session

    var webSocketTask: URLSessionWebSocketTask?
    var sessionID: String?
    var receiveTask: Task<Void, Never>?
    /// EventSub session where channel.poll.end is known to be subscribed.
    var pollSubscriptionSessionID: String?
    /// Session currently awaiting a poll-subscription POST.
    var pollSubscriptionAttemptSessionID: String?
    /// Narrow deterministic seams for live-toggle tests.
    var pollScopeValidationOverride: (@Sendable () async -> PollScopeValidation)?
    var pollSubscriptionOverride: (@Sendable (String) async -> Bool)?

    /// During Twitch's `session_reconnect` handoff the source socket must stay
    /// open and continue delivering events until the replacement sends welcome.
    /// These fields retain that source independently from the new current socket.
    var migrationSourceWebSocketTask: URLSessionWebSocketTask?
    var migrationSourceReceiveTask: Task<Void, Never>?
    /// Socket that most recently completed the welcome handshake. Unlike
    /// `sessionID`, object identity distinguishes the old welcomed session from
    /// a replacement socket that is still waiting for its own welcome.
    var welcomedWebSocketTask: URLSessionWebSocketTask?

    /// One long-lived keepalive watchdog per EventSub session. Inbound frames
    /// update ``lastKeepaliveActivity`` instead of cancelling and allocating a
    /// new sleeping task for every busy-chat message.
    var keepaliveWatchdogTask: Task<Void, Never>?
    var lastKeepaliveActivity: ContinuousClock.Instant?
    /// Invalidates a watchdog that was cancelled just before it re-entered the actor.
    var keepaliveGeneration: UInt64 = 0
    /// Diagnostic counter that also locks the one-task-per-session contract in tests.
    var keepaliveWatchdogTaskStarts = 0

    /// Current keepalive deadline (seconds), set from `session_welcome`.
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
    /// Command-shaped chat IDs retain the complete replay TTL. Ordinary chat
    /// volume must not evict a delayed duplicate before it can rerun a command.
    var commandMessageDeduplicator = EventSubMessageDeduplicator(maxEntries: nil)

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
        // State streams model transitions, not repeated teardown calls. Preserve
        // an explicit error notification even if the state was already false.
        guard _connected != connected || error != nil else { return }
        setConnected(connected)
        // Post on the main actor: this runs on the actor's background executor,
        // and SwiftUI panes observe via NotificationCenter.publisher + .onReceive,
        // which delivers synchronously on the posting thread with no main hop.
        // Mutating MainActor view state off-main is the documented executor-assert
        // SIGTRAP class, so hop here to cover every current and future observer.
        Task { @MainActor in
            NotificationCenter.default.postTwitchConnectionState(isConnected: connected, error: error)
        }
        connectionStateHub.yield(connected)
    }

    // MARK: - Disconnect / Network State

    var isProcessingDisconnect = false
    /// Synchronous signal observed by the receive loop after its socket is
    /// closed for credential teardown. Unlike cancelling the receive task, this
    /// lets a frame already awaiting actor admission finish paid-event intake.
    nonisolated let eventSubTeardownQuiescing = Atomic(false)
    var eventSubCredentialTeardownFenceDepth = 0
    /// Invalidates channel joins that resume after a leave or a newer connect attempt.
    var connectionGeneration: UInt64 = 0
    /// Changes only for an explicit public join/connect, not automatic transport
    /// reconnects. A leave suspended on its final reward pause uses this to avoid
    /// clearing a newer same-account user-initiated join.
    var channelOwnershipGeneration: UInt64 = 0

    /// Ownership captured by one EventSub receive loop. Both the logical
    /// generation and WebSocket object identity must still match after an await.
    struct EventSubReceiveContext: Sendable {
        let generation: UInt64
        let webSocketTask: URLSessionWebSocketTask
    }

    func receiveContextIsCurrent(_ context: EventSubReceiveContext?) -> Bool {
        guard !Task.isCancelled else { return false }
        guard let context else { return true }
        return connectionAttemptIsCurrent(context.generation)
            && (webSocketTask === context.webSocketTask
                || migrationSourceWebSocketTask === context.webSocketTask)
    }
    var networkPathMonitor: NWPathMonitor?
    /// Invalidates callbacks already queued by a canceled/replaced path monitor.
    var networkMonitorGeneration: UInt64 = 0
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

    /// Single service seam for every live 401. The rejected access expectation
    /// is mandatory so an old request can never refresh a replacement account.
    private var reactiveTokenRefreshOperation: @Sendable (
        String,
        TwitchCredentialStore.AccessExpectation
    ) async throws -> TwitchTokenRefresher.RefreshResult = { clientID, expected in
        try await TwitchTokenRefresher.attemptReactiveRefresh(
            clientID: clientID,
            expected: expected
        )
    }

    var redemptionResolutionSleep: @Sendable (Duration) async throws -> Void = {
        try await Task.sleep(for: $0)
    }

    func setReactiveTokenRefresh(
        _ operation: @escaping @Sendable (
            String,
            TwitchCredentialStore.AccessExpectation
        ) async throws -> TwitchTokenRefresher.RefreshResult
    ) {
        reactiveTokenRefreshOperation = operation
    }

    /// Runs the injectable refresher for the exact credential rejected by an
    /// earlier request.
    func reactiveTokenRefresh(
        _ clientID: String,
        expected: TwitchCredentialStore.AccessExpectation
    ) async throws -> TwitchTokenRefresher.RefreshResult {
        try await reactiveTokenRefreshOperation(clientID, expected)
    }

    func setRedemptionResolutionSleep(
        _ operation: @escaping @Sendable (Duration) async throws -> Void
    ) {
        redemptionResolutionSleep = operation
    }

    // MARK: - Pending Messages

    private var pendingMessages: [PendingMessage] = []
    private var pendingRetryTask: Task<Void, Never>?
    /// Invalidates a cancelled drain so its deferred cleanup cannot clear a newer task.
    private var pendingRetryGeneration: UInt64 = 0

    /// Read-only lifecycle snapshots used by diagnostics and focused tests.
    var pendingMessageCount: Int { pendingMessages.count }
    var hasPendingMessageRetry: Bool { pendingRetryTask != nil }

    // MARK: - Command Tasks

    /// In-flight command pipelines. Each task awaits its command but does not
    /// block the serial EventSub receive loop, and is owned by one connection
    /// generation so reconnect/leave can cancel it deterministically.
    var commandTasks: [UUID: Task<Void, Never>] = [:]

    var activeCommandTaskCount: Int { commandTasks.count }

    // MARK: - Redemption Pipeline Tasks

    struct VolatileBitsFallbackKey: Hashable {
        let messageID: String
        let broadcasterID: String
    }

    struct VolatileBitsFallback {
        let item: TwitchRedemptionResolutionOutbox.BitsItem
        let claimedAt: Date
        var completed: Bool
    }

    /// Process-owned fallback used only when the atomic outbox write fails.
    /// Completed entries remain non-evicting for the full EventSub freshness
    /// horizon; incomplete entries remain until they can run or the process exits.
    var volatileBitsFallbacks:
        [VolatileBitsFallbackKey: VolatileBitsFallback] = [:]

    /// In-flight channel-point pipelines, keyed by their durable intake item so
    /// duplicate EventSub delivery cannot process the same payment twice.
    /// Like bits work, these pipelines survive socket reconnects: only their
    /// chat reply is generation-bound. Deinit still cancels them.
    var redemptionTasks: [UUID: Task<Void, Never>] = [:]
    /// Bits represent an irreversible viewer payment. Their request pipeline
    /// therefore outlives EventSub socket generations; only the eventual chat
    /// reply is gated to the originating session.
    var paidRedemptionTasks: [UUID: Task<Void, Never>] = [:]
    var activePaidRedemptionTaskCount: Int { paidRedemptionTasks.count }
    /// Fulfillment/refund HTTP work outlives its originating EventSub session so
    /// reconnect/leave can never strand already-spent viewer points.
    var redemptionResolutionTasks: [UUID: Task<Void, Never>] = [:]
    /// Ownership token preventing a canceled worker's deferred cleanup from
    /// deleting a newer replay task for the same persisted item.
    var redemptionResolutionWorkerIDs: [UUID: UUID] = [:]

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
    @MainActor init(
        eventSubHTTPClient: HTTPClient = .shared,
        helixHTTPClient: HTTPClient = .shared,
        channelPointsService: TwitchChannelPointsService = TwitchChannelPointsService(),
        redemptionResolutionOutbox: TwitchRedemptionResolutionOutbox = .shared,
        redemptionClientIDProvider: @escaping @Sendable () -> String? = {
            TwitchChatService.resolveClientID()
        },
        eventSubWebSocketFactory: (@Sendable (URL) -> URLSessionWebSocketTask)? = nil,
        eventSubWebSocketResume: @escaping @Sendable (URLSessionWebSocketTask) -> Void = {
            $0.resume()
        },
        eventSubWebSocketReceive: @escaping @Sendable (URLSessionWebSocketTask) async throws
            -> URLSessionWebSocketTask.Message = { try await $0.receive() }
    ) {
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
        self.eventSubHTTPClient = eventSubHTTPClient
        self.helixHTTPClient = helixHTTPClient
        self.channelPointsService = channelPointsService
        self.redemptionResolutionOutbox = redemptionResolutionOutbox
        self.redemptionClientIDProvider = redemptionClientIDProvider
        self.eventSubWebSocketFactory = eventSubWebSocketFactory
        self.eventSubWebSocketResume = eventSubWebSocketResume
        self.eventSubWebSocketReceive = eventSubWebSocketReceive
    }

    deinit {
        // Synchronous cleanup only. Actor isolation forbids awaits in deinit.
        sessionWelcomeTask?.cancel()
        reconnectTask?.cancel()
        receiveTask?.cancel()
        migrationSourceReceiveTask?.cancel()
        keepaliveWatchdogTask?.cancel()
        connectionMessageTask?.cancel()
        pendingRetryTask?.cancel()
        commandTasks.values.forEach { $0.cancel() }
        redemptionTasks.values.forEach { $0.cancel() }
        paidRedemptionTasks.values.forEach { $0.cancel() }
        redemptionResolutionTasks.values.forEach { $0.cancel() }
        TwitchRedemptionTeardownGate.removeService(
            serviceID: ObjectIdentifier(self))
        networkPathMonitor?.cancel()
        webSocketTask?.cancel(with: .goingAway, reason: nil)
        migrationSourceWebSocketTask?.cancel(with: .goingAway, reason: nil)
        chatMessagesContinuation.finish()
        connectionStateHub.finish()
        skipPollResultsContinuation.finish()
        // A URLSession that is never invalidated retains its internal state
        // until the process exits. Throwaway instances (resolveBotIdentityStatic)
        // would otherwise leak one session each per OAuth/re-auth.
        urlSession.invalidateAndCancel()
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
        if service != nil {
            replayPendingBitsEvents()
        }
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
        func awaitCapacity(endpoint: String) async throws {
            while let wait = waitTimeIfRateLimited(endpoint: endpoint) {
                try await Task.sleep(for: .seconds(wait))
            }
            try Task.checkCancellation()
        }

        /// Records a hard 429 backoff: marks `endpoint` saturated until
        /// `resetEpoch` (seconds since 1970) so ``awaitCapacity(endpoint:)``
        /// sleeps until the bucket is allowed to refill. Used by the reactive
        /// 429 retry path after parsing `Ratelimit-Reset` / `Retry-After`.
        func noteRateLimited(endpoint: String, untilEpoch resetEpoch: TimeInterval) {
            let now = Date().timeIntervalSince1970
            let delta = resetEpoch - now
            guard delta.isFinite,
                  let wait = TwitchDeviceAuth.boundedServerRetryDelay(max(0, delta)) else {
                return
            }
            var state = states[endpoint] ?? RateLimitState()
            state.remaining = 0
            state.resetTime = now + wait
            states[endpoint] = state
        }

        /// Parses the seconds to wait after a `429 Too Many Requests` response.
        ///
        /// Parses `Retry-After` (delta or HTTP date) and `Ratelimit-Reset`
        /// (epoch seconds), choosing the later bounded signal so a retry never
        /// fires before either server deadline.
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

            let retryAfterSeconds = headerValue("Retry-After").flatMap {
                TwitchDeviceAuth.retryAfterSeconds(
                    $0,
                    now: Date(timeIntervalSince1970: now))
            }
            let resetSeconds: TimeInterval? = headerValue("Ratelimit-Reset").flatMap { reset in
                guard let resetEpoch = TimeInterval(
                    reset.trimmingCharacters(in: .whitespacesAndNewlines)) else {
                    return nil
                }
                let delta = resetEpoch - now
                guard delta.isFinite else { return nil }
                return TwitchDeviceAuth.boundedServerRetryDelay(max(0, delta))
            }
            return [retryAfterSeconds, resetSeconds].compactMap { $0 }.max()
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
                let now = Date().timeIntervalSince1970
                let delta = resetInt - now
                if delta.isFinite,
                   let wait = TwitchDeviceAuth.boundedServerRetryDelay(max(0, delta)) {
                    state.resetTime = now + wait
                }
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
        clientID: String,
        attemptGeneration: UInt64? = nil,
        credentialRevision: UInt64? = nil
    ) async throws {
        guard !broadcasterID.isEmpty, !botID.isEmpty, !token.isEmpty else {
            Log.error("TwitchChatService: Invalid credentials for channel join", category: "Twitch")
            throw ConnectionError.invalidCredentials
        }
        guard !clientID.isEmpty else {
            Log.error("TwitchChatService: Missing client ID for channel join", category: "Twitch")
            throw ConnectionError.missingClientID
        }
        if attemptGeneration == nil {
            // A new explicit connection supersedes a suspended account
            // teardown. The older leave observes the ownership-generation
            // change and preserves credentials instead of clearing this join.
            eventSubTeardownQuiescing.set(false)
            channelOwnershipGeneration &+= 1
            // A direct connection owns recovery now; a delayed backoff must not
            // wake and supersede the socket this call is about to establish.
            reconnectTask?.cancel()
            reconnectTask = nil
        }

        let generation: UInt64
        if let attemptGeneration {
            try ensureConnectionAttempt(attemptGeneration)
            generation = attemptGeneration
        } else {
            generation = beginConnectionAttempt()
        }

        // Defer publishing credentials and starting durable replay until every
        // suspension below has completed and the connection/account revisions
        // are still current. A superseded join must leave no stale actor state.

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

        // `leaveChannel()` or a newer join may have run while MainActor was
        // wiring the dispatcher. Never let this superseded attempt open a socket.
        try ensureConnectionAttempt(generation)
        if let credentialRevision {
            guard TwitchCredentialStore.shared.revision(
                matchingAccessToken: token) == credentialRevision else {
                throw CancellationError()
            }
        }

        self.broadcasterID = broadcasterID
        self.botID = botID
        self.oauthToken = token
        self.clientID = clientID
        self.botUsername = nil
        self.hasSentConnectionMessage = false
        replayPendingRedemptionResolutions()

        // The caller publishes reconnect ownership before starting transport.
        // Connected state still waits for EventSub session_welcome.
    }

    /// Connects to a Twitch channel by name, resolving usernames to IDs.
    func connectToChannel(
        channelName: String,
        token: String,
        clientID: String,
        attemptGeneration: UInt64? = nil,
        expectedCredentialRevision: UInt64? = nil
    ) async throws {
        guard !channelName.isEmpty, !token.isEmpty else {
            Log.error("TwitchChatService: Invalid channel name or token", category: "Twitch")
            throw ConnectionError.invalidCredentials
        }
        guard !clientID.isEmpty else {
            Log.error("TwitchChatService: Missing client ID for channel connect", category: "Twitch")
            throw ConnectionError.missingClientID
        }
        guard let credentialSnapshot = TwitchCredentialStore.shared.connectionSnapshot(
            matchingAccessToken: token
        ), credentialSnapshot.channelID == channelName else {
            throw CancellationError()
        }
        if let expectedCredentialRevision {
            guard credentialSnapshot.revision == expectedCredentialRevision else {
                throw CancellationError()
            }
        }
        let credentialRevision = credentialSnapshot.revision

        if attemptGeneration == nil {
            eventSubTeardownQuiescing.set(false)
            channelOwnershipGeneration &+= 1
            // A direct connection owns recovery now; a delayed backoff must not
            // wake and supersede the socket this call is about to establish.
            reconnectTask?.cancel()
            reconnectTask = nil
        }

        let generation: UInt64
        if let attemptGeneration {
            try ensureConnectionAttempt(attemptGeneration)
            generation = attemptGeneration
        } else {
            generation = beginConnectionAttempt()
        }

        var botUserID = credentialSnapshot.userID

        if botUserID?.isEmpty ?? true {
            let identity = try await fetchBotIdentity(token: token, clientID: clientID)
            try ensureConnectionAttempt(generation)
            botUserID = identity.userID
            let resolvedUsername = identity.displayName.isEmpty
                ? identity.login
                : identity.displayName
            guard try TwitchCredentialStore.shared.commitIdentity(
                username: resolvedUsername,
                userID: identity.userID,
                matchingAccessToken: token,
                expectedRevision: credentialRevision
            ) else {
                throw CancellationError()
            }
        }

        guard let botUserID else { throw ConnectionError.invalidCredentials }

        let broadcasterUserID = try await resolveUsername(
            channelName, token: token, clientID: clientID)
        try ensureConnectionAttempt(generation)
        guard TwitchCredentialStore.shared.revision(
            matchingAccessToken: token) == credentialRevision else {
            throw CancellationError()
        }

        guard !broadcasterUserID.isEmpty else {
            throw ConnectionError.networkError("Could not resolve channel name to user ID")
        }

        try await joinChannel(
            broadcasterID: broadcasterUserID,
            botID: botUserID,
            token: token,
            clientID: clientID,
            attemptGeneration: generation,
            credentialRevision: credentialRevision)

        try ensureConnectionAttempt(generation)
        guard TwitchCredentialStore.shared.revision(
            matchingAccessToken: token) == credentialRevision else {
            disconnectFromEventSub()
            throw CancellationError()
        }

        // Store credentials for automatic reconnection
        reconnectChannelName = channelName
        reconnectToken = token
        reconnectClientID = clientID

        if networkPathMonitor == nil {
            startNetworkMonitoring()
        }

        // Reconnect ownership must exist before a fast session_welcome can run
        // subscription setup and tear down this socket on a critical failure.
        connectToEventSub()

        Log.info("TwitchChatService: Connected to channel \(channelName)", category: "Twitch")
    }

    /// Starts a new logical connection attempt and supersedes any older one.
    @discardableResult
    func beginConnectionAttempt() -> UInt64 {
        // A new logical attempt owns the transport, not just the receive
        // generation. Retire an existing socket immediately so a validation or
        // account-supersede failure cannot leave a ghost connection whose
        // frames are forever rejected by the new generation.
        if webSocketTask != nil || migrationSourceWebSocketTask != nil {
            disconnectFromEventSub()
        } else {
            invalidateSessionBoundChatWork()
        }
        isProcessingDisconnect = false
        return connectionGeneration
    }

    /// Invalidates chat work owned by the current EventSub session.
    ///
    /// Called both when starting a new attempt and as soon as any socket is
    /// disconnected/migrated. That closes the backoff window where an old
    /// command could otherwise finish before the replacement attempt begins.
    func invalidateSessionBoundChatWork() {
        connectionGeneration &+= 1
        connectionMessageTask?.cancel()
        connectionMessageTask = nil
        commandTasks.values.forEach { $0.cancel() }
        commandTasks.removeAll()
        // Channel-point redemptions represent spent viewer points. Their
        // durable-intake owner must finish across socket generations; dropping
        // it here would let replay refund while the old pipeline still mutates
        // the queue. Session-bound chat sends reject the stale generation.
        pendingRetryTask?.cancel()
        pendingRetryTask = nil
        pendingRetryGeneration &+= 1
        pendingMessages.removeAll(keepingCapacity: false)
    }

    /// Actor-isolated intent check used at every suspension boundary and by tests.
    func connectionAttemptIsCurrent(_ generation: UInt64) -> Bool {
        generation == connectionGeneration && !isProcessingDisconnect
    }

    /// True only while an async command still belongs to the active channel session.
    func commandReplyIsCurrent(generation: UInt64, broadcasterID: String) -> Bool {
        connectionAttemptIsCurrent(generation) && self.broadcasterID == broadcasterID
    }

    private func ensureConnectionAttempt(_ generation: UInt64) throws {
        guard connectionAttemptIsCurrent(generation), !Task.isCancelled else {
            throw CancellationError()
        }
    }

    // Bot identity + token/username resolution lives in TwitchChatService+Auth.swift

    /// Leaves the current channel and disconnects from EventSub. The managed
    /// reward is held while this actor still owns the only credentials that can
    /// mutate it, before account teardown is allowed to clear those credentials.
    @discardableResult
    func leaveChannel(
        allowDiscardingOpaqueRedemptionRecovery: Bool = false
    ) async -> Bool {
        Log.info("TwitchChatService:leaveChannel() called", category: "Twitch")
        eventSubCredentialTeardownFenceDepth += 1
        eventSubTeardownQuiescing.set(true)
        defer {
            eventSubCredentialTeardownFenceDepth -= 1
            if eventSubCredentialTeardownFenceDepth == 0 {
                eventSubTeardownQuiescing.set(false)
            }
        }
        let teardownOwnershipGeneration = channelOwnershipGeneration
        let teardownConnectionGeneration = connectionGeneration
        let teardownRewardSnapshot = TwitchManagedRewardStore.snapshot()
        let storedRewardBroadcasterID: String?
        switch teardownRewardSnapshot {
        case let .owned(identity):
            storedRewardBroadcasterID = identity.broadcasterID
        case .none, .legacy, .corrupt:
            storedRewardBroadcasterID = nil
        }

        let teardownBroadcasterID = broadcasterID
        let teardownBotID = botID
        let teardownClientID = clientID
        let teardownManagedBroadcasterID = teardownBroadcasterID
            ?? storedRewardBroadcasterID
            ?? TwitchCredentialStore.shared.accessSnapshot()?.userID
        guard await pauseManagedRewardBeforeCredentialTeardown(
            allowDiscardingOpaqueRedemptionRecovery:
                allowDiscardingOpaqueRedemptionRecovery
        ) else {
            Log.error(
                "TwitchChatService: Refusing credential teardown while the managed reward may still accept redemptions",
                category: "Twitch")
            return false
        }

        // `leaveChannel` now suspends for bounded setup/drain/pause work.
        // Reject a newer actor session or a reward owned by another broadcaster;
        // legacy/corrupt identities are never sufficient teardown authority.
        let rewardOwnershipIsCurrent: Bool
        switch TwitchManagedRewardStore.snapshot() {
        case .none:
            rewardOwnershipIsCurrent = true
        case let .owned(identity):
            rewardOwnershipIsCurrent =
                identity.broadcasterID == teardownManagedBroadcasterID
        case .legacy, .corrupt:
            rewardOwnershipIsCurrent = false
        }
        guard channelOwnershipGeneration == teardownOwnershipGeneration,
              connectionGeneration == teardownConnectionGeneration,
              rewardOwnershipIsCurrent,
              broadcasterID == teardownBroadcasterID,
              botID == teardownBotID,
              clientID == teardownClientID else {
            if let teardownManagedBroadcasterID {
                TwitchRedemptionTeardownGate.cancelTeardown(
                    serviceID: ObjectIdentifier(self),
                    broadcasterID: teardownManagedBroadcasterID,
                    generation: teardownOwnershipGeneration)
            }
            Log.info(
                "TwitchChatService: Account changed during reward pause; skipping stale teardown",
                category: "Twitch")
            // A newer session owns any subsequent reconciliation.
            await refreshRedemptionSubscriptions()
            return false
        }

        // Close the socket without cancelling a receive task that may already
        // be queued on this actor with a paid frame. Only after that intake
        // boundary is quiescent can the final durable drain be authoritative.
        guard await quiesceEventSubReceiveBeforeCredentialTeardown(
            expectedOwnershipGeneration: teardownOwnershipGeneration,
            expectedConnectionGeneration: teardownConnectionGeneration
        ) else {
            if let teardownManagedBroadcasterID {
                TwitchRedemptionTeardownGate.cancelTeardown(
                    serviceID: ObjectIdentifier(self),
                    broadcasterID: teardownManagedBroadcasterID,
                    generation: teardownOwnershipGeneration)
            }
            return false
        }
        if let teardownManagedBroadcasterID {
            guard await settleRedemptionWorkBeforeCredentialTeardown(
                broadcasterID: teardownManagedBroadcasterID
            ) else {
                TwitchRedemptionTeardownGate.cancelTeardown(
                    serviceID: ObjectIdentifier(self),
                    broadcasterID: teardownManagedBroadcasterID,
                    generation: teardownOwnershipGeneration)
                Log.error(
                    "TwitchChatService: Refusing credential teardown because paid work arrived at the final EventSub intake boundary",
                    category: "Twitch")
                return false
            }
        }

        guard eventSubTeardownQuiescing.value,
              channelOwnershipGeneration == teardownOwnershipGeneration,
              connectionGeneration == teardownConnectionGeneration,
              broadcasterID == teardownBroadcasterID,
              botID == teardownBotID,
              clientID == teardownClientID else {
            if let teardownManagedBroadcasterID {
                TwitchRedemptionTeardownGate.cancelTeardown(
                    serviceID: ObjectIdentifier(self),
                    broadcasterID: teardownManagedBroadcasterID,
                    generation: teardownOwnershipGeneration)
            }
            return false
        }

        isProcessingDisconnect = true
        disconnectFromEventSub(allowDuringCredentialTeardown: true)
        if let teardownManagedBroadcasterID {
            // Setup cannot restart for the old receive context after disconnect,
            // so the process-local fence can now be released without an unpause race.
            TwitchRedemptionTeardownGate.cancelTeardown(
                serviceID: ObjectIdentifier(self),
                broadcasterID: teardownManagedBroadcasterID,
                generation: teardownOwnershipGeneration)
        }

        // Clear reconnection credentials
        reconnectChannelName = nil
        reconnectToken = nil
        reconnectClientID = nil
        reconnectionAttempts = 0
        networkReconnectCycles = 0
        reconnectTask?.cancel()
        reconnectTask = nil

        // Network monitoring is needed only while a Twitch channel is active.
        // Recreate it on the next join rather than keeping a process-lifetime
        // path monitor after the integration is disabled.
        networkPathMonitor?.pathUpdateHandler = nil
        networkPathMonitor?.cancel()
        networkPathMonitor = nil
        networkMonitorGeneration &+= 1
        isNetworkReachable = true

        broadcasterID = nil
        botID = nil
        oauthToken = nil
        clientID = nil
        hasSentConnectionMessage = false

        Log.info("TwitchChatService: Left channel", category: "Twitch")
        return true
    }

    // Token validation lives in TwitchChatService+Auth.swift

    /// Sends the connection confirmation message to the channel.
    ///
    /// Called automatically when the bot successfully subscribes to channel chat messages.
    func sendConnectionMessage() {
        connectionMessageTask?.cancel()
        guard let broadcasterID else { return }
        let generation = connectionGeneration
        connectionMessageTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(AppConstants.Twitch.connectionMessageDelay))
            if Task.isCancelled { return }
            await self?.sendConnectionMessageIfNeeded(
                generation: generation,
                broadcasterID: broadcasterID
            )
        }
    }

    func sendConnectionMessageIfNeeded(
        generation: UInt64,
        broadcasterID: String
    ) async {
        guard !Task.isCancelled,
              commandReplyIsCurrent(
                generation: generation,
                broadcasterID: broadcasterID
              ),
              !hasSentConnectionMessage else { return }
        hasSentConnectionMessage = true
        await sendSessionBoundMessage(
            AppConstants.Twitch.connectionMessage,
            replyTo: nil,
            generation: generation,
            broadcasterID: broadcasterID)
    }

    // MARK: - Message Sending

    /// Sends a message to the current channel.
    func sendMessage(_ message: String) async {
        await sendMessage(message, replyTo: nil)
    }

    /// Sends a message that replies to another message.
    ///
    /// This is the public entry point used by command handlers. It delegates to
    /// `sendMessageOnce(_:replyTo:)` and queues only explicitly transient
    /// failures. Permanent/indeterminate failures stay dropped so a successful
    /// request with a malformed response can never produce duplicate chat text.
    func sendMessage(_ message: String, replyTo parentMessageID: String?) async {
        guard let broadcasterID else { return }
        await sendSessionBoundMessage(
            message,
            replyTo: parentMessageID,
            generation: connectionGeneration,
            broadcasterID: broadcasterID)
    }

    /// Sends a command response only to the session that received its command.
    ///
    /// The identity checks bracket the network suspension. If a disconnect or
    /// reconnect happens while command work or the send is in flight, the
    /// response cannot be queued for the replacement channel. Starting any new
    /// connection also clears the shared retry queue.
    func sendCommandReply(
        _ message: String,
        replyTo parentMessageID: String,
        generation: UInt64,
        broadcasterID: String
    ) async {
        await sendSessionBoundMessage(
            message,
            replyTo: parentMessageID,
            generation: generation,
            broadcasterID: broadcasterID)
    }

    /// Sends and optionally queues a message only while one exact channel
    /// generation owns it. Used for both command replies and the delayed
    /// connection greeting so neither can leak into a replacement channel.
    func sendSessionBoundMessage(
        _ message: String,
        replyTo parentMessageID: String?,
        generation: UInt64,
        broadcasterID: String
    ) async {
        guard !Task.isCancelled,
              commandReplyIsCurrent(generation: generation, broadcasterID: broadcasterID) else {
            return
        }

        let outcome = await sendMessageOnce(message, replyTo: parentMessageID)
        guard !Task.isCancelled,
              commandReplyIsCurrent(generation: generation, broadcasterID: broadcasterID) else {
            return
        }

        if Self.shouldRetryChatSend(outcome) {
            queueMessageForRetry(message: message, parentMessageID: parentMessageID, attempts: 0)
        }
    }

    /// Performs one send attempt without touching the retry queue. The outcome
    /// explicitly distinguishes transient failures from permanent rejections.
    /// Empty/whitespace-only text is a successful no-op.
    func sendMessageOnce(
        _ message: String,
        replyTo parentMessageID: String?
    ) async -> ChatSendOutcome {
        await sendMessageOnce(
            message,
            replyTo: parentMessageID,
            allowsRefreshRetry: true
        )
    }

    /// Internal bounded 401 retry. Twitch rejected the original request before
    /// delivery, so retrying it once with a newly-issued token is duplicate-safe.
    private func sendMessageOnce(
        _ message: String,
        replyTo parentMessageID: String?,
        allowsRefreshRetry: Bool
    ) async -> ChatSendOutcome {
        guard let broadcasterID,
              let botID,
              let token = oauthToken,
              let clientID else {
            Log.warn("TwitchChatService: Not connected, send attempt failed", category: "Twitch")
            return .retryableFailure
        }

        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .sent }
        let generation = connectionGeneration
        let expectedCredential = TwitchCredentialStore.shared
            .connectionSnapshot(
                matchingAccessToken: token
            )?.accessExpectation

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
                    Log.warn(
                        "TwitchChatService: Send response contained no result; "
                            + "not retrying an indeterminate delivery",
                        category: "Twitch")
                    return .permanentFailure
                }
                guard first.isSent else {
                    Log.warn(
                        "TwitchChatService: Message dropped by Twitch; "
                            + "not retrying a permanent rejection",
                        category: "Twitch")
                    return .permanentFailure
                }
            } catch {
                Log.warn(
                    "TwitchChatService: Failed to decode send-message response; "
                        + "delivery is indeterminate and will not be retried - "
                        + error.localizedDescription,
                    category: "Twitch")
                return .permanentFailure
            }
            return .sent
        } catch ConnectionError.authenticationFailed {
            Log.error(
                "TwitchChatService: Send rejected (401); attempting token refresh",
                category: "Twitch")
            guard let expectedCredential else {
                return .permanentFailure
            }
            guard allowsRefreshRetry else {
                guard rejectedCredentialIsCurrent(
                    expectedCredential,
                    clientID: clientID,
                    generation: generation,
                    broadcasterID: broadcasterID
                ) else { return .permanentFailure }
                Log.error(
                    "TwitchChatService: Refreshed token was rejected by chat send",
                    category: "Twitch")
                signalReauthNeededAndStop()
                return .permanentFailure
            }
            guard let recovery = await recoverRejectedAccessToken(
                expectedCredential,
                clientID: clientID,
                generation: generation,
                broadcasterID: broadcasterID
            ) else { return .permanentFailure }

            switch recovery {
            case .refreshed:
                return await sendMessageOnce(
                    message,
                    replyTo: parentMessageID,
                    allowsRefreshRetry: false
                )
            case .invalid:
                signalReauthNeededAndStop()
                return .permanentFailure
            case .temporarilyUnavailable:
                disconnectFromEventSub()
                if isNetworkReachable { scheduleReconnect() }
                return .retryableFailure
            case .superseded:
                return .permanentFailure
            }
        } catch HelixRequestError.permanentHTTP(let statusCode) {
            Log.error(
                "TwitchChatService: Chat send permanently rejected with HTTP \(statusCode)",
                category: "Twitch")
            return .permanentFailure
        } catch HelixRequestError.retryableHTTP(let statusCode) {
            Log.warn(
                "TwitchChatService: Chat send transiently failed with HTTP \(statusCode)",
                category: "Twitch")
            return .retryableFailure
        } catch {
            Log.error(
                "TwitchChatService: Failed to send message - \(error.localizedDescription)",
                category: "Twitch")
            return .retryableFailure
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
        pendingRetryGeneration &+= 1
        let generation = pendingRetryGeneration
        pendingRetryTask = Task { [weak self] in
            await self?.drainPendingMessages(generation: generation)
        }
    }

    /// Single long-lived drain loop. Walks the pending queue, sleeping per
    /// message according to that message's exponential backoff, until the queue
    /// drains. Exits (clearing `pendingRetryTask`) when empty so a future
    /// enqueue restarts it. Per-message attempt limits are preserved: the loop
    /// sends via `sendMessageOnce` (which never touches the queue) and, on
    /// failure, passes the current attempt count back through the queue helper
    /// (which stores the next count), dropping at `maxMessageRetries`. It must NOT call
    /// `sendMessage`, whose failure path requeues at `attempts: 0` and would
    /// reset the count, allowing unbounded retries.
    private func drainPendingMessages(generation: UInt64) async {
        defer {
            if pendingRetryGeneration == generation {
                pendingRetryTask = nil
            }
        }

        while !Task.isCancelled,
              pendingRetryGeneration == generation,
              !pendingMessages.isEmpty {
            let pending = pendingMessages.removeFirst()

            // Backoff is keyed off the prior attempt count. `attempts` here is
            // the next attempt number (1-based), so the delay matches the old
            // `pow(2, attempts)` schedule (attempt 1 -> 2^0 = 1s).
            let delay = pow(2.0, Double(pending.attempts - 1))
            do {
                try await Task.sleep(
                    for: .seconds(delay),
                    tolerance: .seconds(delay * 0.1))
            } catch {
                return
            }
            guard !Task.isCancelled,
                  pendingRetryGeneration == generation,
                  !isProcessingDisconnect else { return }

            // Send without auto-queueing. On failure (missing credentials or a
            // failed request) requeue with the attempt count incremented, so a
            // persistently failing message stops at `maxMessageRetries` instead
            // of looping forever.
            let outcome = await sendMessageOnce(pending.message, replyTo: pending.parentMessageID)
            guard !Task.isCancelled,
                  pendingRetryGeneration == generation,
                  !isProcessingDisconnect else { return }
            if Self.shouldRetryChatSend(outcome) {
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
            try await rateLimiter.awaitCapacity(endpoint: endpoint)
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

        try Task.checkCancellation()
        var (data, http) = try await helixHTTPClient.send(request)

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
                try await rateLimiter.awaitCapacity(endpoint: endpoint)
            } else {
                Log.info(
                    "TwitchChatService: API \(endpoint) hit 429 without a reset header; one immediate retry",
                    category: "Twitch")
            }

            try Task.checkCancellation()
            (data, http) = try await helixHTTPClient.send(request)
            await rateLimiter.updateRateLimitState(
                endpoint: endpoint, from: http.allHeaderFields)
        }

        let disposition = Self.helixResponseDisposition(for: http.statusCode)
        guard disposition == .success else {
            let responseText = String(data: data, encoding: .utf8) ?? "No response body"
            Log.warn(
                "TwitchChatService: API \(endpoint) returned HTTP \(http.statusCode) - \(responseText)",
                category: "Twitch")

            switch disposition {
            case .success:
                return data
            case .authenticationFailure:
                throw ConnectionError.authenticationFailed
            case .retryableFailure:
                throw HelixRequestError.retryableHTTP(statusCode: http.statusCode)
            case .permanentFailure:
                throw HelixRequestError.permanentHTTP(statusCode: http.statusCode)
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
