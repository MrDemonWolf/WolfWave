//
//  TwitchDeviceAuth.swift
//  WolfWave
//
//  Created by Nathanial Henniges on 2026-01-08.
//  Copyright © 2026 MrDemonWolf, Inc. All rights reserved.
//

import Foundation

// MARK: - Device Code Response

/// Response structure from Twitch's device authorization endpoint.
nonisolated struct TwitchDeviceCodeResponse: Sendable {
    /// The device verification code used for polling
    let deviceCode: String
    
    /// The short code the user must enter at the verification URL
    let userCode: String
    
    /// The URL where the user must authorize the application
    let verificationURI: String
    
    /// Optional complete URI that includes the user code (for QR codes)
    let verificationURIComplete: String?
    
    /// How long (in seconds) the device code remains valid
    let expiresIn: Int
    
    /// Minimum interval (in seconds) between polling attempts
    let interval: Int
}

// MARK: - Device Auth Errors

/// Errors that can occur during the OAuth Device Code flow.
enum TwitchDeviceAuthError: LocalizedError {
    /// Server returned an invalid or unparseable response
    case invalidResponse
    
    /// User denied the authorization request
    case accessDenied
    
    /// Device code expired before user completed authorization
    case expiredToken
    
    /// Authorization is pending - user hasn't completed the flow yet
    case authorizationPending
    
    /// Client is polling too quickly - increase the polling interval when received
    case slowDown
    
    /// Invalid client credentials provided
    case invalidClient
    
    /// Other unknown error with message
    case unknown(String)

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "Invalid response from Twitch"
        case .accessDenied:
            return "Access denied by user"
        case .expiredToken:
            return "Device code expired"
        case .authorizationPending:
            return "Waiting for user authorization"
        case .slowDown:
            return "Polling too quickly"
        case .invalidClient:
            return "Invalid client credentials"
        case .unknown(let msg):
            return msg
        }
    }
}

// MARK: - Twitch Device Auth

/// Implements OAuth Device Code flow for Twitch authentication.
///
/// This flow is suitable for public clients (like desktop apps) where a client secret
/// cannot be securely embedded. Instead of running a local HTTP server, the user
/// enters a short code at Twitch's verification URL.
///
/// **OAuth Device Code Flow:**
/// 1. Request a device code from Twitch
/// 2. Display the user code and verification URL to the user
/// 3. Poll Twitch's token endpoint until the user authorizes
/// 4. Receive and store the access token
///
/// **Usage:**
/// ```swift
/// let auth = TwitchDeviceAuth(
///     clientID: "your-client-id",
///     scopes: ["user:read:chat", "user:write:chat", "channel:manage:polls"]
/// )
///
/// let response = try await auth.requestDeviceCode()
/// // Show user: response.userCode and response.verificationURI
///
/// let token = try await auth.pollForToken(
///     deviceCode: response.deviceCode,
///     interval: response.interval
/// ) { progress in
///     print(progress)
/// }
/// ```
///
/// **References:**
/// - [Twitch OAuth Device Code Flow](https://dev.twitch.tv/docs/authentication/getting-tokens-oauth/#device-code-grant-flow)
nonisolated final class TwitchDeviceAuth: Sendable {
    
    // MARK: - Properties
    
    /// The Twitch client ID for this application
    private let clientID: String
    
    /// The OAuth scopes to request (e.g., "user:read:chat", "user:write:chat")
    private let scopes: [String]

    /// URL session used for OAuth HTTP requests. Injectable for testing.
    private let session: URLSession

    // MARK: - Initialization

    /// Creates a new Twitch Device Auth instance.
    ///
    /// - Parameters:
    ///   - clientID: Your Twitch application's client ID.
    ///   - scopes: Array of OAuth scope strings to request.
    ///   - session: URL session for HTTP requests. Defaults to `.shared`.
    init(clientID: String, scopes: [String], session: URLSession = .shared) {
        self.clientID = clientID
        self.scopes = scopes
        self.session = session
    }
    
    // MARK: - Public Methods
    
    /// Requests a device code from Twitch, initiating Device Code Grant flow.
    ///
    /// RFC 8628 Compliance: Implements Twitch Device Code Grant per RFC 8628.
    /// No client secret is used; suitable for public client applications.
    ///
    /// User Flow:
    /// 1. Call this method to get device code and user code
    /// 2. Display user_code to user and provide verification_uri or verification_uri_complete
    /// 3. User visits URL and enters user_code
    /// 4. Call pollForToken() while waiting for approval
    /// 5. Token is returned when user completes approval
    ///
    /// Response Fields:
    /// - deviceCode: Server-side code; passed to pollForToken()
    /// - userCode: 8-character code shown to user for verification
    /// - verificationURI: URL base for approval (append user_code if needed)
    /// - verificationURIComplete: Complete URL including user_code (preferred)
    /// - expiresIn: Device code validity in seconds (usually 600s / 10 minutes)
    /// - interval: Recommended polling interval in seconds (usually 5s)
    ///
    /// Network Details:
    /// - 15s timeout for reliability
    /// - Requires internet connectivity; no retry logic
    ///
    /// Thread Safety: Can be called from any thread.
    ///
    /// Error Handling:
    /// - Throws InvalidClient if client ID is empty or invalid
    /// - Throws InvalidResponse if response structure is malformed
    /// - Throws Unknown if network error occurs
    ///
    /// - Returns: Device code response containing codes and polling parameters
    /// - Throws: `TwitchDeviceAuthError` if the request fails
    func requestDeviceCode() async throws -> TwitchDeviceCodeResponse {
        guard !clientID.isEmpty else {
            throw TwitchDeviceAuthError.invalidClient
        }
        
        guard let url = URL(string: AppConstants.API.twitchOAuthDevice) else {
            throw TwitchDeviceAuthError.invalidResponse
        }

        let params: [String: String] = [
            "client_id": clientID,
            "scope": scopes.joined(separator: " "),
        ]

        let body = formURLEncoded(params: params)
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = body
        request.timeoutInterval = 15

        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw TwitchDeviceAuthError.invalidResponse
            }

            guard (200..<300).contains(http.statusCode) else {
                let message = String(data: data, encoding: .utf8) ?? "HTTP \(http.statusCode)"
                
                if http.statusCode == 401 {
                    throw TwitchDeviceAuthError.invalidClient
                }
                throw TwitchDeviceAuthError.unknown(message)
            }

            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                let deviceCode = json["device_code"] as? String,
                let userCode = json["user_code"] as? String,
                let verificationURI = json["verification_uri"] as? String,
                let expiresIn = json["expires_in"] as? Int,
                let interval = json["interval"] as? Int
            else {
                throw TwitchDeviceAuthError.invalidResponse
            }

            let verificationURIComplete = json["verification_uri_complete"] as? String
            return TwitchDeviceCodeResponse(
                deviceCode: deviceCode,
                userCode: userCode,
                verificationURI: verificationURI,
                verificationURIComplete: verificationURIComplete,
                expiresIn: expiresIn,
                interval: interval
            )
        } catch let error as TwitchDeviceAuthError {
            throw error
        } catch {
            throw TwitchDeviceAuthError.unknown(error.localizedDescription)
        }
    }
    
    /// Polls Twitch for token completion, implementing RFC 8628 Device Code Grant with linear backoff.
    ///
    /// Polling Strategy:
    /// - Polls at `interval` seconds, respecting Twitch slow_down requests
    /// - Increases interval by 5 seconds when slow_down is received (per Twitch spec)
    /// - Respects expiresIn timeout; stops polling when device code expires
    /// - Task cancellation is checked each iteration; cancellation is respected immediately
    ///
    /// Progress Callback:
    /// - Called every 10 polling attempts or on first poll
    /// - Called on background thread; dispatch to main if updating UI
    ///
    /// Network Details:
    /// - 15s timeout per request for reliability
    /// - Retries transient network errors (ECONNRESET, etc.)
    /// - Permanent failures (auth_denied, expired_token) throw immediately
    ///
    /// Thread Safety: Can be called from any thread. Cancellation-safe.
    ///
    /// Error Handling:
    /// - Throws InvalidClient if deviceCode is empty
    /// - Throws DeviceFlowTimeout if polling exceeds expiresIn
    /// - Throws AuthorizationDenied if user rejects on browser
    /// - Throws InvalidResponse if token response is malformed
    ///
    /// - Parameters:
    ///   - deviceCode: The device code from requestDeviceCode()
    ///   - interval: Initial polling interval in seconds (from requestDeviceCode())
    ///   - expiresIn: Device code expiration time in seconds (optional)
    ///   - progress: Called periodically with status messages
    /// - Returns: OAuth access token on successful authorization
    /// - Throws: TwitchDeviceAuthError describing the failure
    func pollForToken(
        deviceCode: String,
        interval: Int,
        expiresIn: Int? = nil,
        progress: @escaping (String) -> Void
    ) async throws -> String
    {
        // Validate inputs
        guard !deviceCode.isEmpty else {
            throw TwitchDeviceAuthError.invalidClient
        }
        guard interval > 0 else {
            throw TwitchDeviceAuthError.invalidResponse
        }
        
        var currentInterval = interval
        guard let tokenURL = URL(string: AppConstants.API.twitchOAuthToken) else {
            throw TwitchDeviceAuthError.invalidResponse
        }
        let grantType = "urn:ietf:params:oauth:grant-type:device_code"
        var pollAttempts = 0
        // Compute max attempts from expiresIn when available, otherwise fall back to a sensible default
        let maxAttempts: Int = {
            if let expires = expiresIn, expires > 0 {
                // ensure at least one attempt; guard against tiny intervals
                let per = max(1, currentInterval)
                return max(1, expires / per + 2)
            }
            return 600
        }()

        while true {
            try Task.checkCancellation()
            pollAttempts += 1

            if pollAttempts % 10 == 0 {
                // Update UI every 10 polls
                progress("Still waiting on Twitch. Check your browser tab.")
            } else if pollAttempts == 1 {
                progress("Waiting for you to approve on Twitch\u{2026}")
            }

            let params: [String: String] = [
                "client_id": clientID,
                "grant_type": grantType,
                "device_code": deviceCode,
            ]

            let body = formURLEncoded(params: params)
            var request = URLRequest(url: tokenURL)
            request.httpMethod = "POST"
            request.setValue(
                "application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
            request.httpBody = body
            request.timeoutInterval = 15

            do {
                let (data, response) = try await session.data(for: request)
                guard let http = response as? HTTPURLResponse else {
                    throw TwitchDeviceAuthError.invalidResponse
                }

                if (200..<300).contains(http.statusCode) {
                    guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                        let accessToken = json["access_token"] as? String,
                        !accessToken.isEmpty
                    else {
                        Log.error(
                            "TwitchDeviceAuth: Failed to parse access token from response", category: "Twitch")
                        throw TwitchDeviceAuthError.invalidResponse
                    }
                    Log.info("TwitchDeviceAuth: Device code token obtained successfully", category: "Twitch")
                    return accessToken
                }

                // Check if we've exceeded max polling attempts
                guard pollAttempts < maxAttempts else {
                    Log.error(
                        "TwitchDeviceAuth: Device code polling timed out after \(pollAttempts) attempts",
                        category: "Twitch")
                    throw TwitchDeviceAuthError.expiredToken
                }

                // Prefer structured OAuth error fields if present per Twitch docs
                if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    if let errorCode = json["error"] as? String {
                        Log.debug("TwitchDeviceAuth: Device poll error code - \(errorCode)", category: "Twitch")
                        switch errorCode {
                        case "authorization_pending":
                            // continue polling
                            break
                        case "slow_down":
                            currentInterval += 5
                            Log.info(
                                "TwitchDeviceAuth: Received slow_down; increasing poll interval to \(currentInterval)s",
                                category: "Twitch")
                        case "access_denied":
                            Log.error("TwitchDeviceAuth: User denied authorization", category: "Twitch")
                            throw TwitchDeviceAuthError.accessDenied
                        case "expired_token", "invalid_grant":
                            Log.error("TwitchDeviceAuth: Device code expired", category: "Twitch")
                            throw TwitchDeviceAuthError.expiredToken
                        case "invalid_client":
                            Log.error("TwitchDeviceAuth: Invalid client credentials", category: "Twitch")
                            throw TwitchDeviceAuthError.invalidClient
                        default:
                            let message = json["error_description"] as? String
                                ?? (json["message"] as? String)
                                ?? errorCode
                            Log.error("TwitchDeviceAuth: Unknown error - \(message)", category: "Twitch")
                            throw TwitchDeviceAuthError.unknown(message)
                        }
                    } else if let message = json["message"] as? String {
                        // Fallback to message parsing for older responses
                        Log.debug("TwitchDeviceAuth: Device poll response (fallback) - \(message)", category: "Twitch")
                        if message.contains("authorization_pending") {
                            // continue
                        } else if message.contains("slow_down") {
                            currentInterval += 5
                        } else if message.contains("access_denied") {
                            throw TwitchDeviceAuthError.accessDenied
                        } else if message.contains("expired_token") || message.contains("invalid_grant") {
                            throw TwitchDeviceAuthError.expiredToken
                        } else if message.contains("invalid_client") {
                            throw TwitchDeviceAuthError.invalidClient
                        } else {
                            throw TwitchDeviceAuthError.unknown(message)
                        }
                    }
                }

                // Device-code poll: tolerance only ever delays the wakeup (never
                // earlier), so it can't trip Twitch's slow_down rate limit while
                // still letting macOS coalesce the timer.
                try await Task.sleep(for: .seconds(currentInterval), tolerance: .seconds(Double(currentInterval) * 0.1))
            } catch let error as TwitchDeviceAuthError {
                throw error
            } catch {
                // Network error or cancellation
                if (error as? CancellationError) != nil {
                    throw error
                }
                Log.error("TwitchDeviceAuth: Network error during polling - \(error.localizedDescription)", category: "Twitch")
                throw TwitchDeviceAuthError.unknown(error.localizedDescription)
            }
        }
    }

    // MARK: - Private Helpers

    /// Encodes parameters as application/x-www-form-urlencoded for HTTP requests.
    ///
    /// Delegates to ``HTTPClient/formURLEncodedBody(_:)`` so the percent-encoding
    /// rule is shared with the rest of the app instead of redefined here.
    ///
    /// - Parameter params: Dictionary of key-value pairs to encode.
    /// - Returns: URL-encoded data ready for HTTP body.
    private func formURLEncoded(params: [String: String]) -> Data {
        HTTPClient.formURLEncodedBody(params)
    }
}
