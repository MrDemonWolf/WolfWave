//
//  WebSocketServerServiceTests.swift
//  WolfWaveTests
//
//  Created by MrDemonWolf, Inc. on 2/13/26.
//

import XCTest
@testable import WolfWave

final class WebSocketServerServiceTests: XCTestCase {

    // MARK: - Server State

    func testServerStateRawValues() {
        XCTAssertEqual(WebSocketServerService.ServerState.stopped.rawValue, "stopped")
        XCTAssertEqual(WebSocketServerService.ServerState.starting.rawValue, "starting")
        XCTAssertEqual(WebSocketServerService.ServerState.listening.rawValue, "listening")
        XCTAssertEqual(WebSocketServerService.ServerState.error.rawValue, "error")
    }

    func testAllServerStatesAreUnique() {
        let states: [WebSocketServerService.ServerState] = [.stopped, .starting, .listening, .error]
        let rawValues = states.map { $0.rawValue }
        XCTAssertEqual(rawValues.count, Set(rawValues).count, "All server states should have unique raw values")
    }

    // MARK: - Port Validation

    func testDefaultPort() {
        XCTAssertEqual(AppConstants.WebSocketServer.defaultPort, 8765)
    }

    func testMinPort() {
        XCTAssertEqual(AppConstants.WebSocketServer.minPort, 1024)
    }

    func testMaxPort() {
        XCTAssertEqual(AppConstants.WebSocketServer.maxPort, 65535)
    }

    func testMinPortIsLessThanMaxPort() {
        XCTAssertLessThan(AppConstants.WebSocketServer.minPort, AppConstants.WebSocketServer.maxPort)
    }

    func testDefaultPortIsWithinBounds() {
        XCTAssertGreaterThanOrEqual(AppConstants.WebSocketServer.defaultPort, AppConstants.WebSocketServer.minPort)
        XCTAssertLessThanOrEqual(AppConstants.WebSocketServer.defaultPort, AppConstants.WebSocketServer.maxPort)
    }

    // MARK: - Constants

    func testProgressBroadcastInterval() {
        XCTAssertEqual(AppConstants.WebSocketServer.progressBroadcastInterval, 1.0)
    }

    func testRetryDelay() {
        XCTAssertGreaterThan(AppConstants.WebSocketServer.retryDelay, 0)
    }

    // MARK: - Service Initialization

    func testServiceInitializesWithDefaultPort() {
        let service = WebSocketServerService()
        XCTAssertEqual(service.state, .stopped)
        XCTAssertEqual(service.connectionCount, 0)
    }

    func testServiceInitializesWithCustomPort() {
        let service = WebSocketServerService(port: 9999)
        XCTAssertEqual(service.state, .stopped)
        XCTAssertEqual(service.connectionCount, 0)
    }

    // MARK: - Notification Names

    func testWebSocketServerChangedNotificationName() {
        XCTAssertEqual(AppConstants.Notifications.websocketServerChanged, "WebSocketServerChanged")
    }

    func testWebSocketServerStateChangedNotificationName() {
        XCTAssertEqual(AppConstants.Notifications.websocketServerStateChanged, "WebSocketServerStateChanged")
    }

    // MARK: - UserDefaults Keys

    func testWebSocketServerPortKey() {
        XCTAssertEqual(AppConstants.UserDefaults.websocketServerPort, "websocketServerPort")
    }

    func testWebSocketEnabledKeyExists() {
        XCTAssertEqual(AppConstants.UserDefaults.websocketEnabled, "websocketEnabled")
    }

    // MARK: - Dispatch Queue

    func testWebSocketServerQueueLabel() {
        XCTAssertEqual(AppConstants.DispatchQueues.websocketServer, "com.mrdemonwolf.wolfwave.websocketserver")
    }
}
