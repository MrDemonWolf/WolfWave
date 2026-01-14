//
//  TwitchDeviceAuth.swift
//  wolfwave
//
//  Created by MrDemonWolf, Inc. on 1/13/26.
//

import Foundation

// MARK: - Device Code Response

/// Response structure from Twitch's device authorization endpoint.
struct TwitchDeviceCodeResponse {
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
///     scopes: ["user:read:chat", "user:write:chat"]
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
final class TwitchDeviceAuth {
    
    // MARK: - Properties
    
    /// The Twitch client ID for this application
    private let clientID: String
    
    /// The OAuth scopes to request (e.g., "user:read:chat", "user:write:chat")
    private let scopes: [String]
    
    // MARK: - Initialization
    
    /// Creates a new Twitch Device Auth instance.
    ///
    /// - Parameters:
    ///   - clientID: Your Twitch application's client ID.
    ///   - scopes: Array of OAuth scope strings to request.
    init(clientID: String, scopes: [String]) {
        self.clientID = clientID
        self.scopes = scopes
    }
    
    // MARK: - Public Methods

    
    // MARK: - Public Methods
    
    /// Requests a device code from Twitch to begin the OAuth flow.
    ///
    /// This initiates the device authorization flow by requesting a device code
    /// and user code from Twitch. The user must visit the verification URL and
    /// enter the user code to authorize the application.
    ///
    /// - Returns: A `TwitchDeviceCodeResponse` containing the codes and URLs.
    /// - Throws: `TwitchDeviceAuthError` if the request fails.
    func requestDeviceCode() async throws -> TwitchDeviceCodeResponse {
        Log.info("OAuth: Requesting device code from Twitch", category: "OAuth")
        guard let url = URL(string: "https://id.twitch.tv/oauth2/device") else {
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

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw TwitchDeviceAuthError.invalidResponse
        }

        guard (200..<300).contains(http.statusCode) else {
            let message = String(data: data, encoding: .utf8) ?? "HTTP \(http.statusCode)"
            Log.error("OAuth: Device code request failed - \(message)", category: "OAuth")
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
        Log.info("OAuth: Device code received; user must visit verification URI", category: "OAuth")
        return TwitchDeviceCodeResponse(
            deviceCode: deviceCode,
            userCode: userCode,
            verificationURI: verificationURI,
            verificationURIComplete: verificationURIComplete,
            expiresIn: expiresIn,
            interval: interval
        )
    }
    
    /// Polls Twitch's token endpoint until the user authorizes or an error occurs.
    ///
    /// This method continuously polls Twitch's OAuth token endpoint at the specified
    /// interval until one of the following occurs:
    /// - User completes authorization → returns access token
    /// - User denies authorization → throws `.accessDenied`
    /// - Device code expires → throws `.expiredToken`
    /// - Maximum polling attempts exceeded → throws `.expiredToken`
    ///
    /// - Parameters:
    ///   - deviceCode: The device code from `requestDeviceCode()`.
    ///   - interval: The minimum polling interval in seconds.
    ///   - progress: Callback for progress updates (called on background thread).
    /// - Returns: The OAuth access token on successful authorization.
    /// - Throws: `TwitchDeviceAuthError` if authorization fails or times out.
    func pollForToken(deviceCode: String, interval: Int, progress: @escaping (String) -> Void)
        async throws -> String
    {
        var currentInterval = interval
        let tokenURL = URL(string: "https://id.twitch.tv/oauth2/token")!
        let grantType = "urn:ietf:params:oauth:grant-type:device_code"
        var pollAttempts = 0
        let maxAttempts = 600  // 10 minutes with 1-second base interval

        while true {
            try Task.checkCancellation()
            pollAttempts += 1

            if pollAttempts % 10 == 0 {
                // Update UI every 10 polls
                progress("Still waiting for Twitch approval... Please check your browser.")
            } else {
                progress("Waiting for Twitch approval...")
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

            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw TwitchDeviceAuthError.invalidResponse
            }

            if (200..<300).contains(http.statusCode) {
                guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                    let accessToken = json["access_token"] as? String
                else {
                    Log.error(
                        "OAuth: Failed to parse access token from response", category: "OAuth")
                    throw TwitchDeviceAuthError.invalidResponse
                }
                Log.info("OAuth: Device code token obtained successfully", category: "OAuth")
                return accessToken
            }

            // Check if we've exceeded max polling attempts
            guard pollAttempts < maxAttempts else {
                Log.error(
                    "OAuth: Device code polling timed out after \(pollAttempts) attempts",
                    category: "OAuth")
                throw TwitchDeviceAuthError.expiredToken
            }

            // Handle known error cases
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                let message = json["message"] as? String
            {
                Log.debug("OAuth: Device poll response - \(message)", category: "OAuth")
                switch message {
                case _ where message.contains("authorization_pending"):
                    // Keep polling
                    break
                case _ where message.contains("slow_down"):
                    currentInterval += 5
                    Log.info(
                        "OAuth: Received slow_down; increasing poll interval to \(currentInterval)s",
                        category: "OAuth")
                case _ where message.contains("access_denied"):
                    Log.error("OAuth: User denied authorization", category: "OAuth")
                    throw TwitchDeviceAuthError.accessDenied
                case _ where message.contains("expired_token") || message.contains("invalid_grant"):
                    Log.error("OAuth: Device code expired", category: "OAuth")
                    throw TwitchDeviceAuthError.expiredToken
                case _ where message.contains("invalid_client"):
                    Log.error("OAuth: Invalid client credentials", category: "OAuth")
                    throw TwitchDeviceAuthError.invalidClient
                default:
                    Log.error("OAuth: Unknown error - \(message)", category: "OAuth")
                    throw TwitchDeviceAuthError.unknown(message)
                }
            }

            try await Task.sleep(nanoseconds: UInt64(currentInterval) * 1_000_000_000)
        }
    }

    // MARK: - Private Helpers
    
    /// Encodes parameters as application/x-www-form-urlencoded for HTTP requests.
    ///
    /// - Parameter params: Dictionary of key-value pairs to encode.
    /// - Returns: URL-encoded data ready for HTTP body.
    private func formURLEncoded(params: [String: String]) -> Data {
        let allowed = CharacterSet(
            charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        let body =
            params
            .map { key, value in
                let encodedKey = key.addingPercentEncoding(withAllowedCharacters: allowed) ?? key
                let encodedValue =
                    value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
                return "\(encodedKey)=\(encodedValue)"
            }
            .joined(separator: "&")
        return body.data(using: .utf8) ?? Data()
    }
}
