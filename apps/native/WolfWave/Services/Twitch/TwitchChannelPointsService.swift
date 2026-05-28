//
//  TwitchChannelPointsService.swift
//  WolfWave
//
//  Created by Nathanial Henniges on 2026-05-22.
//  Copyright © 2026 MrDemonWolf, Inc. All rights reserved.
//

import Foundation

/// Manages the WolfWave-owned custom channel-point reward via the Twitch Helix
/// API: creating the "Request a Song" reward, keeping its cost in sync, and
/// resolving redemptions (fulfilling on success, cancelling to refund points on
/// failure).
///
/// Only rewards created by WolfWave's own client ID can be managed here — that
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
    enum Resolution: String, Sendable {
        /// The request succeeded — points are spent.
        case fulfilled = "FULFILLED"
        /// The request failed — points are refunded to the viewer.
        case canceled = "CANCELED"
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

        var errorDescription: String? {
            switch self {
            case let .http(status, body):
                return "Twitch API error \(status): \(body.prefix(160))"
            case let .transport(error):
                return "Network error: \(error.localizedDescription)"
            case .malformedResponse:
                return "Unexpected response from Twitch."
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

    /// Test seam — inject a fully-configured `HelixClient`.
    init(helix: HelixClient) {
        self.helix = helix
    }

    // MARK: - Reward Lifecycle

    /// Ensures the WolfWave "Request a Song" reward exists, creating it when
    /// necessary, and returns its reward ID.
    ///
    /// If a reward ID is already stored it is verified against Twitch; a missing
    /// or unmanageable reward is recreated. The resolved ID is persisted to
    /// `songRequestChannelPointsRewardID`.
    ///
    /// - Parameters:
    ///   - credentials: Broadcaster credentials.
    ///   - cost: Channel-point cost for a newly created reward.
    /// - Returns: The reward ID.
    func ensureReward(credentials: Credentials, cost: Int) async throws -> String {
        let storedID = Foundation.UserDefaults.standard
            .string(forKey: AppConstants.UserDefaults.songRequestChannelPointsRewardID) ?? ""

        if !storedID.isEmpty, try await rewardExists(credentials: credentials, rewardID: storedID) {
            return storedID
        }

        let newID = try await createReward(credentials: credentials, cost: cost)
        Foundation.UserDefaults.standard.set(
            newID, forKey: AppConstants.UserDefaults.songRequestChannelPointsRewardID)
        return newID
    }

    /// Updates the cost of the managed reward.
    func updateRewardCost(credentials: Credentials, rewardID: String, cost: Int) async throws {
        var components = URLComponents(string: baseURL + "/channel_points/custom_rewards")
        components?.queryItems = [
            URLQueryItem(name: "broadcaster_id", value: credentials.broadcasterID),
            URLQueryItem(name: "id", value: rewardID),
        ]
        guard let url = components?.url else { throw RewardError.malformedResponse }

        do {
            _ = try await helix.sendJSON(
                url: url, method: "PATCH",
                credentials: credentials.helix,
                body: ["cost": cost])
        } catch let error as HelixClient.HelixError {
            throw RewardError.from(error)
        }
    }

    /// Resolves a redemption — `fulfilled` spends the points, `canceled` refunds
    /// them. A failure here is non-fatal (the song may still have queued); the
    /// caller should log and continue.
    func resolveRedemption(
        credentials: Credentials,
        rewardID: String,
        redemptionID: String,
        as resolution: Resolution
    ) async throws {
        var components = URLComponents(
            string: baseURL + "/channel_points/custom_rewards/redemptions")
        components?.queryItems = [
            URLQueryItem(name: "broadcaster_id", value: credentials.broadcasterID),
            URLQueryItem(name: "reward_id", value: rewardID),
            URLQueryItem(name: "id", value: redemptionID),
        ]
        guard let url = components?.url else { throw RewardError.malformedResponse }

        do {
            _ = try await helix.sendJSON(
                url: url, method: "PATCH",
                credentials: credentials.helix,
                body: ["status": resolution.rawValue])
        } catch let error as HelixClient.HelixError {
            throw RewardError.from(error)
        }
    }

    // MARK: - Private Helpers

    /// Checks whether a reward ID still exists and is manageable by this client.
    private func rewardExists(credentials: Credentials, rewardID: String) async throws -> Bool {
        var components = URLComponents(string: baseURL + "/channel_points/custom_rewards")
        components?.queryItems = [
            URLQueryItem(name: "broadcaster_id", value: credentials.broadcasterID),
            URLQueryItem(name: "id", value: rewardID),
            URLQueryItem(name: "only_manageable_rewards", value: "true"),
        ]
        guard let url = components?.url else { return false }

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
        var components = URLComponents(string: baseURL + "/channel_points/custom_rewards")
        components?.queryItems = [
            URLQueryItem(name: "broadcaster_id", value: credentials.broadcasterID)
        ]
        guard let url = components?.url else { throw RewardError.malformedResponse }

        let body: [String: Any] = [
            "title": AppConstants.Twitch.songRequestRewardTitle,
            "cost": cost,
            "prompt": "Type a song name or paste an Apple Music / Spotify / YouTube link.",
            "is_user_input_required": true,
        ]

        let json: [String: Any]?
        do {
            json = try await helix.sendJSON(
                url: url, method: "POST",
                credentials: credentials.helix,
                body: body)
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
}
