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

/// Focused request-policy checks plus integration tests that cross the real
/// NWListener boundary. Port-binding tests use `startBoundService` to avoid
/// coupling the suite to a single machine-global port.
@MainActor
final class WidgetHTTPServiceTests: XCTestCase {

    // MARK: - Request Policy Tests

    func testTokenInjectionRequiresLoopbackPeerAndLiteralLocalHost() {
        XCTAssertTrue(
            WidgetHTTPService.shouldInjectToken(
                loopbackPeer: true,
                hostHeader: "localhost:8766"
            )
        )
        XCTAssertTrue(
            WidgetHTTPService.shouldInjectToken(
                loopbackPeer: true,
                hostHeader: "127.42.0.1:8766"
            )
        )
        XCTAssertTrue(
            WidgetHTTPService.shouldInjectToken(
                loopbackPeer: true,
                hostHeader: "[::1]:8766"
            )
        )
        XCTAssertFalse(
            WidgetHTTPService.shouldInjectToken(
                loopbackPeer: true,
                hostHeader: "attacker.example:8766"
            ),
            "A hostile DNS name must not receive the loopback credential"
        )
        XCTAssertFalse(
            WidgetHTTPService.shouldInjectToken(
                loopbackPeer: false,
                hostHeader: "localhost:8766"
            ),
            "A LAN peer cannot opt into token injection with a forged Host"
        )
        XCTAssertFalse(
            WidgetHTTPService.shouldInjectToken(
                loopbackPeer: true,
                hostHeader: "127.0.0.1.attacker.example"
            )
        )
        XCTAssertFalse(
            WidgetHTTPService.shouldInjectToken(loopbackPeer: true, hostHeader: nil),
            "HTTP/1.1 requests without Host must never receive credentials"
        )
    }

    func testHeaderValueDoesNotScanPastEndOfHeaders() {
        let request = "GET / HTTP/1.1\r\nUser-Agent: WolfWaveTests\r\n\r\nHost: localhost:8766\r\n"

        XCTAssertNil(
            WidgetHTTPService.headerValue(named: "host", in: request),
            "Header-like body content must not authorize token injection"
        )
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

    /// Fetches `GET /` from a service that has already reported readiness.
    private func fetchServedWidgetResponse(
        port: UInt16,
        timeout: TimeInterval = 5
    ) async throws -> (body: String, response: HTTPURLResponse) {
        let url = try XCTUnwrap(URL(string: "http://127.0.0.1:\(port)/"))
        let configuration = URLSessionConfiguration.ephemeral
        configuration.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        configuration.timeoutIntervalForRequest = timeout
        configuration.timeoutIntervalForResource = timeout
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }

        let (data, response) = try await session.data(for: URLRequest(url: url))
        let httpResponse = try XCTUnwrap(response as? HTTPURLResponse)
        let body = try XCTUnwrap(String(data: data, encoding: .utf8))
        return (body, httpResponse)
    }

    func testPublicWidgetResponseContainsShippedAssetAndPrivacyPolicy() async throws {
        guard let (service, port) = await startBoundService() else { return }
        defer { service.stop() }

        let result = try await fetchServedWidgetResponse(port: port)

        XCTAssertTrue(
            result.body.contains("window.WW_TOKENS"),
            "The built widget should contain the inlined window.WW_TOKENS literal"
        )
        XCTAssertFalse(
            result.body.contains("<script src=\"widget-tokens.generated.js\"></script>"),
            "The build should remove the external tokens script before the native server reads the asset"
        )
        XCTAssertTrue(
            result.body.contains("class=\"placeholder\""),
            "Served HTML should include the pre-WebSocket placeholder so the page doesn't render blank"
        )
        XCTAssertTrue(
            result.body.contains("Waiting for music"),
            "Placeholder should carry the 'Waiting for music' copy"
        )
        XCTAssertEqual(result.response.value(forHTTPHeaderField: "Referrer-Policy"), "no-referrer")
        XCTAssertTrue(result.body.contains("<meta name=\"referrer\" content=\"no-referrer\">"))
    }

    func testLoopbackWidgetInjectsReadOnlyOverlayCredential() async throws {
        let overlayToken = String(repeating: "a", count: 64)
        guard let (service, port) = await startBoundService(
            from: 59880,
            make: { WidgetHTTPService(port: $0, overlayToken: overlayToken) }
        ) else { return }
        defer { service.stop() }

        let result = try await fetchServedWidgetResponse(port: port)

        XCTAssertTrue(result.body.contains(overlayToken))
        XCTAssertTrue(result.body.contains("wolfwave.overlay."))
        XCTAssertFalse(result.body.contains("wolfwave.control."))
        XCTAssertEqual(
            result.response.value(forHTTPHeaderField: "Cache-Control"),
            "no-store"
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
        // Walk for a free port instead of pinning one. A hardcoded port fails with
        // `listenerFailed` whenever the previous run's socket is still in TIME_WAIT
        // or the real app is running, which made this suite flake on every rerun.
        guard let (service, port) = await startBoundService(from: 38995) else { return }
        defer { service.stop() }

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
        // Short timeout so the test stays fast; production default is 10s.
        guard let (service, port) = await startBoundService(
            from: 38994,
            make: { WidgetHTTPService(port: $0, headerTimeout: 0.5) }
        ) else { return }
        defer { service.stop() }

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
        // Tiny cap so the test doesn't need 32 sockets; production default is 32.
        // Port-walks for the same reason as `testStopCancelsAcceptedIdleConnections`.
        guard let (service, port) = await startBoundService(
            from: 38993,
            make: { WidgetHTTPService(port: $0, maxConcurrentConnections: 2) }
        ) else { return }
        defer { service.stop() }

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
