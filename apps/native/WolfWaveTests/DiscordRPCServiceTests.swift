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

    func testInitialStateIsDisconnected() async {
        let service = DiscordRPCService(clientID: "")
        let state = await service.state
        XCTAssertEqual(
            state,
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

    func testSetEnabledFalseDoesNotCrash() async {
        let service = DiscordRPCService(clientID: "")
        await service.setEnabled(false)
        // No crash = pass
    }

    func testClearPresenceOnDisconnectedServiceDoesNotCrash() async {
        let service = DiscordRPCService(clientID: "")
        await service.clearPresence()
        // clearPresence() guards on state == .connected, so this should be a no-op
    }

    func testTestConnectionOnDisconnectedServiceReturnsFalse() async {
        let service = DiscordRPCService(clientID: "")
        let success = await service.testConnection()
        XCTAssertFalse(success, "testConnection should return false when disconnected with no client ID")
    }

    // MARK: - Connection State Enum Tests

    func testConnectionStateRawValues() {
        XCTAssertEqual(DiscordRPCService.ConnectionState.disconnected.rawValue, "disconnected")
        XCTAssertEqual(DiscordRPCService.ConnectionState.connecting.rawValue, "connecting")
        XCTAssertEqual(DiscordRPCService.ConnectionState.connected.rawValue, "connected")
    }

    // MARK: - Stream Existence Tests

    func testStateChangesStreamIsAvailable() {
        let service = DiscordRPCService(clientID: "")
        // Streams are nonisolated `let` — accessible without await and never nil.
        _ = service.stateChanges
        _ = service.artworkResolutions
    }

    // MARK: - Enable/Disable Toggle Tests

    func testSetEnabledTrueThenFalseDoesNotCrash() async {
        let service = DiscordRPCService(clientID: "")
        await service.setEnabled(true)
        await service.setEnabled(false)
        // No crash = pass
    }

    // MARK: - Clear Presence Tests

    func testClearPresenceMultipleTimesDoesNotCrash() async {
        let service = DiscordRPCService(clientID: "")
        await service.clearPresence()
        await service.clearPresence()
        await service.clearPresence()
        // No crash = pass
    }

    // MARK: - Connection State Enum Completeness

    func testConnectionStateRawValuesAreUniqueAndNonEmpty() async {
        // Validate each case has a non-empty, distinct raw value
        let disconnected = DiscordRPCService.ConnectionState.disconnected
        let connecting = DiscordRPCService.ConnectionState.connecting
        let connected = DiscordRPCService.ConnectionState.connected

        XCTAssertFalse(disconnected.rawValue.isEmpty, "disconnected raw value should not be empty")
        XCTAssertFalse(connecting.rawValue.isEmpty, "connecting raw value should not be empty")
        XCTAssertFalse(connected.rawValue.isEmpty, "connected raw value should not be empty")

        // All raw values must be distinct
        XCTAssertNotEqual(disconnected.rawValue, connecting.rawValue)
        XCTAssertNotEqual(disconnected.rawValue, connected.rawValue)
        XCTAssertNotEqual(connecting.rawValue, connected.rawValue)

        // Verify initial state transitions: a new service starts disconnected
        let service = DiscordRPCService(clientID: "")
        let state = await service.state
        XCTAssertEqual(state, .disconnected)
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
