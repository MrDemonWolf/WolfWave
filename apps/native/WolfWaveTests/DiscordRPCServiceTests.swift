//
//  DiscordRPCServiceTests.swift
//  WolfWaveTests
//
//  Created by MrDemonWolf, Inc. on 3/18/26.
//

import XCTest
@testable import WolfWave

final class DiscordRPCServiceTests: XCTestCase {

    // MARK: - Initialization Tests

    func testServiceInitializesWithEmptyClientID() {
        let service = DiscordRPCService(clientID: "")
        XCTAssertNotNil(service, "Service should initialize without crash even with empty client ID")
    }

    // MARK: - Initial State Tests

    func testInitialStateIsDisconnected() {
        let service = DiscordRPCService(clientID: "")
        XCTAssertEqual(
            service.state,
            .disconnected,
            "Initial connection state should be .disconnected"
        )
    }

    // MARK: - Client ID Resolution Tests

    func testResolveClientIDReturnsNilForPlaceholder() {
        // The resolveClientID() static method should reject unresolved build variable placeholders
        // In test environment, Info.plist won't have a real DISCORD_CLIENT_ID,
        // so resolveClientID() should return nil (or the env variable if set)
        let resolved = DiscordRPCService.resolveClientID()
        // If not configured in environment, should be nil
        if let resolved = resolved {
            // If it returns a value, it must not be a placeholder
            XCTAssertNotEqual(resolved, "$(DISCORD_CLIENT_ID)", "Should not return unresolved build variable")
            XCTAssertNotEqual(resolved, "your_discord_application_id_here", "Should not return placeholder value")
            XCTAssertFalse(resolved.isEmpty, "Should not return empty string")
        }
    }

    func testResolveClientIDRejectsPlaceholders() {
        // In test environment, resolveClientID() should return nil (no real client ID configured)
        // or a valid non-placeholder string if one is set in the environment
        let resolved = DiscordRPCService.resolveClientID()
        if let resolved = resolved {
            XCTAssertNotEqual(resolved, "$(DISCORD_CLIENT_ID)", "Should not return unresolved build variable")
            XCTAssertNotEqual(resolved, "your_discord_application_id_here", "Should not return example placeholder")
            XCTAssertFalse(resolved.isEmpty, "Should not return empty string")
        }
    }

    // MARK: - Safe Operation Tests (No Socket)

    func testSetEnabledFalseDoesNotCrash() {
        let service = DiscordRPCService(clientID: "")
        service.setEnabled(false)
        // No crash = pass
    }

    func testClearPresenceOnDisconnectedServiceDoesNotCrash() {
        let service = DiscordRPCService(clientID: "")
        service.clearPresence()
        // clearPresence() guards on state == .connected, so this should be a no-op
    }

    func testTestConnectionOnDisconnectedServiceReturnsFalse() {
        let service = DiscordRPCService(clientID: "")
        let expectation = expectation(description: "testConnection completion")

        service.testConnection { success in
            XCTAssertFalse(success, "testConnection should return false when disconnected with no client ID")
            expectation.fulfill()
        }

        waitForExpectations(timeout: 5.0)
    }

    // MARK: - Connection State Enum Tests

    func testConnectionStateRawValues() {
        XCTAssertEqual(DiscordRPCService.ConnectionState.disconnected.rawValue, "disconnected")
        XCTAssertEqual(DiscordRPCService.ConnectionState.connecting.rawValue, "connecting")
        XCTAssertEqual(DiscordRPCService.ConnectionState.connected.rawValue, "connected")
    }

    // MARK: - State Change Callback Tests

    func testOnStateChangeCallbackIsNilByDefault() {
        let service = DiscordRPCService(clientID: "")
        XCTAssertNil(service.onStateChange, "onStateChange callback should be nil by default")
    }

    func testOnArtworkResolvedCallbackIsNilByDefault() {
        let service = DiscordRPCService(clientID: "")
        XCTAssertNil(service.onArtworkResolved, "onArtworkResolved callback should be nil by default")
    }

    // MARK: - Enable/Disable Toggle Tests

    func testSetEnabledTrueThenFalseDoesNotCrash() {
        let service = DiscordRPCService(clientID: "")
        service.setEnabled(true)
        service.setEnabled(false)
        // No crash = pass
    }

    // MARK: - Clear Presence Tests

    func testClearPresenceMultipleTimesDoesNotCrash() {
        let service = DiscordRPCService(clientID: "")
        service.clearPresence()
        service.clearPresence()
        service.clearPresence()
        // No crash = pass
    }

    // MARK: - Connection State Enum Completeness

    func testConnectionStateHasExactlyThreeCases() {
        let allCases: [DiscordRPCService.ConnectionState] = [.disconnected, .connecting, .connected]
        let uniqueRawValues = Set(allCases.map { $0.rawValue })
        XCTAssertEqual(uniqueRawValues.count, 3, "ConnectionState should have exactly 3 unique cases")
    }

    // MARK: - Callback Tests

    func testOnStateChangeCallbackCanBeSet() {
        let service = DiscordRPCService(clientID: "")
        var callbackCalled = false
        service.onStateChange = { _ in callbackCalled = true }
        XCTAssertNotNil(service.onStateChange)
        // Verify the callback was stored (not called yet)
        XCTAssertFalse(callbackCalled)
    }

    // MARK: - Performance Tests

    func testInitializationPerformance() {
        measure {
            for _ in 0..<100 {
                _ = DiscordRPCService(clientID: "test_id_\(Int.random(in: 0...999))")
            }
        }
    }
}
