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
/// is registered with and answers it from a test-supplied handler. No real
/// network traffic.
///
/// Use it to drive networking services (`HTTPClient`, `ArtworkService`,
/// `LinkResolverService`, `TwitchDeviceAuth`, …) deterministically in unit
/// tests.
///
/// Example:
/// ```swift
/// let session = MockURLProtocol.makeSession { request in
///     let response = MockURLProtocol.httpResponse(for: request, status: 200)
///     return (response, Data(#"{"ok":true}"#.utf8))
/// }
/// // ... inject `session` into the service under test ...
/// ```
final class MockURLProtocol: URLProtocol {

    // MARK: - Types

    /// Produces the stubbed result for an intercepted request. Throw to
    /// simulate a transport-level failure.
    typealias Handler = @Sendable (URLRequest) throws -> (HTTPURLResponse, Data)

    /// Mutable, lock-backed handler owned by one test instance. Use this when
    /// the service's session is created in `setUp` or a test intentionally
    /// changes its response midway through a request sequence.
    nonisolated final class HandlerStore: @unchecked Sendable {
        private let lock = NSLock()
        private var storedHandler: Handler?

        var handler: Handler? {
            get { lock.withLock { storedHandler } }
            set { lock.withLock { storedHandler = newValue } }
        }
    }

    // MARK: - Stub Configuration

    private nonisolated static let handlerLock = NSLock()
    nonisolated(unsafe) private static var sessionHandlers: [String: Handler] = [:]
    private nonisolated static let sessionHeader = "X-WolfWave-Mock-Session"

    /// Builds a session whose handler is immutable and isolated from every
    /// other mock session. Prefer this overload for async/concurrent tests.
    static func makeSession(handler: @escaping Handler) -> URLSession {
        let identifier = UUID().uuidString
        handlerLock.lock()
        sessionHandlers[identifier] = handler
        handlerLock.unlock()

        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        config.httpAdditionalHeaders = [sessionHeader: identifier]
        return URLSession(configuration: config)
    }

    /// Builds an isolated session backed by one test-owned mutable handler.
    /// The registry stores only the wrapper; changing this store cannot affect
    /// any other mock session running in parallel.
    static func makeSession(handlerStore: HandlerStore) -> URLSession {
        makeSession { request in
            guard let handler = handlerStore.handler else {
                throw URLError(.unsupportedURL)
            }
            return try handler(request)
        }
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
        let handler: Handler? = {
            Self.handlerLock.lock()
            defer { Self.handlerLock.unlock() }
            guard let identifier = request.value(forHTTPHeaderField: Self.sessionHeader) else {
                return nil
            }
            return Self.sessionHandlers[identifier]
        }()
        guard let handler else {
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
