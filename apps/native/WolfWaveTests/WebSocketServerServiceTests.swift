//
//  WebSocketServerServiceTests.swift
//  WolfWave
//
//  Created by Nathanial Henniges on 2026-02-20.
//  Copyright © 2026 MrDemonWolf, Inc. All rights reserved.
//

import XCTest
@testable import WolfWave

/// Smoke tests for `WebSocketServerService` construction.
///
/// The port bounds, notification names, UserDefaults keys, queue label, and
/// `ServerState` raw values are covered once in `AppConstantsTests`. Re-asserting
/// those literals here was change-detector duplication (it restates the source and
/// breaks on any intentional edit without catching a bug), so this file keeps only
/// the init behavior that exercises the type itself.
@MainActor
final class WebSocketServerServiceTests: XCTestCase {

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

    func testProgressTimerPolicySkipsZeroDurationWithConnectedClient() {
        XCTAssertFalse(WebSocketServerService.shouldRunProgressTimer(
            isEnabled: true,
            isOverlayVisible: true,
            isPlaying: true,
            duration: 0,
            connectionCount: 1
        ))
        XCTAssertTrue(WebSocketServerService.shouldRunProgressTimer(
            isEnabled: true,
            isOverlayVisible: true,
            isPlaying: true,
            duration: 180,
            connectionCount: 1
        ))
    }

    func testInboundMessageLimitIsExplicitAndSmall() {
        XCTAssertGreaterThan(WebSocketServerService.maximumInboundMessageSize, 0)
        XCTAssertLessThanOrEqual(
            WebSocketServerService.maximumInboundMessageSize,
            64 * 1024
        )
    }

    func testConnectionAdmissionCapsPendingAndTotalPeers() {
        XCTAssertTrue(WebSocketServerService.shouldAcceptNewConnection(
            activeCount: 0,
            pendingCount: 0
        ))
        XCTAssertFalse(WebSocketServerService.shouldAcceptNewConnection(
            activeCount: 0,
            pendingCount: WebSocketServerService.maximumPendingConnectionCount
        ))
        XCTAssertFalse(WebSocketServerService.shouldAcceptNewConnection(
            activeCount: WebSocketServerService.maximumConnectionCount,
            pendingCount: 0
        ))
        XCTAssertTrue(WebSocketServerService.shouldAcceptNewConnection(
            activeCount: WebSocketServerService.maximumConnectionCount - 1,
            pendingCount: 0
        ))
        XCTAssertFalse(WebSocketServerService.shouldAcceptNewConnection(
            activeCount: WebSocketServerService.maximumConnectionCount - 1,
            pendingCount: 1
        ))
        XCTAssertFalse(WebSocketServerService.shouldAcceptNewConnection(
            activeCount: -1,
            pendingCount: 0
        ))
    }
}
