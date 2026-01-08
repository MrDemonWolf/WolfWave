//
//  TwitchDeviceAuth.swift
//  wolfwave
//
//  Implements the OAuth Device Code flow for Twitch, suitable for public clients
//  where a client secret is not shipped. The flow avoids running a local HTTP
//  server and instead asks the user to enter a short code at a verification URL.

import Foundation

struct TwitchDeviceCodeResponse {
    let deviceCode: String
    let userCode: String
    let verificationURI: String
    let verificationURIComplete: String?
    let expiresIn: Int
    let interval: Int
}

enum TwitchDeviceAuthError: LocalizedError {
    case invalidResponse
    case accessDenied
    case expiredToken
    case authorizationPending
    case slowDown
    case invalidClient
    case unknown(String)

    var errorDescription: String? {
        switch self {
        case .invalidResponse: return "Invalid response from Twitch"
        case .accessDenied: return "Access denied by user"
        case .expiredToken: return "Device code expired"
        case .authorizationPending: return "Waiting for user authorization"
        case .slowDown: return "Polling too quickly"
        case .invalidClient: return "Invalid client credentials"
        case .unknown(let msg): return msg
        }
    }
}

final class TwitchDeviceAuth {
    private let clientID: String
    private let scopes: [String]

    init(clientID: String, scopes: [String]) {
        self.clientID = clientID
        self.scopes = scopes
    }

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

    func pollForToken(deviceCode: String, interval: Int, progress: @escaping (String) -> Void)
        async throws -> String
    {
        var currentInterval = interval
        let tokenURL = URL(string: "https://id.twitch.tv/oauth2/token")!
        let grantType = "urn:ietf:params:oauth:grant-type:device_code"

        while true {
            try Task.checkCancellation()
            progress("Waiting for Twitch approval...")

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
                    throw TwitchDeviceAuthError.invalidResponse
                }
                Log.info("OAuth: Device code token obtained", category: "OAuth")
                return accessToken
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
                case _ where message.contains("access_denied"):
                    throw TwitchDeviceAuthError.accessDenied
                case _ where message.contains("expired_token") || message.contains("invalid_grant"):
                    throw TwitchDeviceAuthError.expiredToken
                case _ where message.contains("invalid_client"):
                    throw TwitchDeviceAuthError.invalidClient
                default:
                    throw TwitchDeviceAuthError.unknown(message)
                }
            }

            try await Task.sleep(nanoseconds: UInt64(currentInterval) * 1_000_000_000)
        }
    }

    // MARK: - Helpers

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
