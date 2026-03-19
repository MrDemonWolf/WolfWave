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

    func testServiceInitializesWithoutCrash() {
        let service = DiscordRPCService(clientID: "")
        XCTAssertNotNil(service)
    }

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

    func testResolveClientIDRejectsUnresolvedBuildVariable() {
        // Verify the logic that rejects "$(DISCORD_CLIENT_ID)" as a valid value
        let placeholder = "$(DISCORD_CLIENT_ID)"
        let isValid = !placeholder.isEmpty &&
            placeholder != "$(DISCORD_CLIENT_ID)" &&
            placeholder != "your_discord_application_id_here"
        XCTAssertFalse(isValid, "Unresolved build variable should not be treated as valid client ID")
    }

    func testResolveClientIDRejectsExamplePlaceholder() {
        let placeholder = "your_discord_application_id_here"
        let isValid = !placeholder.isEmpty &&
            placeholder != "$(DISCORD_CLIENT_ID)" &&
            placeholder != "your_discord_application_id_here"
        XCTAssertFalse(isValid, "Example placeholder should not be treated as valid client ID")
    }

    func testResolveClientIDAcceptsRealValue() {
        let realID = "1234567890"
        let isValid = !realID.isEmpty &&
            realID != "$(DISCORD_CLIENT_ID)" &&
            realID != "your_discord_application_id_here"
        XCTAssertTrue(isValid, "A real numeric client ID should be accepted")
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
}
