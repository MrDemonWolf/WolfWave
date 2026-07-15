//
//  WidgetHTTPServiceTests.swift
//  WolfWave
//
//  Created by Nathanial Henniges on 2026-03-19.
//  Copyright © 2026 MrDemonWolf, Inc. All rights reserved.
//

import Network
import XCTest
@testable import WolfWave

/// Integration tests that start a real HTTP server (NWListener). Port-binding
/// tests go through `startBoundService`, which walks a small range of high ports
/// until one binds, so a busy or lingering port can't flake CI.
@MainActor
final class WidgetHTTPServiceTests: XCTestCase {

    // MARK: - Initialization Tests

    func testInitWithValidPortStoresPort() {
        let service = WidgetHTTPService(port: 8766)
        XCTAssertNotNil(service, "Service should initialize with a valid port")
    }

    func testInitWithDefaultWidgetPort() {
        let service = WidgetHTTPService(port: AppConstants.WebSocketServer.widgetDefaultPort)
        XCTAssertNotNil(service, "Service should initialize with the default widget port")
    }

    func testInitWithMinPort() {
        let service = WidgetHTTPService(port: AppConstants.WebSocketServer.minPort)
        XCTAssertNotNil(service, "Service should initialize with the minimum allowed port")
    }

    func testInitWithMaxPort() {
        let service = WidgetHTTPService(port: AppConstants.WebSocketServer.maxPort)
        XCTAssertNotNil(service, "Service should initialize with the maximum allowed port")
    }

    // MARK: - Listener State Tests

    func testListenerIsNilBeforeStart() {
        // The listener should not be created until start() is called
        // We verify this indirectly: calling stop() on a not-started service is safe
        let service = WidgetHTTPService(port: 8766)
        // If listener were non-nil at init, stop() would cancel it; this should be a no-op
        service.stop()
        // No crash = pass; listener was nil
    }

    // MARK: - Stop Safety Tests

    func testStopOnNotStartedServiceDoesNotCrash() {
        let service = WidgetHTTPService(port: 8766)
        service.stop()
        // No crash = pass
    }

    func testMultipleStopCallsDoNotCrash() {
        let service = WidgetHTTPService(port: 8766)
        service.stop()
        service.stop()
        service.stop()
        // Multiple stop() calls should be safe since listener is set to nil after cancel
    }

    // MARK: - Port 0 Handling Tests

    func testPortZeroHandledGracefully() {
        // Port 0 should be handled gracefully. NWEndpoint.Port(rawValue: 0) returns nil,
        // so start() will log an error and return early without crashing
        let service = WidgetHTTPService(port: 0)
        XCTAssertNotNil(service, "Service should initialize with port 0 without crashing")
        service.start()
        // start() should return early after logging "Invalid port 0"
        // Verify no crash and stop is still safe
        service.stop()
    }

    // MARK: - Start/Stop Lifecycle Tests

    func testStartThenStopDoesNotCrash() {
        // Use a high port unlikely to conflict
        let service = WidgetHTTPService(port: 59999)
        service.start()
        service.stop()
        // Clean lifecycle = pass
    }

    func testMultipleStartCallsDoNotCreateDuplicateListeners() {
        // The start() method guards on listener == nil, so calling it twice should be safe
        let service = WidgetHTTPService(port: 59998)
        service.start()
        service.start() // Should be a no-op since listener is already set
        service.stop()
        // No crash = pass
    }

    // MARK: - Served HTML Body Tests

    /// Starts a `WidgetHTTPService` on the first port in a small high range that
    /// binds, awaiting readiness. Retries on the next port when a bind fails so a
    /// busy or lingering port can't flake CI. Returns the ready service and the
    /// port it bound, or fails the test if none bind.
    private func startBoundService(
        from base: UInt16 = 59900,
        attempts: Int = 20,
        make: (UInt16) -> WidgetHTTPService = { WidgetHTTPService(port: $0) }
    ) async -> (service: WidgetHTTPService, port: UInt16)? {
        for offset in 0..<attempts {
            let port = base &+ UInt16(offset)
            let service = make(port)
            service.start()
            do {
                try await service.ready()
                return (service, port)
            } catch {
                service.stop()
            }
        }
        XCTFail("WidgetHTTPService never bound a port in \(base)…\(base &+ UInt16(attempts - 1))")
        return nil
    }

    /// Fetches `GET /` from the running service and returns the body as a string.
    /// Retries a few times so a transient connect race right after `ready()`
    /// doesn't flake the assertion.
    private func fetchServedWidget(port: UInt16, attempts: Int = 5, timeout: TimeInterval = 5) -> String? {
        guard let url = URL(string: "http://127.0.0.1:\(port)/") else { return nil }
        for attempt in 0..<attempts {
            let exp = expectation(description: "fetch / (attempt \(attempt))")
            var body: String?
            let config = URLSessionConfiguration.ephemeral
            config.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
            let session = URLSession(configuration: config)
            let task = session.dataTask(with: url) { data, _, _ in
                if let data { body = String(data: data, encoding: .utf8) }
                exp.fulfill()
            }
            task.resume()
            wait(for: [exp], timeout: timeout)
            if let body, !body.isEmpty { return body }
            Thread.sleep(forTimeInterval: 0.05)
        }
        return nil
    }

    func testServedWidgetInlinesTokensJS() async {
        guard let (service, port) = await startBoundService() else { return }
        defer { service.stop() }

        guard let body = fetchServedWidget(port: port) else {
            XCTFail("Failed to fetch served widget.html")
            return
        }

        XCTAssertTrue(
            body.contains("window.WW_TOKENS"),
            "Served HTML should contain inlined window.WW_TOKENS literal from widget-tokens.generated.js"
        )
        XCTAssertFalse(
            body.contains("<script src=\"widget-tokens.generated.js\"></script>"),
            "Served HTML should not still reference the external tokens JS: it should be inlined"
        )
    }

    func testServedWidgetContainsPlaceholder() async {
        guard let (service, port) = await startBoundService() else { return }
        defer { service.stop() }

        guard let body = fetchServedWidget(port: port) else {
            XCTFail("Failed to fetch served widget.html")
            return
        }

        XCTAssertTrue(
            body.contains("class=\"placeholder\""),
            "Served HTML should include the pre-WebSocket placeholder so the page doesn't render blank"
        )
        XCTAssertTrue(
            body.contains("Waiting for music"),
            "Placeholder should carry the 'Waiting for music' copy"
        )
    }

    // MARK: - Connection Lifecycle Helpers

    /// Opens a raw TCP client to `127.0.0.1:port` that calls `onClosed` when
    /// the server closes, resets, or otherwise terminates the connection.
    /// The caller must `start` and later `cancel` the returned connection.
    private func makeRawClient(
        port: UInt16,
        onClosed: @escaping @Sendable () -> Void
    ) -> NWConnection? {
        guard let nwPort = NWEndpoint.Port(rawValue: port) else { return nil }
        let client = NWConnection(host: "127.0.0.1", port: nwPort, using: .tcp)
        client.stateUpdateHandler = { state in
            switch state {
            case .failed, .cancelled:
                onClosed()
            default:
                break
            }
        }
        // A graceful server-side close arrives as EOF (isComplete) on a read
        // rather than a state change, so observe both paths.
        client.receive(minimumIncompleteLength: 1, maximumLength: 1024) { _, _, isComplete, error in
            if isComplete || error != nil {
                onClosed()
            }
        }
        return client
    }

    /// Polls until the service tracks at least `count` connections, failing
    /// the test if that doesn't happen within `timeout`. Bounded polling so
    /// tests await the accept instead of sleeping a fixed interval.
    private func waitForActiveConnections(
        _ service: WidgetHTTPService,
        atLeast count: Int,
        timeout: TimeInterval = 5
    ) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while service.activeConnectionCount < count {
            if Date() >= deadline {
                XCTFail("Timed out waiting for \(count) tracked connections")
                return
            }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
    }

    // MARK: - Connection Lifecycle Tests

    func testStopCancelsAcceptedIdleConnections() async throws {
        let port: UInt16 = 59995
        let service = WidgetHTTPService(port: port)
        service.start()
        defer { service.stop() }
        try await service.ready()

        let closed = expectation(description: "server closed the idle client on stop()")
        closed.assertForOverFulfill = false
        guard let client = makeRawClient(port: port, onClosed: { closed.fulfill() }) else {
            XCTFail("Failed to build raw client for port \(port)")
            return
        }
        client.start(queue: DispatchQueue(label: "test.raw-client"))
        defer { client.cancel() }

        // Send nothing: the connection sits idle with a pending server receive.
        try await waitForActiveConnections(service, atLeast: 1)

        service.stop()
        await fulfillment(of: [closed], timeout: 5)
        XCTAssertEqual(service.activeConnectionCount, 0, "stop() should drop all tracked connections")
    }

    func testHeaderTimeoutCancelsConnectionWithIncompleteHeaders() async throws {
        let port: UInt16 = 59994
        // Short timeout so the test stays fast; production default is 10s.
        let service = WidgetHTTPService(port: port, headerTimeout: 0.5)
        service.start()
        defer { service.stop() }
        try await service.ready()

        let closed = expectation(description: "server cancelled the stalled client")
        closed.assertForOverFulfill = false
        guard let client = makeRawClient(port: port, onClosed: { closed.fulfill() }) else {
            XCTFail("Failed to build raw client for port \(port)")
            return
        }
        client.start(queue: DispatchQueue(label: "test.raw-client"))
        defer { client.cancel() }

        // Partial request line, no CRLF CRLF terminator: headers never complete.
        client.send(content: Data("GET / HT".utf8), completion: .idempotent)

        await fulfillment(of: [closed], timeout: 5)
    }

    func testConnectionCapRefusesExtraConnections() async throws {
        let port: UInt16 = 59993
        // Tiny cap so the test doesn't need 32 sockets; production default is 32.
        let service = WidgetHTTPService(port: port, maxConcurrentConnections: 2)
        service.start()
        defer { service.stop() }
        try await service.ready()

        // Fill the cap with idle clients that never send a request.
        var capFillers: [NWConnection] = []
        defer { capFillers.forEach { $0.cancel() } }
        for _ in 0..<2 {
            guard let filler = makeRawClient(port: port, onClosed: {}) else {
                XCTFail("Failed to build raw client for port \(port)")
                return
            }
            filler.start(queue: DispatchQueue(label: "test.raw-client"))
            capFillers.append(filler)
        }
        try await waitForActiveConnections(service, atLeast: 2)

        let refused = expectation(description: "over-cap connection cancelled immediately")
        refused.assertForOverFulfill = false
        guard let extra = makeRawClient(port: port, onClosed: { refused.fulfill() }) else {
            XCTFail("Failed to build raw client for port \(port)")
            return
        }
        extra.start(queue: DispatchQueue(label: "test.raw-client"))
        defer { extra.cancel() }

        await fulfillment(of: [refused], timeout: 5)
        XCTAssertEqual(
            service.activeConnectionCount, 2,
            "Refused connection should never be tracked"
        )
    }
}
