//
//  TwitchChatService+Auth.swift
//  WolfWave
//
//  Created by Nathanial Henniges on 2026-01-08.
//  Copyright © 2026 MrDemonWolf, Inc. All rights reserved.
//

import Foundation

extension TwitchChatService {

    // MARK: - Bot Identity

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
}
