//
//  HTTPClient.swift
//  WolfWave
//
//  Created by Nathanial Henniges on 2026-05-16.
//  Copyright © 2026 MrDemonWolf, Inc. All rights reserved.
//

import Foundation

/// Lightweight HTTP wrapper around `URLSession` for JSON request/response cycles.
///
/// Centralizes request construction (bearer auth header, content type),
/// status-code validation, and JSON decoding so services do not duplicate
/// boilerplate at every call site.
///
/// - Note: For WebSocket connections (`URLSessionWebSocketTask`), continue to
///   use a dedicated `URLSession` configured per service. This client targets
///   request/response HTTP only.
///
/// Example:
/// ```swift
/// let user: TwitchUser = try await HTTPClient.shared.get(
///     url: url,
///     headers: ["Authorization": "Bearer \(token)", "Client-Id": clientID]
/// )
/// ```
nonisolated struct HTTPClient: Sendable {

    // MARK: - Errors

    /// Errors produced by `HTTPClient` request/response handling.
    enum HTTPError: Error, LocalizedError {
        /// The server returned a non-2xx status code. Includes the status code
        /// and the raw response body for diagnostics.
        case unexpectedStatus(Int, body: String)

        /// The response was missing or could not be cast to `HTTPURLResponse`.
        case invalidResponse

        /// JSON decoding failed.
        case decodingFailed(underlying: Error)

        /// The underlying transport (`URLSession`) failed.
        case transport(underlying: Error)

        var errorDescription: String? {
            switch self {
            case let .unexpectedStatus(code, body):
                return "HTTP \(code): \(body.prefix(200))"
            case .invalidResponse:
                return "Invalid HTTP response"
            case let .decodingFailed(error):
                return "JSON decoding failed: \(error.localizedDescription)"
            case let .transport(error):
                return "Transport error: \(error.localizedDescription)"
            }
        }
    }

    // MARK: - Properties

    /// Shared default client backed by `URLSession.shared`.
    static let shared = HTTPClient()

    /// Underlying URL session used to perform requests.
    let session: URLSession

    /// Decoder applied to JSON response bodies. Defaults to snake-case.
    let decoder: JSONDecoder

    // MARK: - Init

    /// Creates a new HTTP client.
    ///
    /// - Parameters:
    ///   - session: URL session to use. Defaults to `.shared`.
    ///   - decoder: JSON decoder for response bodies. Defaults to
    ///     `JSONCoders.snakeCase`.
    init(session: URLSession = .shared, decoder: JSONDecoder = JSONCoders.snakeCase) {
        self.session = session
        self.decoder = decoder
    }

    // MARK: - Requests

    /// Performs a GET request and decodes the JSON response.
    ///
    /// - Parameters:
    ///   - url: Target URL.
    ///   - headers: Additional HTTP headers (e.g. `Authorization`, `Client-Id`).
    /// - Returns: A value of type `T` decoded from the response body.
    /// - Throws: `HTTPError` on non-2xx status, decoding failure, or transport
    ///   error.
    func get<T: Decodable>(url: URL, headers: [String: String] = [:]) async throws -> T {
        let request = makeRequest(url: url, method: "GET", headers: headers, body: nil)
        return try await perform(request)
    }

    /// Performs a POST request with a URL-form-encoded body and decodes the
    /// JSON response.
    ///
    /// - Parameters:
    ///   - url: Target URL.
    ///   - form: Key/value pairs to be percent-encoded as
    ///     `application/x-www-form-urlencoded`.
    ///   - headers: Additional HTTP headers.
    /// - Returns: A value of type `T` decoded from the response body.
    /// - Throws: `HTTPError` on non-2xx status, decoding failure, or transport
    ///   error.
    func postForm<T: Decodable>(
        url: URL,
        form: [String: String],
        headers: [String: String] = [:]
    ) async throws -> T {
        var combinedHeaders = headers
        combinedHeaders["Content-Type"] = "application/x-www-form-urlencoded"

        let body = form
            .map { key, value in
                let k = key.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? key
                let v = value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? value
                return "\(k)=\(v)"
            }
            .joined(separator: "&")
            .data(using: .utf8)

        let request = makeRequest(url: url, method: "POST", headers: combinedHeaders, body: body)
        return try await perform(request)
    }

    /// Performs an arbitrary request and returns the raw response without
    /// validating the status code.
    ///
    /// Use when the caller needs to inspect the HTTP status, headers, or
    /// raw body, for example sites that branch on 401 / 403 / 409 or
    /// capture rate-limit headers from the response.
    ///
    /// - Parameter request: Fully-constructed request to perform.
    /// - Returns: Tuple of `(Data, HTTPURLResponse)`.
    /// - Throws: `HTTPError.invalidResponse` if the response isn't HTTP, or
    ///   `HTTPError.transport` on session failure. Non-2xx statuses are
    ///   **not** thrown. The caller decides.
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await transport(request)
        guard let http = response as? HTTPURLResponse else {
            throw HTTPError.invalidResponse
        }
        return (data, http)
    }

    /// Fetches raw bytes for a URL with no decoding (e.g. image download).
    ///
    /// - Parameters:
    ///   - url: Target URL.
    ///   - headers: Additional HTTP headers.
    /// - Returns: The raw response `Data`.
    /// - Throws: `HTTPError` on non-2xx status or transport error.
    func data(url: URL, headers: [String: String] = [:]) async throws -> Data {
        let request = makeRequest(url: url, method: "GET", headers: headers, body: nil)
        let (data, response) = try await transport(request)
        try validate(response: response, body: data)
        return data
    }

    // MARK: - Private Helpers

    private func makeRequest(
        url: URL,
        method: String,
        headers: [String: String],
        body: Data?
    ) -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.httpBody = body
        for (key, value) in headers {
            request.setValue(value, forHTTPHeaderField: key)
        }
        return request
    }

    private func perform<T: Decodable>(_ request: URLRequest) async throws -> T {
        let (data, response) = try await transport(request)
        try validate(response: response, body: data)
        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            throw HTTPError.decodingFailed(underlying: error)
        }
    }

    private func transport(_ request: URLRequest) async throws -> (Data, URLResponse) {
        do {
            return try await session.data(for: request)
        } catch {
            throw HTTPError.transport(underlying: error)
        }
    }

    private func validate(response: URLResponse, body: Data) throws {
        guard let http = response as? HTTPURLResponse else {
            throw HTTPError.invalidResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            let bodyString = String(data: body, encoding: .utf8) ?? ""
            throw HTTPError.unexpectedStatus(http.statusCode, body: bodyString)
        }
    }
}
