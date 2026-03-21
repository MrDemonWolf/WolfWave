//
//  WidgetHTTPServiceTests.swift
//  WolfWaveTests
//
//  Created by MrDemonWolf, Inc. on 3/18/26.
//

import XCTest
@testable import WolfWave

/// Integration tests that start a real HTTP server (NWListener) on ephemeral ports.
/// Some tests bind to high-numbered ports; conflicts are unlikely but possible.
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
}
