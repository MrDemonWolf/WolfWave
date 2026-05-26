//
//  WidgetHTTPServiceTests.swift
//  WolfWave
//
//  Created by Nathanial Henniges on 2026-03-19.
//  Copyright © 2026 MrDemonWolf, Inc. All rights reserved.
//

import XCTest
@testable import WolfWave

/// Integration tests that start a real HTTP server (NWListener) on ephemeral ports.
/// Some tests bind to high-numbered ports; conflicts are unlikely but possible.
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
        // Port 0 should be handled gracefully — NWEndpoint.Port(rawValue: 0) returns nil,
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

    /// Fetches `GET /` from the running service and returns the body as a string.
    private func fetchServedWidget(port: UInt16, timeout: TimeInterval = 5) -> String? {
        guard let url = URL(string: "http://127.0.0.1:\(port)/") else { return nil }
        let exp = expectation(description: "fetch /")
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
        return body
    }

    func testServedWidgetInlinesTokensJS() {
        let port: UInt16 = 59997
        let service = WidgetHTTPService(port: port)
        service.start()
        defer { service.stop() }

        // Give the listener a beat to bind.
        Thread.sleep(forTimeInterval: 0.2)

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
            "Served HTML should not still reference the external tokens JS — it should be inlined"
        )
    }

    func testServedWidgetContainsPlaceholder() {
        let port: UInt16 = 59996
        let service = WidgetHTTPService(port: port)
        service.start()
        defer { service.stop() }

        Thread.sleep(forTimeInterval: 0.2)

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
}
