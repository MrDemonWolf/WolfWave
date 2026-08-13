//
//  TwitchChannelPointsService.swift
//  WolfWave
//
//  Created by Nathanial Henniges on 2026-05-22.
//  Copyright © 2026 MrDemonWolf, Inc. All rights reserved.
//

import Foundation

/// Canonical process-atomic identity for WolfWave managed channel-point rewards.
///
/// The legacy string key remains a UI mirror and migration source only. Every
/// Helix mutation consults this owner-bound record, so changing Twitch accounts
/// cannot make one broadcaster mutate or discard another broadcaster reward.
nonisolated enum TwitchManagedRewardStore {
    struct Identity: Codable, Equatable, Sendable {
        let rewardID: String
        let broadcasterID: String

        var isValid: Bool { !rewardID.isEmpty && !broadcasterID.isEmpty }
    }

    enum Snapshot: Equatable, Sendable {
        case none
        case legacy(rewardID: String)
        case owned(Identity)
        case corrupt
    }

    private static let lock = NSLock()
    private static var defaults: UserDefaults { DefaultsStore.store }

    static func snapshot() -> Snapshot {
        lock.withLock { snapshotUnlocked(repairingLegacyMirror: true) }
    }

    static func matches(_ identity: Identity) -> Bool {
        lock.withLock {
            snapshotUnlocked(repairingLegacyMirror: true) == .owned(identity)
        }
    }

    /// Compare-and-swap persistence. A newly-created or migrated reward cannot
    /// overwrite an identity installed by a concurrent account/session.
    @discardableResult
    static func store(_ identity: Identity, replacing expected: Snapshot) -> Bool {
        guard identity.isValid,
              let encoded = try? JSONCoders.defaultEncoder.encode(identity) else {
            return false
        }
        return lock.withLock {
            guard snapshotUnlocked(repairingLegacyMirror: false) == expected else {
                return false
            }
            defaults.set(
                encoded,
                forKey: AppConstants.UserDefaults.songRequestChannelPointsRewardIdentity)
            defaults.set(
                identity.rewardID,
                forKey: AppConstants.UserDefaults.songRequestChannelPointsRewardID)
            return true
        }
    }

    /// Removes only the exact owner-bound record the caller previously proved.
    /// A replacement account or reward installed meanwhile is left untouched.
    @discardableResult
    static func remove(matching identity: Identity) -> Bool {
        lock.withLock {
            guard snapshotUnlocked(repairingLegacyMirror: false) == .owned(identity) else {
                return false
            }
            if defaults.string(
                forKey: AppConstants.UserDefaults.songRequestChannelPointsRewardID
            ) == identity.rewardID {
                defaults.removeObject(
                    forKey: AppConstants.UserDefaults.songRequestChannelPointsRewardID)
            }
            // The authoritative owner record is removed last. A process exit
            // between these writes leaves an owned snapshot that repairs its
            // mirror, never an ownerless legacy ID.
            defaults.removeObject(
                forKey: AppConstants.UserDefaults.songRequestChannelPointsRewardIdentity)
            return true
        }
    }

    private static func snapshotUnlocked(
        repairingLegacyMirror: Bool
    ) -> Snapshot {
        let identityKey = AppConstants.UserDefaults.songRequestChannelPointsRewardIdentity
        if let storedObject = defaults.object(forKey: identityKey) {
            guard let data = storedObject as? Data,
                  let identity = try? JSONCoders.default.decode(
                    Identity.self,
                    from: data),
                  identity.isValid else {
                return .corrupt
            }
            if repairingLegacyMirror,
               defaults.string(
                forKey: AppConstants.UserDefaults.songRequestChannelPointsRewardID
               ) != identity.rewardID {
                defaults.set(
                    identity.rewardID,
                    forKey: AppConstants.UserDefaults.songRequestChannelPointsRewardID)
            }
            return .owned(identity)
        }

        let legacyRewardID = (defaults.string(
            forKey: AppConstants.UserDefaults.songRequestChannelPointsRewardID) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return legacyRewardID.isEmpty ? .none : .legacy(rewardID: legacyRewardID)
    }
}

/// Manages the WolfWave-owned custom channel-point reward via the Twitch Helix
/// API: creating the "Request a Song" reward, keeping its cost in sync, and
/// resolving redemptions (fulfilling on success, cancelling to refund points on
/// failure).
///
/// Only rewards created by WolfWave's own client ID can be managed here. That
/// is why WolfWave owns the reward rather than listening to one the streamer
/// created manually. All methods take credentials explicitly so the type holds
/// no mutable state and is trivially `Sendable`.
nonisolated struct TwitchChannelPointsService: Sendable {

    // MARK: - Types

    /// Twitch credentials needed for Helix channel-point calls. The token must
    /// belong to the broadcaster and carry the `channel:manage:redemptions` scope.
    struct Credentials: Sendable {
        let broadcasterID: String
        let token: String
        let clientID: String

        var helix: HelixClient.Credentials {
            HelixClient.Credentials(token: token, clientID: clientID)
        }
    }

    /// How a channel-point redemption should be resolved.
    enum Resolution: String, Sendable, Equatable {
        /// The request succeeded. Points are spent.
        case fulfilled = "FULFILLED"
        /// The request failed. Points are refunded to the viewer.
        case canceled = "CANCELED"
    }

    /// Typed resolution failure retained by the durable outbox worker. Unlike
    /// the legacy reward error, this preserves status and Retry-After metadata
    /// so only transient outcomes are retried and Twitch controls 429 pacing.
    enum RedemptionResolutionError: Error, Sendable {
        case http(status: Int, body: String, retryAfter: Duration?)
        case transport(String)
        case malformedResponse
        case ownershipUnverified
    }

    /// Errors produced by Helix channel-point calls.
    ///
    /// Kept as a thin wrapper around `HelixClient.HelixError` so existing
    /// callers continue to switch on the same cases while sharing the
    /// underlying HTTP/transport plumbing.
    enum RewardError: Error, LocalizedError {
        case http(status: Int, body: String)
        case transport(underlying: Error)
        case malformedResponse
        case ownershipUnverified

        var errorDescription: String? {
            switch self {
            case let .http(status, body):
                return "Twitch API error \(status): \(body.prefix(160))"
            case let .transport(error):
                return "Network error: \(error.localizedDescription)"
            case .malformedResponse:
                return "Unexpected response from Twitch."
            case .ownershipUnverified:
                return "Managed reward ownership could not be verified for this Twitch account."
            }
        }

        /// Maps a `HelixError` into the legacy `RewardError` cases used by
        /// existing call sites and tests.
        static func from(_ error: HelixClient.HelixError) -> RewardError {
            switch error {
            case let .http(status, body):
                return .http(status: status, body: body)
            case let .unauthorized(body):
                return .http(status: 401, body: body)
            case let .rateLimited(body):
                return .http(status: 429, body: body)
            case .malformedResponse, .decodingFailed, .encodingFailed:
                return .malformedResponse
            case let .transport(message):
                return .transport(
                    underlying: NSError(
                        domain: "HelixTransport", code: -1,
                        userInfo: [NSLocalizedDescriptionKey: message]))
            }
        }
    }

    // MARK: - Properties

    private let baseURL = AppConstants.Twitch.apiBaseURL
    private let helix: HelixClient

    // MARK: - Init

    /// Backwards-compatible initializer that lets tests inject a custom
    /// `URLSession` (e.g. one backed by `MockURLProtocol`).
    init(session: URLSession = .shared) {
        self.helix = HelixClient(http: HTTPClient(session: session))
    }

    /// Test seam. Inject a fully-configured `HelixClient`.
    init(helix: HelixClient) {
        self.helix = helix
    }

    // MARK: - Reward Lifecycle

    /// Ensures the WolfWave "Request a Song" reward exists, creating it when
    /// necessary, and returns its reward ID.
    ///
    /// An owner-bound reward is recreated only after its stored broadcaster
    /// matches these credentials. A legacy ownerless ID is adopted only after
    /// Twitch proves that this broadcaster can manage it; otherwise it remains
    /// untouched and setup fails closed.
    ///
    /// - Parameters:
    ///   - credentials: Broadcaster credentials.
    ///   - cost: Channel-point cost for a newly created reward.
    /// - Returns: The reward ID.
    func ensureReward(credentials: Credentials, cost: Int) async throws -> String {
        let snapshot = TwitchManagedRewardStore.snapshot()
        switch snapshot {
        case let .owned(identity):
            guard identity.broadcasterID == credentials.broadcasterID else {
                throw RewardError.ownershipUnverified
            }
            if try await rewardExists(
                credentials: credentials,
                rewardID: identity.rewardID) {
                guard TwitchManagedRewardStore.matches(identity) else {
                    throw RewardError.ownershipUnverified
                }
                return identity.rewardID
            }
            return try await createAndStoreReward(
                credentials: credentials,
                cost: cost,
                replacing: snapshot)
        case .legacy:
            guard let identity = try await managedRewardIdentity(
                credentials: credentials) else {
                throw RewardError.ownershipUnverified
            }
            return identity.rewardID
        case .none:
            return try await createAndStoreReward(
                credentials: credentials,
                cost: cost,
                replacing: snapshot)
        case .corrupt:
            throw RewardError.ownershipUnverified
        }
    }

    /// Returns the owner-bound reward for these credentials. A legacy ID is
    /// migrated only after Helix proves this broadcaster can manage it.
    func managedRewardIdentity(
        credentials: Credentials
    ) async throws -> TwitchManagedRewardStore.Identity? {
        let snapshot = TwitchManagedRewardStore.snapshot()
        switch snapshot {
        case .none:
            return nil
        case .corrupt:
            throw RewardError.ownershipUnverified
        case let .owned(identity):
            guard identity.broadcasterID == credentials.broadcasterID else {
                throw RewardError.ownershipUnverified
            }
            return identity
        case let .legacy(rewardID):
            guard try await rewardExists(
                credentials: credentials,
                rewardID: rewardID) else {
                throw RewardError.ownershipUnverified
            }
            let identity = TwitchManagedRewardStore.Identity(
                rewardID: rewardID,
                broadcasterID: credentials.broadcasterID)
            guard TwitchManagedRewardStore.store(
                identity,
                replacing: snapshot
            ) || TwitchManagedRewardStore.matches(identity) else {
                throw RewardError.ownershipUnverified
            }
            return identity
        }
    }

    /// Pauses or unpauses the managed reward via Helix (`is_paused`).
    ///
    /// A paused reward stays on the channel but can't be redeemed, so this is how
    /// WolfWave stops channel-point song requests at the source when the feature
    /// is turned off, without deleting and recreating the reward (which would
    /// reset its ID and any viewer-facing customization).
    func setRewardPaused(
        credentials: Credentials,
        rewardID: String,
        paused: Bool,
        requestTimeout: TimeInterval? = nil
    ) async throws {
        _ = try await requireManagedRewardIdentity(
            credentials: credentials, rewardID: rewardID)
        guard let url = customRewardsURL(
            broadcasterID: credentials.broadcasterID, id: rewardID
        ) else { throw RewardError.malformedResponse }

        do {
            var body: [String: Any] = ["is_paused": paused]
            if !paused {
                // Newly-created rewards start disabled until reconciliation.
                body["is_enabled"] = true
            }
            _ = try await helix.sendJSON(
                url: url, method: "PATCH",
                credentials: credentials.helix,
                body: body,
                requestTimeout: requestTimeout)
        } catch let error as HelixClient.HelixError {
            throw RewardError.from(error)
        }
    }

    /// Updates the cost of the managed reward.
    func updateRewardCost(credentials: Credentials, rewardID: String, cost: Int) async throws {
        _ = try await requireManagedRewardIdentity(
            credentials: credentials, rewardID: rewardID)
        guard let url = customRewardsURL(
            broadcasterID: credentials.broadcasterID, id: rewardID
        ) else { throw RewardError.malformedResponse }

        do {
            _ = try await helix.sendJSON(
                url: url, method: "PATCH",
                credentials: credentials.helix,
                body: ["cost": cost])
        } catch let error as HelixClient.HelixError {
            throw RewardError.from(error)
        }
    }

    /// Returns every currently-unfulfilled redemption for the managed reward.
    /// Twitch caps this endpoint at 50 items per page and returns an opaque
    /// cursor in `pagination.cursor`; IDs are de-duplicated across pages.
    func unfulfilledRedemptionIDs(
        credentials: Credentials,
        rewardID: String,
        requestTimeout: TimeInterval? = nil
    ) async throws -> [String] {
        _ = try await requireManagedRewardIdentity(
            credentials: credentials, rewardID: rewardID)
        let deadline = requestTimeout.map { Date().addingTimeInterval($0) }
        var after: String?
        var seenCursors = Set<String>()
        var seenRedemptionIDs = Set<String>()
        var redemptionIDs: [String] = []

        repeat {
            var components = URLComponents(
                string: baseURL + "/channel_points/custom_rewards/redemptions")
            var queryItems = [
                URLQueryItem(name: "broadcaster_id", value: credentials.broadcasterID),
                URLQueryItem(name: "reward_id", value: rewardID),
                URLQueryItem(name: "status", value: "UNFULFILLED"),
                URLQueryItem(name: "sort", value: "OLDEST"),
                URLQueryItem(name: "first", value: "50"),
            ]
            if let after {
                queryItems.append(URLQueryItem(name: "after", value: after))
            }
            components?.queryItems = queryItems
            guard let url = components?.url else {
                throw RewardError.malformedResponse
            }

            let json: [String: Any]?
            do {
                let remainingTimeout: TimeInterval?
                if let deadline {
                    let remaining = deadline.timeIntervalSinceNow
                    guard remaining > 0 else {
                        throw RewardError.transport(
                            underlying: URLError(.timedOut))
                    }
                    remainingTimeout = remaining
                } else {
                    remainingTimeout = nil
                }
                json = try await helix.sendJSON(
                    url: url,
                    method: "GET",
                    credentials: credentials.helix,
                    requestTimeout: remainingTimeout)
            } catch let error as RewardError {
                throw error
            } catch let error as HelixClient.HelixError {
                throw RewardError.from(error)
            }
            guard let data = json?["data"] as? [[String: Any]],
                  let pagination = json?["pagination"] as? [String: Any] else {
                throw RewardError.malformedResponse
            }

            for redemption in data {
                guard let id = redemption["id"] as? String, !id.isEmpty else {
                    throw RewardError.malformedResponse
                }
                if let returnedBroadcasterID = redemption["broadcaster_id"] as? String,
                   returnedBroadcasterID != credentials.broadcasterID {
                    throw RewardError.malformedResponse
                }
                if let reward = redemption["reward"] as? [String: Any],
                   let returnedRewardID = reward["id"] as? String,
                   returnedRewardID != rewardID {
                    throw RewardError.malformedResponse
                }
                if seenRedemptionIDs.insert(id).inserted {
                    redemptionIDs.append(id)
                }
            }

            if let rawCursor = pagination["cursor"] {
                guard let cursor = rawCursor as? String, !cursor.isEmpty else {
                    throw RewardError.malformedResponse
                }
                guard seenCursors.insert(cursor).inserted else {
                    throw RewardError.malformedResponse
                }
                after = cursor
            } else {
                after = nil
            }
        } while after != nil

        return redemptionIDs
    }

    /// Resolves a redemption. `fulfilled` spends the points, `canceled` refunds
    /// them. A failure here is non-fatal (the song may still have queued); the
    /// caller should log and continue.
    func resolveRedemption(
        credentials: Credentials,
        rewardID: String,
        redemptionID: String,
        as resolution: Resolution
    ) async throws {
        do {
            try await resolveRedemptionWithMetadata(
                credentials: credentials,
                rewardID: rewardID,
                redemptionID: redemptionID,
                as: resolution
            )
        } catch let error as RedemptionResolutionError {
            switch error {
            case let .http(status, body, _):
                throw RewardError.http(status: status, body: body)
            case let .transport(message):
                throw RewardError.transport(
                    underlying: NSError(
                        domain: "HelixTransport",
                        code: -1,
                        userInfo: [NSLocalizedDescriptionKey: message]))
            case .malformedResponse:
                throw RewardError.malformedResponse
            case .ownershipUnverified:
                throw RewardError.ownershipUnverified
            }
        }
    }

    /// Resolves a redemption while retaining the response metadata required by
    /// the durable retry worker.
    func resolveRedemptionWithMetadata(
        credentials: Credentials,
        rewardID: String,
        redemptionID: String,
        as resolution: Resolution
    ) async throws {
        try await requireResolutionManagedRewardIdentity(
            credentials: credentials, rewardID: rewardID)
        var components = URLComponents(
            string: baseURL + "/channel_points/custom_rewards/redemptions")
        components?.queryItems = [
            URLQueryItem(name: "broadcaster_id", value: credentials.broadcasterID),
            URLQueryItem(name: "reward_id", value: rewardID),
            URLQueryItem(name: "id", value: redemptionID),
        ]
        guard let url = components?.url else {
            throw RedemptionResolutionError.malformedResponse
        }

        do {
            try Task.checkCancellation()
            let (data, response) = try await helix.sendRawResponse(
                url: url,
                method: "PATCH",
                credentials: credentials.helix,
                body: ["status": resolution.rawValue]
            )
            try Task.checkCancellation()
            guard (200..<300).contains(response.statusCode) else {
                throw RedemptionResolutionError.http(
                    status: response.statusCode,
                    body: String(data: data, encoding: .utf8) ?? "",
                    retryAfter: TwitchDeviceAuth.retryAfterDuration(
                        response.value(forHTTPHeaderField: "Retry-After"))
                )
            }
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as RedemptionResolutionError {
            throw error
        } catch let error as HelixClient.HelixError {
            if Task.isCancelled { throw CancellationError() }
            switch error {
            case let .transport(message):
                throw RedemptionResolutionError.transport(message)
            case .malformedResponse, .encodingFailed, .decodingFailed:
                throw RedemptionResolutionError.malformedResponse
            case let .http(status, body):
                throw RedemptionResolutionError.http(
                    status: status, body: body, retryAfter: nil)
            case let .unauthorized(body):
                throw RedemptionResolutionError.http(
                    status: 401, body: body, retryAfter: nil)
            case let .rateLimited(body):
                throw RedemptionResolutionError.http(
                    status: 429, body: body, retryAfter: nil)
            }
        } catch {
            if Task.isCancelled { throw CancellationError() }
            throw RedemptionResolutionError.transport(error.localizedDescription)
        }
    }

    // MARK: - Private Helpers

    private func createAndStoreReward(
        credentials: Credentials,
        cost: Int,
        replacing expected: TwitchManagedRewardStore.Snapshot
    ) async throws -> String {
        let rewardID = try await createReward(credentials: credentials, cost: cost)
        let identity = TwitchManagedRewardStore.Identity(
            rewardID: rewardID,
            broadcasterID: credentials.broadcasterID)
        guard TwitchManagedRewardStore.store(
            identity,
            replacing: expected
        ) || TwitchManagedRewardStore.matches(identity) else {
            throw RewardError.ownershipUnverified
        }
        return rewardID
    }

    private func requireManagedRewardIdentity(
        credentials: Credentials,
        rewardID: String
    ) async throws -> TwitchManagedRewardStore.Identity {
        guard let identity = try await managedRewardIdentity(
            credentials: credentials),
              identity.rewardID == rewardID,
              TwitchManagedRewardStore.matches(identity) else {
            throw RewardError.ownershipUnverified
        }
        return identity
    }

    private func requireResolutionManagedRewardIdentity(
        credentials: Credentials,
        rewardID: String
    ) async throws {
        do {
            _ = try await requireManagedRewardIdentity(
                credentials: credentials,
                rewardID: rewardID)
        } catch let error as RewardError {
            switch error {
            case let .http(status, body):
                throw RedemptionResolutionError.http(
                    status: status,
                    body: body,
                    retryAfter: nil)
            case let .transport(underlying):
                throw RedemptionResolutionError.transport(
                    underlying.localizedDescription)
            case .malformedResponse:
                throw RedemptionResolutionError.malformedResponse
            case .ownershipUnverified:
                throw RedemptionResolutionError.ownershipUnverified
            }
        }
    }

    /// Builds a Helix `custom_rewards` URL with the common `broadcaster_id`
    /// query plus the optional `id` / `only_manageable_rewards` filters. Returns
    /// `nil` on the (practically impossible) malformed-URL case so each caller
    /// keeps its own distinct failure branch (throw / `false` / `nil`). The
    /// `/redemptions` path is deliberately not routed through this.
    private func customRewardsURL(
        broadcasterID: String,
        id: String? = nil,
        onlyManageable: Bool = false
    ) -> URL? {
        var components = URLComponents(string: baseURL + "/channel_points/custom_rewards")
        var items = [URLQueryItem(name: "broadcaster_id", value: broadcasterID)]
        if let id { items.append(URLQueryItem(name: "id", value: id)) }
        if onlyManageable {
            items.append(URLQueryItem(name: "only_manageable_rewards", value: "true"))
        }
        components?.queryItems = items
        return components?.url
    }

    /// Checks whether a reward ID still exists and is manageable by this client.
    private func rewardExists(credentials: Credentials, rewardID: String) async throws -> Bool {
        guard let url = customRewardsURL(
            broadcasterID: credentials.broadcasterID, id: rewardID, onlyManageable: true
        ) else { return false }

        do {
            let json = try await helix.sendJSON(
                url: url, method: "GET",
                credentials: credentials.helix)
            let data = json?["data"] as? [[String: Any]] ?? []
            return !data.isEmpty
        } catch let HelixClient.HelixError.http(status, _) where status == 404 {
            return false
        } catch let error as HelixClient.HelixError {
            throw RewardError.from(error)
        }
    }

    /// Creates the "Request a Song" reward and returns its ID.
    private func createReward(credentials: Credentials, cost: Int) async throws -> String {
        guard let url = customRewardsURL(
            broadcasterID: credentials.broadcasterID
        ) else { throw RewardError.malformedResponse }

        let body: [String: Any] = [
            "title": AppConstants.Twitch.songRequestRewardTitle,
            "cost": cost,
            "prompt": "Type a song name or paste an Apple Music / Spotify / YouTube link.",
            "is_user_input_required": true,
            "is_enabled": false,
        ]

        let json: [String: Any]?
        do {
            json = try await helix.sendJSON(
                url: url, method: "POST",
                credentials: credentials.helix,
                body: body)
        } catch let HelixClient.HelixError.http(status, errorBody) where status == 400 {
            // A 400 here is almost always a duplicate-title reward left over from
            // a previous install or client-ID change. Adopt the existing managed
            // reward instead of failing and leaving the streamer with none.
            if let existing = try await findManagedRewardByTitle(
                credentials: credentials, title: AppConstants.Twitch.songRequestRewardTitle) {
                return existing
            }
            throw RewardError.http(status: status, body: errorBody)
        } catch let error as HelixClient.HelixError {
            throw RewardError.from(error)
        }
        guard let data = json?["data"] as? [[String: Any]],
            let id = data.first?["id"] as? String, !id.isEmpty
        else {
            throw RewardError.malformedResponse
        }
        return id
    }

    /// Finds an existing WolfWave-manageable reward by title, used to adopt a
    /// duplicate left over from a prior install rather than failing to create.
    private func findManagedRewardByTitle(
        credentials: Credentials, title: String
    ) async throws -> String? {
        guard let url = customRewardsURL(
            broadcasterID: credentials.broadcasterID, onlyManageable: true
        ) else { return nil }

        do {
            let json = try await helix.sendJSON(
                url: url, method: "GET",
                credentials: credentials.helix)
            let data = json?["data"] as? [[String: Any]] ?? []
            return data.first(where: { ($0["title"] as? String) == title })?["id"] as? String
        } catch let error as HelixClient.HelixError {
            throw RewardError.from(error)
        }
    }
}
