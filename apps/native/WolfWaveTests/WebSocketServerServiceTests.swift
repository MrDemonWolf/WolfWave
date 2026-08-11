//
//  WebSocketServerServiceTests.swift
//  WolfWave
//
//  Created by Nathanial Henniges on 2026-02-20.
//  Copyright © 2026 MrDemonWolf, Inc. All rights reserved.
//

import XCTest
@testable import WolfWave

/// Unit tests for WebSocket server state and admission policies. Network-bound
/// lifecycle and frame delivery stay in `WebSocketServerIntegrationTests`.
@MainActor
final class WebSocketServerServiceTests: XCTestCase {

    func testServiceInitializesWithDefaultPort() {
        let service = WebSocketServerService()
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

    // MARK: - State Policy Tests

    func testProgressTimerDoesNotRunWithoutConnectedClients() async {
        let service = WebSocketServerService(port: 0)

        await service.updateNowPlaying(
            track: "Quiet Track",
            artist: "Test Artist",
            album: "Test Album",
            duration: 180,
            elapsed: 10
        )

        let active = await service.isProgressTimerActive
        XCTAssertFalse(active, "Playback state caching must not create an idle one-second task")
    }

    func testOverlayVisibilityToggleUpdatesHealthSnapshot() async {
        let service = WebSocketServerService(port: 0)
        XCTAssertTrue(service.overlayVisible)

        let hidden = await service.toggleOverlayVisibility()
        XCTAssertFalse(hidden)
        XCTAssertFalse(service.overlayVisible)

        let shown = await service.toggleOverlayVisibility()
        XCTAssertTrue(shown)
        XCTAssertTrue(service.overlayVisible)
    }

    func testArtworkResultIsScopedToCurrentTrackIdentity() async {
        let service = WebSocketServerService(port: 0)

        await service.updateNowPlaying(
            track: "Track A",
            artist: "Artist A",
            album: "Album A",
            duration: 180,
            elapsed: 10,
            artworkURL: "https://example.com/a.jpg"
        )
        await service.updateNowPlaying(
            track: "Track B",
            artist: "Artist B",
            album: "Album B",
            duration: 200,
            elapsed: 0,
            artworkURL: nil
        )

        let cleared = await service.artworkState
        XCTAssertNil(cleared.url, "A new track must not inherit the previous track artwork")

        let acceptedOld = await service.updateArtworkURL(
            "https://example.com/late-a.jpg",
            track: "Track A",
            artist: "Artist A"
        )
        XCTAssertFalse(acceptedOld, "An out-of-order artwork result must be ignored")

        let acceptedCurrent = await service.updateArtworkURL(
            "https://example.com/b.jpg",
            track: "Track B",
            artist: "Artist B"
        )
        XCTAssertTrue(acceptedCurrent)
        let current = await service.artworkState
        XCTAssertEqual(current.url, "https://example.com/b.jpg")

        let acceptedDuplicate = await service.updateArtworkURL(
            "https://example.com/b.jpg",
            track: "Track B",
            artist: "Artist B"
        )
        XCTAssertFalse(acceptedDuplicate, "An identical artwork result must be a no-op")
    }

}
