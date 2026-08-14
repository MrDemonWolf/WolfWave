//
//  TwitchChatService+Auth.swift
//  WolfWave
//
//  Created by Nathanial Henniges on 2026-07-15.
//  Copyright © 2026 MrDemonWolf, Inc. All rights reserved.
//

import Foundation

extension TwitchChatService {

    // MARK: - Bot Identity

    /// Static method to resolve bot identity without an instance.
    static func resolveBotIdentityStatic(
        token: String,
        clientID: String,
        credentialRevision: UInt64? = nil
    ) async throws {
        guard !token.isEmpty else { throw ConnectionError.invalidCredentials }
        guard !clientID.isEmpty else { throw ConnectionError.missingClientID }

        // `init()` is `@MainActor`; hop to construct.
        let expectedRevision: UInt64
        if let credentialRevision {
            expectedRevision = credentialRevision
        } else if let matchingRevision = TwitchCredentialStore.shared.revision(
            matchingAccessToken: token
        ) {
            expectedRevision = matchingRevision
        } else {
            throw CancellationError()
        }
        let service = await MainActor.run { TwitchChatService() }
        let identity = try await service.fetchBotIdentity(token: token, clientID: clientID)
        try Task.checkCancellation()
        let resolvedUsername = identity.displayName.isEmpty ? identity.login : identity.displayName

        guard try TwitchCredentialStore.shared.commitIdentity(
            username: resolvedUsername,
            userID: identity.userID,
            matchingAccessToken: token,
            expectedRevision: expectedRevision
        ) else {
            throw CancellationError()
        }
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
            response = try await helixHTTPClient.get(
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

        return BotIdentity(userID: first.id, login: first.login, displayName: displayName)
    }

    /// Validates an OAuth token with Twitch and verifies required scopes.
    ///
    /// Twitch documents HTTP 401 as its definitive invalid-token response.
    /// Every ambiguous failure preserves the local session for a later retry.
    func validateToken(
        _ token: String,
        requiredScopes: [String] = ["user:read:chat", "user:write:chat"],
        expectedClientID: String? = TwitchChatService.resolveClientID(),
        http: HTTPClient = .shared
    ) async -> TokenValidationResult {
        guard !token.isEmpty else { return .invalid }
        guard let url = URL(string: "https://id.twitch.tv/oauth2/validate") else {
            Log.error("TwitchChatService: Invalid validate URL", category: "Twitch")
            return .temporarilyUnavailable
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 15
        // Per Twitch docs, use "OAuth <token>" for the validate endpoint
        request.setValue("OAuth \(token)", forHTTPHeaderField: "Authorization")
        request.setValue(HTTPClient.defaultUserAgent, forHTTPHeaderField: "User-Agent")

        do {
            let (data, response) = try await http.send(request)

            guard (200..<300).contains(response.statusCode) else {
                if response.statusCode == 401 {
                    Log.warn("TwitchChatService: Stored OAuth token is invalid or expired", category: "Twitch")
                    return .invalid
                } else {
                    Log.warn(
                        "TwitchChatService: Token validation temporarily unavailable (HTTP \(response.statusCode))",
                        category: "Twitch")
                    return .temporarilyUnavailable
                }
            }

            guard let parsed = try? JSONCoders.default.decode(
                TwitchValidateResponse.self,
                from: data
            ) else {
                Log.warn("TwitchChatService: Could not parse token validate response", category: "Twitch")
                return .temporarilyUnavailable
            }

            if let expectedClientID, !expectedClientID.isEmpty {
                guard let validatedClientID = parsed.clientID else {
                    Log.warn(
                        "TwitchChatService: Token validate response omitted client_id",
                        category: "Twitch")
                    return .temporarilyUnavailable
                }
                guard validatedClientID == expectedClientID else {
                    Log.warn(
                        "TwitchChatService: Token belongs to a different Twitch client",
                        category: "Twitch")
                    return .invalid
                }
            }

            guard let scopes = parsed.scopes else {
                Log.warn("TwitchChatService: Token validate response omitted scopes", category: "Twitch")
                return .temporarilyUnavailable
            }
            // Vote-skip Polls mode needs the polls scope. Only require it when
            // the user has actually enabled Polls mode, so existing users are
            // not forced to re-authorize unless they opt in.
            var effectiveScopes = requiredScopes
            let defaults = DefaultsStore.store
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
                // Not `.invalid`: Twitch just accepted this token. Reporting a
                // scope gap as an expired session tells the user to reconnect
                // for a session that still works, and the re-auth flag that
                // follows also stops the hourly validator, so the live token
                // would never be re-checked.
                return .missingScopes(missing)
            }
            return .valid
        } catch {
            Log.error(
                "TwitchChatService: Token validation temporarily unavailable - \(error.localizedDescription)",
                category: "Twitch")
            return .temporarilyUnavailable
        }
    }

    /// Revalidates the stored token when Polls mode is enabled on an already
    /// connected EventSub session. Only a parsed missing scope or 401 is
    /// definitive enough to require interactive reauthorization.
    func validateLivePollScope() async -> PollScopeValidation {
        if let pollScopeValidationOverride {
            return await pollScopeValidationOverride()
        }
        guard let token = oauthToken,
              let url = URL(string: "https://id.twitch.tv/oauth2/validate") else {
            return .missing
        }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 15
        request.setValue("OAuth \(token)", forHTTPHeaderField: "Authorization")
        request.setValue(HTTPClient.defaultUserAgent, forHTTPHeaderField: "User-Agent")

        do {
            let (data, http) = try await HTTPClient.shared.send(request)
            return Self.pollScopeValidation(
                statusCode: http.statusCode,
                responseData: data)
        } catch {
            Log.warn(
                "TwitchChatService: Poll scope validation was inconclusive - \(error.localizedDescription)",
                category: "Twitch")
            return .indeterminate
        }
    }

    /// Pure classifier used by live refresh and focused tests.
    nonisolated static func pollScopeValidation(
        statusCode: Int?,
        responseData: Data?
    ) -> PollScopeValidation {
        guard let statusCode else { return .indeterminate }
        if statusCode == 401 { return .missing }
        guard (200..<300).contains(statusCode),
              let responseData,
              let parsed = try? JSONCoders.default.decode(
                  TwitchValidateResponse.self,
                  from: responseData),
              let scopes = parsed.scopes else {
            return .indeterminate
        }
        return scopes.contains(AppConstants.Twitch.pollsScope)
            ? .present
            : .missing
    }

    // MARK: - Username Resolution

    /// Normalizes a Twitch login and rejects characters that could change
    /// Helix query structure. Twitch logins are lowercase ASCII letters,
    /// digits, or underscores and are at most 25 characters.
    nonisolated static func normalizedChannelName(_ raw: String) -> String? {
        let normalized = raw
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        guard !normalized.isEmpty,
              normalized.count <= 25,
              normalized.utf8.allSatisfy({ byte in
                  (97...122).contains(byte)
                      || (48...57).contains(byte)
                      || byte == 95
              }) else {
            return nil
        }
        return normalized
    }

    /// Validates whether a Twitch channel name exists by resolving it to a user ID.
    ///
    /// `GET /helix/users` needs no scope, so 401 is the only outcome that
    /// implicates the token. A 403, 429, or 5xx means Twitch accepted the
    /// sign-in and refused the lookup for its own reasons, which the caller
    /// surfaces as "your sign-in is fine" rather than prompting a reconnect
    /// that cannot help.
    func validateChannelExists(_ channelName: String, token: String, clientID: String) async -> ChannelValidationResult {
        do {
            let userID = try await resolveUsername(channelName, token: token, clientID: clientID)
            return userID.isEmpty ? .notFound : .exists
        } catch let error as ConnectionError {
            switch error {
            case .authenticationFailed:
                return .authenticationFailed
            case .channelNotFound:
                return .notFound
            case .notPermitted(let status):
                return .notPermitted(status: status)
            default:
                return .error(error.localizedDescription)
            }
        } catch {
            return .error(error.localizedDescription)
        }
    }

    /// Resolves a Twitch username to a user ID.
    func resolveUsername(_ username: String, token: String, clientID: String) async throws -> String {
        guard let sanitizedUsername = Self.normalizedChannelName(username) else {
            throw ConnectionError.networkError("Invalid username format")
        }
        guard var components = URLComponents(string: apiBaseURL + "/users") else {
            throw ConnectionError.networkError("Invalid users endpoint")
        }
        components.queryItems = [
            URLQueryItem(name: "login", value: sanitizedUsername)
        ]
        guard let url = components.url else {
            throw ConnectionError.networkError("Invalid users endpoint")
        }

        var request = try HelixClient.buildRequest(
            url: url, method: "GET",
            credentials: .init(token: token, clientID: clientID))
        request.timeoutInterval = 15

        do {
            let (data, http) = try await helixHTTPClient.send(request)
            guard (200..<300).contains(http.statusCode) else {
                // 401 is the only status that implicates the token here: this
                // endpoint requires no scope. Everything else keeps its status
                // so the caller can say what actually happened.
                if http.statusCode == 401 { throw ConnectionError.authenticationFailed }
                throw ConnectionError.notPermitted(status: http.statusCode)
            }

            let parsed: HelixUsersResponse
            do {
                parsed = try JSONCoders.snakeCase.decode(HelixUsersResponse.self, from: data)
            } catch {
                throw ConnectionError.networkError(
                    "Failed to decode username response: \(error.localizedDescription)")
            }

            // Twitch answers an unknown login with 200 and an empty data array.
            // That is a real answer, not a failed lookup.
            guard let first = parsed.data.first, !first.id.isEmpty else {
                throw ConnectionError.channelNotFound
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
