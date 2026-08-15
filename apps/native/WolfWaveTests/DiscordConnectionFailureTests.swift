//
//  DiscordConnectionFailureTests.swift
//  WolfWave
//
//  Created by Nathanial Henniges on 2026-08-14.
//  Copyright © 2026 MrDemonWolf, Inc. All rights reserved.
//

import XCTest
@testable import WolfWave

/// Covers the failure reason behind a Discord disconnect.
///
/// `DiscordRPCService` had no error state at all: every failure — a rejected
/// handshake, a sandbox-blocked socket, an unresolvable temp directory — was
/// `Log.error` only, and the pane asserted "Discord not running" for all of
/// them. That string is often plainly false, since a handshake rejection
/// happens with Discord open on screen.
@MainActor
final class DiscordConnectionFailureTests: XCTestCase {

    // MARK: - Snapshot Mirroring

    func testFailureStartsClear() {
        let service = DiscordRPCService()
        XCTAssertEqual(service.failureSnapshot, .none)
    }

    /// The UI reads this synchronously off the actor, so the mirror has to
    /// track every assignment.
    func testFailureSnapshotMirrorsAssignment() async {
        let service = DiscordRPCService()
        await service.recordFailure(.handshakeRejected)
        XCTAssertEqual(service.failureSnapshot, .handshakeRejected)

        await service.recordFailure(.socketUnavailable)
        XCTAssertEqual(service.failureSnapshot, .socketUnavailable)
    }

    /// A stale reason must not outlive the problem it described.
    func testConnectingSuccessfullyClearsTheReason() async {
        let service = DiscordRPCService()
        await service.recordFailure(.notRunning)
        XCTAssertEqual(service.failureSnapshot, .notRunning)

        await service.recordFailure(.none)
        XCTAssertEqual(service.failureSnapshot, .none)
    }

    // MARK: - Vocabulary

    /// Reasons cross a `NotificationCenter` hop as raw strings, so the
    /// round-trip has to be lossless or the pane silently falls back to `.none`.
    func testEveryReasonRoundTripsThroughItsRawValue() {
        let all: [DiscordRPCService.ConnectionFailure] = [
            .none, .notRunning, .handshakeRejected, .socketUnavailable, .notConfigured
        ]
        for failure in all {
            XCTAssertEqual(
                DiscordRPCService.ConnectionFailure(rawValue: failure.rawValue),
                failure,
                "\(failure) should survive the notification hop"
            )
        }
    }

    func testUnknownRawValueIsRejected() {
        XCTAssertNil(DiscordRPCService.ConnectionFailure(rawValue: "somethingElse"))
    }

    /// `notRunning` and `handshakeRejected` are the pair that used to be
    /// conflated. Discord being closed and Discord refusing us are different
    /// problems with different fixes.
    func testRunningButRefusedIsDistinctFromNotRunning() {
        XCTAssertNotEqual(
            DiscordRPCService.ConnectionFailure.notRunning,
            DiscordRPCService.ConnectionFailure.handshakeRejected
        )
    }

    // MARK: - Notification Payload

    func testStatePayloadCarriesTheFailureReason() {
        let expectation = expectation(description: "state posted")
        let observer = NotificationCenter.default.addObserver(
            forName: .discordStateChanged,
            object: nil,
            queue: .main
        ) { notification in
            XCTAssertEqual(notification.stateString, "disconnected")
            XCTAssertEqual(notification.errorMessage, "handshakeRejected")
            expectation.fulfill()
        }
        defer { NotificationCenter.default.removeObserver(observer) }

        NotificationCenter.default.postDiscordState(
            "disconnected",
            failure: DiscordRPCService.ConnectionFailure.handshakeRejected.rawValue
        )
        wait(for: [expectation], timeout: 2)
    }

    /// The reason is optional so existing callers keep working unchanged.
    func testStatePayloadOmitsTheReasonWhenAbsent() {
        let expectation = expectation(description: "state posted")
        let observer = NotificationCenter.default.addObserver(
            forName: .discordStateChanged,
            object: nil,
            queue: .main
        ) { notification in
            XCTAssertEqual(notification.stateString, "connected")
            XCTAssertNil(notification.errorMessage)
            expectation.fulfill()
        }
        defer { NotificationCenter.default.removeObserver(observer) }

        NotificationCenter.default.postDiscordState("connected")
        wait(for: [expectation], timeout: 2)
    }
}
