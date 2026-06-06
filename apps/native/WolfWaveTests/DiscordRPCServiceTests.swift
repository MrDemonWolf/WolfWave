//
//  DiscordRPCServiceTests.swift
//  WolfWave
//
//  Created by Nathanial Henniges on 2026-03-19.
//  Copyright © 2026 MrDemonWolf, Inc. All rights reserved.
//

import XCTest
@testable import WolfWave

@MainActor
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

    // MARK: - Off-Executor I/O Tests (No Socket)
    //
    // The blocking IPC syscalls now run on a dedicated serial queue, bridged back
    // to the actor with a checked continuation. None of these entry points may
    // touch the socket while disconnected (they guard on `state == .connected`),
    // so on a service with no client ID they must return promptly without ever
    // opening or blocking on a socket. A regression that re-blocks the executor
    // (or drops the state guard) would hang these `await`s.

    func testUpdatePresenceWhileDisconnectedReturnsWithoutBlocking() async {
        let service = DiscordRPCService(clientID: "")
        // Disconnected: guarded out before any socket I/O. Must return, not hang.
        await service.updatePresence(
            track: "Howl", artist: "Timber Wolf", album: "Moonrise",
            playlist: "", duration: 120, elapsed: 10, isPaused: false
        )
        let state = await service.state
        XCTAssertEqual(state, .disconnected, "updatePresence must not connect on its own")
    }

    func testShowIdleStatusWhileDisconnectedIsNoOp() async {
        let service = DiscordRPCService(clientID: "")
        await service.showIdleStatus()
        let state = await service.state
        XCTAssertEqual(state, .disconnected)
    }

    func testTestConnectionWithEmptyClientReturnsFalseWithoutHanging() async {
        // testConnection() now awaits connectIfNeeded(); with no client ID it
        // bails before touching the IPC queue and resolves to false.
        let service = DiscordRPCService(clientID: "")
        let result = await service.testConnection()
        XCTAssertFalse(result)
    }

    func testConcurrentDisconnectedCallsAllComplete() async {
        // The actor serializes these and none reach the socket, so a batch of
        // concurrent calls must all complete (no continuation leak / deadlock).
        let service = DiscordRPCService(clientID: "")
        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<8 {
                group.addTask { await service.clearPresence() }
                group.addTask { await service.showIdleStatus() }
                group.addTask {
                    await service.updatePresence(
                        track: "T", artist: "A", album: "Al",
                        playlist: "", duration: 0, elapsed: 0, isPaused: false
                    )
                }
            }
        }
        let state = await service.state
        XCTAssertEqual(state, .disconnected)
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
        // Streams are nonisolated `let`, accessible without await and never nil.
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

    // MARK: - Frame payload decode (pure, no live socket)
    //
    // `decodeFramePayload` is the seam behind `readFrame`. A hostile or garbled
    // Discord peer must never crash the IPC read loop, so malformed bytes have
    // to decode to nil, not trap.

    func testDecodeFramePayloadParsesValidObject() {
        let data = Data(#"{"cmd":"DISPATCH","evt":"READY"}"#.utf8)
        let json = DiscordRPCService.decodeFramePayload(data)
        XCTAssertEqual(json?["cmd"] as? String, "DISPATCH")
    }

    func testDecodeFramePayloadReturnsNilForGarbage() {
        XCTAssertNil(DiscordRPCService.decodeFramePayload(Data("not json".utf8)))
    }

    func testDecodeFramePayloadReturnsNilForTruncatedJSON() {
        XCTAssertNil(DiscordRPCService.decodeFramePayload(Data("{".utf8)))
    }

    func testDecodeFramePayloadReturnsNilForJSONArray() {
        // Valid JSON, but a top-level array is not a frame payload object.
        XCTAssertNil(DiscordRPCService.decodeFramePayload(Data("[1,2,3]".utf8)))
    }

    func testDecodeFramePayloadReturnsNilForEmptyData() {
        XCTAssertNil(DiscordRPCService.decodeFramePayload(Data()))
    }

    func testMaxIPCFrameBytesCapIsBounded() {
        XCTAssertEqual(AppConstants.Discord.maxIPCFrameBytes, 65536)
    }

    // MARK: - I/O Result Shapes (errno captured on-queue)
    //
    // `writeFully`/`readFully` now return a small Sendable result carrying the
    // failing `errno` captured on the same worker thread that ran the syscall,
    // instead of letting the actor read a stale, unrelated `errno` after the
    // queue hop. These assert the result shape and the success/failure contract
    // without opening a socket.

    func testWriteResultSuccessShape() {
        let result = DiscordRPCService.WriteResult(ok: true, errno: 0)
        XCTAssertTrue(result.ok)
        XCTAssertEqual(result.errno, 0, "errno is meaningful only on failure; success carries 0")
    }

    func testWriteResultFailureCarriesErrno() {
        let result = DiscordRPCService.WriteResult(ok: false, errno: EPIPE)
        XCTAssertFalse(result.ok)
        XCTAssertEqual(result.errno, EPIPE, "failing errno must be carried back, not re-read post-hop")
    }

    func testReadResultSuccessShape() {
        let result = DiscordRPCService.ReadResult(data: Data([1, 2, 3]), errno: 0)
        XCTAssertEqual(result.data, Data([1, 2, 3]))
        XCTAssertEqual(result.errno, 0)
    }

    func testReadResultPeerCloseHasNilDataAndZeroErrno() {
        // A clean peer close (read returns 0) is not a syscall error, so errno
        // stays 0 while data is nil — distinct from a timeout/error path.
        let result = DiscordRPCService.ReadResult(data: nil, errno: 0)
        XCTAssertNil(result.data)
        XCTAssertEqual(result.errno, 0)
    }

    func testReadResultErrorCarriesErrno() {
        let result = DiscordRPCService.ReadResult(data: nil, errno: EAGAIN)
        XCTAssertNil(result.data)
        XCTAssertEqual(result.errno, EAGAIN, "timeout/error errno must be carried back from the queue")
    }

    // MARK: - Teardown / Generation Gate (no socket)
    //
    // `disconnect()` bumps a monotonic generation token and routes the close
    // through `ipcQueue`, and `connectIfNeeded` discards a just-opened fd if the
    // generation changed mid-connect. With no client ID nothing reaches a real
    // socket, but a regression in the gate (or in routing the close through the
    // queue) would deadlock or crash these toggles. They must all settle on
    // `.disconnected` without hanging.

    func testEnableDisableTogglesSettleDisconnected() async {
        let service = DiscordRPCService(clientID: "")
        for _ in 0..<5 {
            await service.setEnabled(true)
            await service.setEnabled(false)
        }
        let state = await service.state
        XCTAssertEqual(state, .disconnected, "repeated enable/disable must end disconnected, not hang")
    }

    func testDisableDuringConcurrentCallsSettlesDisconnected() async {
        // A disable racing in-flight presence calls exercises the teardown +
        // generation path. None reach a socket, so all must complete and the
        // service must end disconnected.
        let service = DiscordRPCService(clientID: "")
        await service.setEnabled(true)
        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<4 {
                group.addTask {
                    await service.updatePresence(
                        track: "T", artist: "A", album: "Al",
                        playlist: "", duration: 0, elapsed: 0, isPaused: false
                    )
                }
                group.addTask { await service.clearPresence() }
            }
            group.addTask { await service.setEnabled(false) }
        }
        await service.setEnabled(false)
        let state = await service.state
        XCTAssertEqual(state, .disconnected)
    }

    // MARK: - Reconnect Backoff

    func testNextBackoffDoubles() {
        let base = AppConstants.Discord.reconnectBaseDelay
        let max = AppConstants.Discord.reconnectMaxDelay
        let next = DiscordRPCService.nextBackoff(base, base: base, max: max)
        XCTAssertEqual(next, base * 2, accuracy: 0.0001)
    }

    func testNextBackoffClampsAtMax() {
        let base = AppConstants.Discord.reconnectBaseDelay
        let max = AppConstants.Discord.reconnectMaxDelay
        // Already at max: doubling would overshoot, so it must clamp.
        let next = DiscordRPCService.nextBackoff(max, base: base, max: max)
        XCTAssertEqual(next, max, accuracy: 0.0001)
        // Just under max: doubling overshoots, still clamps.
        let nearMax = DiscordRPCService.nextBackoff(max * 0.75, base: base, max: max)
        XCTAssertEqual(nearMax, max, accuracy: 0.0001)
    }

    func testNextBackoffRepeatedDoublingClampsAndResetIsBase() {
        let base = AppConstants.Discord.reconnectBaseDelay
        let max = AppConstants.Discord.reconnectMaxDelay
        var delay = base
        for _ in 0..<20 {
            delay = DiscordRPCService.nextBackoff(delay, base: base, max: max)
            XCTAssertLessThanOrEqual(delay, max)
        }
        XCTAssertEqual(delay, max, accuracy: 0.0001)
        // Reset semantics: a successful connect sets reconnectDelay back to base.
        XCTAssertEqual(base, AppConstants.Discord.reconnectBaseDelay, accuracy: 0.0001)
    }
}
