//
//  HelixClient.swift
//  WolfWave
//
//  Created by Nathanial Henniges on 2026-05-28.
//  Copyright © 2026 MrDemonWolf, Inc. All rights reserved.
//

import Foundation

/// Wrapper around `HTTPClient` that knows how to talk to the Twitch Helix API.
///
/// Centralizes the auth header (`Authorization: Bearer …`, `Client-Id: …`),
/// JSON body encoding, status validation, and Helix-shaped error mapping so
/// service code does not rebuild the same `URLRequest` scaffolding at every
/// endpoint call site.
///
/// The type holds no mutable state and is trivially `Sendable`.
nonisolated struct HelixClient: Sendable {

    // MARK: - Types

    /// Credentials needed for a Helix call.
    struct Credentials: Sendable {
        let token: String
        let clientID: String

        init(token: String, clientID: String) {
            self.token = token
            self.clientID = clientID
        }
    }

    /// Errors produced by Helix calls.
    enum HelixError: Error, LocalizedError, Equatable {
        /// The server returned a non-2xx status code. Includes the status code
        /// and the raw response body for diagnostics.
        case http(status: Int, body: String)
        /// The token was rejected (HTTP 401).
        case unauthorized(body: String)
        /// The endpoint is rate-limited (HTTP 429).
        case rateLimited(body: String)
        /// The response was missing or malformed.
        case malformedResponse
        /// Encoding the request body failed.
        case encodingFailed(message: String)
        /// JSON decoding of the response failed.
        case decodingFailed(message: String)
        /// The underlying transport (`URLSession`) failed.
        case transport(message: String)

        var errorDescription: String? {
            switch self {
            case let .http(status, body):
                return "Twitch API error \(status): \(body.prefix(200))"
            case let .unauthorized(body):
                return "Twitch token rejected: \(body.prefix(200))"
            case let .rateLimited(body):
                return "Twitch rate limit hit: \(body.prefix(200))"
            case .malformedResponse:
                return "Unexpected response from Twitch."
            case let .encodingFailed(message):
                return "Failed to encode Helix request body: \(message)"
            case let .decodingFailed(message):
                return "Failed to decode Helix response: \(message)"
            case let .transport(message):
                return "Network error: \(message)"
            }
        }
    }

    // MARK: - Properties

    /// HTTP client used to perform the underlying request.
    let http: HTTPClient

    // MARK: - Init

    init(http: HTTPClient = .shared) {
        self.http = http
    }

    // MARK: - Typed Requests

    /// Performs a GET request and decodes the JSON response.
    ///
    /// - Parameters:
    ///   - url: Helix endpoint URL.
    ///   - credentials: Caller credentials.
    /// - Returns: A value of type `T` decoded from the response body.
    /// - Throws: `HelixError` on transport, status, or decoding failure.
    func get<T: Decodable>(
        url: URL,
        credentials: Credentials
    ) async throws -> T {
        let request = try makeRequest(
            url: url, method: "GET", credentials: credentials, body: nil)
        let (data, http) = try await send(request)
        try validate(http: http, data: data)
        return try decode(data: data)
    }

    /// Performs a POST request with a JSON body and decodes the response.
    func post<T: Decodable>(
        url: URL,
        credentials: Credentials,
        body: [String: Any]
    ) async throws -> T {
        let request = try makeRequest(
            url: url, method: "POST", credentials: credentials, body: body)
        let (data, http) = try await send(request)
        try validate(http: http, data: data)
        return try decode(data: data)
    }

    /// Performs a PATCH request with a JSON body and decodes the response.
    func patch<T: Decodable>(
        url: URL,
        credentials: Credentials,
        body: [String: Any]
    ) async throws -> T {
        let request = try makeRequest(
            url: url, method: "PATCH", credentials: credentials, body: body)
        let (data, http) = try await send(request)
        try validate(http: http, data: data)
        return try decode(data: data)
    }

    // MARK: - Untyped (JSON Object) Requests

    /// Performs a request and returns the parsed JSON object dictionary, or
    /// `nil` for an empty 204 body. Use when the response shape is dynamic and
    /// strict `Decodable` typing isn't worth the boilerplate.
    @discardableResult
    func sendJSON(
        url: URL,
        method: String,
        credentials: Credentials,
        body: [String: Any]? = nil
    ) async throws -> [String: Any]? {
        let request = try makeRequest(
            url: url, method: method, credentials: credentials, body: body)
        let (data, http) = try await send(request)
        try validate(http: http, data: data)
        guard !data.isEmpty else { return nil }
        return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }

    /// Performs a request and returns `(data, statusCode)` without status
    /// validation. Use when the caller needs to branch on a specific non-2xx
    /// code (e.g. 404 → "doesn't exist", 403 → "missing scope").
    func sendRaw(
        url: URL,
        method: String,
        credentials: Credentials,
        body: [String: Any]? = nil
    ) async throws -> (Data, Int) {
        let request = try makeRequest(
            url: url, method: method, credentials: credentials, body: body)
        let (data, http) = try await send(request)
        return (data, http.statusCode)
    }

    // MARK: - Private Helpers

    /// Standard Helix headers: auth + client id + JSON content type.
    static func headers(for credentials: Credentials) -> [String: String] {
        [
            "Authorization": "Bearer \(credentials.token)",
            "Client-Id": credentials.clientID,
            "Content-Type": "application/json",
        ]
    }

    private func makeRequest(
        url: URL,
        method: String,
        credentials: Credentials,
        body: [String: Any]?
    ) throws -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = method
        for (key, value) in Self.headers(for: credentials) {
            request.setValue(value, forHTTPHeaderField: key)
        }
        if let body {
            do {
                request.httpBody = try JSONSerialization.data(withJSONObject: body)
            } catch {
                throw HelixError.encodingFailed(message: error.localizedDescription)
            }
        }
        return request
    }

    private func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        do {
            return try await http.send(request)
        } catch let error as HTTPClient.HTTPError {
            switch error {
            case .invalidResponse:
                throw HelixError.malformedResponse
            case let .transport(underlying):
                throw HelixError.transport(message: underlying.localizedDescription)
            case let .decodingFailed(underlying):
                throw HelixError.decodingFailed(message: underlying.localizedDescription)
            case let .unexpectedStatus(status, body):
                throw mappedStatus(status, body: body)
            }
        } catch {
            throw HelixError.transport(message: error.localizedDescription)
        }
    }

    private func validate(http: HTTPURLResponse, data: Data) throws {
        let status = http.statusCode
        guard (200..<300).contains(status) else {
            throw mappedStatus(status, body: String(data: data, encoding: .utf8) ?? "")
        }
    }

    private func mappedStatus(_ status: Int, body: String) -> HelixError {
        switch status {
        case 401: return .unauthorized(body: body)
        case 429: return .rateLimited(body: body)
        default: return .http(status: status, body: body)
        }
    }

    private func decode<T: Decodable>(data: Data) throws -> T {
        do {
            return try JSONCoders.snakeCase.decode(T.self, from: data)
        } catch {
            throw HelixError.decodingFailed(message: error.localizedDescription)
        }
    }
}
