//
//  MockURLProtocol.swift
//  WolfWave
//
//  Created by Nathanial Henniges on 2026-05-22.
//  Copyright © 2026 MrDemonWolf, Inc. All rights reserved.
//

import Foundation

// MARK: - Mock URL Protocol

/// A `URLProtocol` subclass that intercepts every request made on a session it
/// is registered with and answers it from a test-supplied handler — no real
/// network traffic.
///
/// Use it to drive networking services (`HTTPClient`, `ArtworkService`,
/// `LinkResolverService`, `TwitchDeviceAuth`, …) deterministically in unit
/// tests.
///
/// Example:
/// ```swift
/// MockURLProtocol.requestHandler = { request in
///     let response = MockURLProtocol.httpResponse(for: request, status: 200)
///     return (response, Data(#"{"ok":true}"#.utf8))
/// }
/// let session = MockURLProtocol.makeSession()
/// // ... inject `session` into the service under test ...
/// MockURLProtocol.reset() // in tearDown
/// ```
final class MockURLProtocol: URLProtocol {

    // MARK: - Types

    /// Produces the stubbed result for an intercepted request. Throw to
    /// simulate a transport-level failure.
    typealias Handler = @Sendable (URLRequest) throws -> (HTTPURLResponse, Data)

    // MARK: - Stub Configuration

    /// Handler invoked for every intercepted request. Set this before
    /// exercising the service under test; clear it with `reset()` in `tearDown`.
    nonisolated(unsafe) static var requestHandler: Handler?

    /// Builds a `URLSession` that routes all traffic through `MockURLProtocol`.
    static func makeSession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        return URLSession(configuration: config)
    }

    /// Clears the installed handler. Call from `tearDown` to isolate tests.
    static func reset() {
        requestHandler = nil
    }

    /// Convenience builder for an `HTTPURLResponse` matching a request's URL.
    static func httpResponse(
        for request: URLRequest,
        status: Int,
        headers: [String: String] = [:]
    ) -> HTTPURLResponse {
        let url = request.url ?? URL(string: "https://example.invalid")!
        return HTTPURLResponse(
            url: url,
            statusCode: status,
            httpVersion: "HTTP/1.1",
            headerFields: headers
        )!
    }

    // MARK: - URLProtocol

    override class func canInit(with request: URLRequest) -> Bool { true }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = MockURLProtocol.requestHandler else {
            client?.urlProtocol(self, didFailWithError: URLError(.unsupportedURL))
            return
        }
        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}
