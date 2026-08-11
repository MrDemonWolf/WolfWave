//
//  TwitchDeviceAuthNetworkTests.swift
//  WolfWave
//
//  Created by Nathanial Henniges on 2026-05-22.
//  Copyright © 2026 MrDemonWolf, Inc. All rights reserved.
//

import XCTest

@testable import WolfWave

/// A monotonic clock/sleeper pair that advances instantly when production code
/// asks it to sleep. This makes multi-poll OAuth tests deterministic.
private nonisolated final class DeviceAuthVirtualClock: @unchecked Sendable {
    private struct State {
        var instant: ContinuousClock.Instant
        var delays: [Duration] = []
    }

    private let state = ThreadSafeBox(State(instant: ContinuousClock.now))

    var now: ContinuousClock.Instant {
        state.value.instant
    }

    var delays: [Duration] {
        state.value.delays
    }

    func advance(by duration: Duration) {
        state.mutate {
            $0.instant = $0.instant.advanced(by: duration)
        }
    }

    func sleep(for delay: Duration, tolerance _: Duration?) async throws {
        try Task.checkCancellation()
        state.mutate {
            $0.instant = $0.instant.advanced(by: delay)
            $0.delays.append(delay)
        }
        await Task.yield()
        try Task.checkCancellation()
    }
}

// MARK: - TwitchDeviceAuthNetworkTests

/// Covers `TwitchDeviceAuth` OAuth Device Code networking: device-code
/// requests and deadline-bounded multi-shot token polling, driven by
/// `MockURLProtocol` and a virtual monotonic clock.
@MainActor
final class TwitchDeviceAuthNetworkTests: XCTestCase {

    private let handlerStore = MockURLProtocol.HandlerStore()

    override func setUp() {
        super.setUp()
        handlerStore.handler = nil
    }

    override func tearDown() {
        handlerStore.handler = nil
        super.tearDown()
    }

    private func makeAuth(
        clientID: String = "test-client",
        clock: DeviceAuthVirtualClock = DeviceAuthVirtualClock()
    ) -> TwitchDeviceAuth {
        TwitchDeviceAuth(
            clientID: clientID,
            scopes: ["user:read:chat"],
            session: MockURLProtocol.makeSession(handlerStore: handlerStore),
            pollingNow: { clock.now },
            pollingSleep: { delay, tolerance in
                try await clock.sleep(for: delay, tolerance: tolerance)
            }
        )
    }

    nonisolated private static func nextAttempt(_ counter: ThreadSafeBox<Int>) -> Int {
        var next = 0
        counter.mutate {
            $0 += 1
            next = $0
        }
        return next
    }

    // MARK: - requestDeviceCode

    func testRequestDeviceCodeParsesResponse() async throws {
        let requestBody = ThreadSafeBox("")
        handlerStore.handler = { request in
            requestBody.value = String(data: request.httpBody ?? Data(), encoding: .utf8) ?? ""
            let json = #"{"device_code":"DEV","user_code":"WXYZ","verification_uri":"https://twitch.tv/activate","verification_uri_complete":"https://twitch.tv/activate?code=WXYZ","expires_in":600,"interval":5}"#
            return (MockURLProtocol.httpResponse(for: request, status: 200), Data(json.utf8))
        }

        let response = try await makeAuth().requestDeviceCode()

        XCTAssertEqual(response.deviceCode, "DEV")
        XCTAssertEqual(response.userCode, "WXYZ")
        XCTAssertEqual(response.verificationURI, "https://twitch.tv/activate")
        XCTAssertEqual(response.verificationURIComplete, "https://twitch.tv/activate?code=WXYZ")
        XCTAssertEqual(response.expiresIn, 600)
        XCTAssertEqual(response.interval, 5)
        XCTAssertTrue(requestBody.value.contains("scopes=user%3Aread%3Achat"))
    }

    func testRequestDeviceCodeDefaultsMissingIntervalToRFCValue() async throws {
        handlerStore.handler = { request in
            let json = #"""
            {
              "device_code": "DEV",
              "user_code": "WXYZ",
              "verification_uri": "https://twitch.tv/activate",
              "expires_in": 1800
            }
            """#
            return (MockURLProtocol.httpResponse(for: request, status: 200), Data(json.utf8))
        }

        let response = try await makeAuth().requestDeviceCode()

        XCTAssertEqual(response.interval, 5)
    }

    func testRequestDeviceCodeRejectsUnsafeTimingMetadata() async {
        let responses = [
            #"""
            {"device_code":"DEV","user_code":"WXYZ","verification_uri":"https://twitch.tv/activate",
             "expires_in":9223372036854775807,"interval":5}
            """#,
            #"""
            {"device_code":"DEV","user_code":"WXYZ","verification_uri":"https://twitch.tv/activate",
             "expires_in":1800,"interval":9223372036854775807}
            """#,
        ]

        for json in responses {
            handlerStore.handler = { request in
                (MockURLProtocol.httpResponse(for: request, status: 200), Data(json.utf8))
            }
            do {
                _ = try await makeAuth().requestDeviceCode()
                XCTFail("Expected .invalidResponse")
            } catch TwitchDeviceAuthError.invalidResponse {
                // expected
            } catch {
                XCTFail("Unexpected error: \(error)")
            }
        }
    }

    func testRequestDeviceCodeEmptyClientIDThrowsInvalidClient() async {
        do {
            _ = try await makeAuth(clientID: "").requestDeviceCode()
            XCTFail("Expected .invalidClient")
        } catch TwitchDeviceAuthError.invalidClient {
            // expected
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testRequestDeviceCode401ThrowsInvalidClient() async {
        handlerStore.handler = { request in
            (MockURLProtocol.httpResponse(for: request, status: 401), Data("unauthorized".utf8))
        }

        do {
            _ = try await makeAuth().requestDeviceCode()
            XCTFail("Expected .invalidClient")
        } catch TwitchDeviceAuthError.invalidClient {
            // expected
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testRequestDeviceCodeMalformedJSONThrowsInvalidResponse() async {
        handlerStore.handler = { request in
            (MockURLProtocol.httpResponse(for: request, status: 200),
             Data(#"{"device_code":"only-this"}"#.utf8))
        }

        do {
            _ = try await makeAuth().requestDeviceCode()
            XCTFail("Expected .invalidResponse")
        } catch TwitchDeviceAuthError.invalidResponse {
            // expected
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    // MARK: - pollForToken

    func testPollForTokenReturnsAccessTokenOnSuccess() async throws {
        let requestBody = ThreadSafeBox("")
        handlerStore.handler = { request in
            requestBody.value = String(data: request.httpBody ?? Data(), encoding: .utf8) ?? ""
            return (
                MockURLProtocol.httpResponse(for: request, status: 200),
                Data(#"{"access_token":"ABC123","refresh_token":"REFRESH123"}"#.utf8)
            )
        }

        let grant = try await makeAuth().pollForToken(deviceCode: "DEV", interval: 1) { _ in }

        XCTAssertEqual(grant.accessToken, "ABC123")
        XCTAssertEqual(grant.refreshToken, "REFRESH123")
        XCTAssertTrue(requestBody.value.contains("scopes=user%3Aread%3Achat"))
    }

    func testAuthorizationPendingContinuesAtOriginalInterval() async throws {
        let attempts = ThreadSafeBox(0)
        let clock = DeviceAuthVirtualClock()
        handlerStore.handler = { request in
            if Self.nextAttempt(attempts) == 1 {
                return (
                    MockURLProtocol.httpResponse(for: request, status: 400),
                    Data(#"{"status":400,"message":"authorization_pending"}"#.utf8))
            }
            return (
                MockURLProtocol.httpResponse(for: request, status: 200),
                Data(#"{"access_token":"READY","refresh_token":"READY_RT"}"#.utf8))
        }

        let grant = try await makeAuth(clock: clock).pollForToken(
            deviceCode: "DEV",
            interval: 2,
            expiresIn: 30
        ) { _ in }

        XCTAssertEqual(grant.accessToken, "READY")
        XCTAssertEqual(attempts.value, 2)
        XCTAssertEqual(clock.delays, [.seconds(2)])
    }

    func testSlowDownAddsFiveSecondsForEverySubsequentPoll() async throws {
        let attempts = ThreadSafeBox(0)
        let clock = DeviceAuthVirtualClock()
        handlerStore.handler = { request in
            switch Self.nextAttempt(attempts) {
            case 1:
                return (
                    MockURLProtocol.httpResponse(for: request, status: 400),
                    Data(#"{"error":"slow_down"}"#.utf8))
            case 2:
                return (
                    MockURLProtocol.httpResponse(for: request, status: 400),
                    Data(#"{"message":"authorization_pending"}"#.utf8))
            default:
                return (
                    MockURLProtocol.httpResponse(for: request, status: 200),
                    Data(#"{"access_token":"READY","refresh_token":"READY_RT"}"#.utf8))
            }
        }

        let grant = try await makeAuth(clock: clock).pollForToken(
            deviceCode: "DEV",
            interval: 2,
            expiresIn: 30
        ) { _ in }

        XCTAssertEqual(grant.accessToken, "READY")
        XCTAssertEqual(attempts.value, 3)
        XCTAssertEqual(clock.delays, [.seconds(7), .seconds(7)])
    }

    func testTransientHTTPAndTransportFailuresRecover() async throws {
        let attempts = ThreadSafeBox(0)
        let clock = DeviceAuthVirtualClock()
        handlerStore.handler = { request in
            switch Self.nextAttempt(attempts) {
            case 1:
                return (
                    MockURLProtocol.httpResponse(for: request, status: 429),
                    Data("rate limited".utf8))
            case 2:
                return (
                    MockURLProtocol.httpResponse(for: request, status: 503),
                    Data("unavailable".utf8))
            case 3:
                throw URLError(.networkConnectionLost)
            default:
                return (
                    MockURLProtocol.httpResponse(for: request, status: 200),
                    Data(#"{"access_token":"RECOVERED","refresh_token":"RECOVERED_RT"}"#.utf8))
            }
        }

        let grant = try await makeAuth(clock: clock).pollForToken(
            deviceCode: "DEV",
            interval: 1,
            expiresIn: 30
        ) { _ in }

        XCTAssertEqual(grant.accessToken, "RECOVERED")
        XCTAssertEqual(attempts.value, 4)
        XCTAssertEqual(clock.delays, [.seconds(6), .seconds(6), .seconds(6)])
    }

    func testConnectionTimeoutDoublesPollingInterval() async throws {
        let attempts = ThreadSafeBox(0)
        let clock = DeviceAuthVirtualClock()
        handlerStore.handler = { request in
            if Self.nextAttempt(attempts) == 1 {
                throw URLError(.timedOut)
            }
            return (
                MockURLProtocol.httpResponse(for: request, status: 200),
                Data(#"{"access_token":"RECOVERED","refresh_token":"RECOVERED_RT"}"#.utf8))
        }

        let grant = try await makeAuth(clock: clock).pollForToken(
            deviceCode: "DEV",
            interval: 2,
            expiresIn: 30
        ) { _ in }

        XCTAssertEqual(grant.accessToken, "RECOVERED")
        XCTAssertEqual(attempts.value, 2)
        XCTAssertEqual(clock.delays, [.seconds(4)])
    }

    func testServerErrorHonorsRetryAfterForOnePollOnly() async throws {
        let attempts = ThreadSafeBox(0)
        let clock = DeviceAuthVirtualClock()
        handlerStore.handler = { request in
            switch Self.nextAttempt(attempts) {
            case 1:
                return (
                    MockURLProtocol.httpResponse(
                        for: request, status: 503, headers: ["Retry-After": "12"]),
                    Data())
            case 2:
                return (
                    MockURLProtocol.httpResponse(for: request, status: 400),
                    Data(#"{"message":"authorization_pending"}"#.utf8))
            default:
                return (
                    MockURLProtocol.httpResponse(for: request, status: 200),
                    Data(#"{"access_token":"RECOVERED","refresh_token":"RECOVERED_RT"}"#.utf8))
            }
        }

        _ = try await makeAuth(clock: clock).pollForToken(
            deviceCode: "DEV", interval: 1, expiresIn: 30
        ) { _ in }

        XCTAssertEqual(clock.delays, [.seconds(12), .seconds(1)])
    }

    func testConnectionTimeoutCapsPollingInterval() async throws {
        let attempts = ThreadSafeBox(0)
        let clock = DeviceAuthVirtualClock()
        handlerStore.handler = { request in
            if Self.nextAttempt(attempts) == 1 {
                throw URLError(.timedOut)
            }
            return (
                MockURLProtocol.httpResponse(for: request, status: 200),
                Data(#"{"access_token":"RECOVERED","refresh_token":"RECOVERED_RT"}"#.utf8))
        }

        _ = try await makeAuth(clock: clock).pollForToken(
            deviceCode: "DEV", interval: 200, expiresIn: 600
        ) { _ in }

        XCTAssertEqual(clock.delays, [.seconds(300)])
    }

    func testSlowDownSaturatesAtPollingCeiling() async throws {
        let attempts = ThreadSafeBox(0)
        let clock = DeviceAuthVirtualClock()
        handlerStore.handler = { request in
            if Self.nextAttempt(attempts) == 1 {
                return (
                    MockURLProtocol.httpResponse(for: request, status: 400),
                    Data(#"{"message":"slow_down"}"#.utf8))
            }
            return (
                MockURLProtocol.httpResponse(for: request, status: 200),
                Data(#"{"access_token":"RECOVERED","refresh_token":"RECOVERED_RT"}"#.utf8))
        }

        _ = try await makeAuth(clock: clock).pollForToken(
            deviceCode: "DEV", interval: 298, expiresIn: 600
        ) { _ in }

        XCTAssertEqual(attempts.value, 2)
        XCTAssertEqual(clock.delays, [.seconds(300)])
    }

    func testRateLimitHonorsLongerRetryAfter() async throws {
        let attempts = ThreadSafeBox(0)
        let clock = DeviceAuthVirtualClock()
        handlerStore.handler = { request in
            if Self.nextAttempt(attempts) == 1 {
                return (
                    MockURLProtocol.httpResponse(
                        for: request, status: 429, headers: ["Retry-After": "12"]),
                    Data())
            }
            return (
                MockURLProtocol.httpResponse(for: request, status: 200),
                Data(#"{"access_token":"READY","refresh_token":"READY_RT"}"#.utf8))
        }

        _ = try await makeAuth(clock: clock).pollForToken(
            deviceCode: "DEV", interval: 1, expiresIn: 30
        ) { _ in }

        XCTAssertEqual(clock.delays, [.seconds(12)])
    }

    func testRateLimitCapsHugeRetryAfterAndRemainsAtCeiling() async throws {
        let attempts = ThreadSafeBox(0)
        let clock = DeviceAuthVirtualClock()
        handlerStore.handler = { request in
            if Self.nextAttempt(attempts) <= 2 {
                return (
                    MockURLProtocol.httpResponse(
                        for: request, status: 429, headers: ["Retry-After": "1e308"]),
                    Data())
            }
            return (
                MockURLProtocol.httpResponse(for: request, status: 200),
                Data(#"{"access_token":"READY","refresh_token":"READY_RT"}"#.utf8))
        }

        _ = try await makeAuth(clock: clock).pollForToken(
            deviceCode: "DEV", interval: 1, expiresIn: 900
        ) { _ in }

        XCTAssertEqual(clock.delays, [.seconds(300), .seconds(300)])
    }

    func testPollSuccessWithoutRefreshTokenIsRejected() async {
        handlerStore.handler = { request in
            (
                MockURLProtocol.httpResponse(for: request, status: 200),
                Data(#"{"access_token":"EPHEMERAL_ONLY"}"#.utf8))
        }

        do {
            _ = try await makeAuth().pollForToken(
                deviceCode: "DEV", interval: 1, expiresIn: 30
            ) { _ in }
            XCTFail("Expected .invalidResponse")
        } catch TwitchDeviceAuthError.invalidResponse {
            // expected
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testExpiryClipsFinalDelayAndPreventsAnotherRequest() async {
        let attempts = ThreadSafeBox(0)
        let clock = DeviceAuthVirtualClock()
        handlerStore.handler = { request in
            _ = Self.nextAttempt(attempts)
            return (
                MockURLProtocol.httpResponse(for: request, status: 503),
                Data("unavailable".utf8))
        }

        do {
            _ = try await makeAuth(clock: clock).pollForToken(
                deviceCode: "DEV",
                interval: 2,
                expiresIn: 5
            ) { _ in }
            XCTFail("Expected .expiredToken")
        } catch TwitchDeviceAuthError.expiredToken {
            // expected
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        XCTAssertEqual(attempts.value, 3)
        XCTAssertEqual(clock.delays, [.seconds(2), .seconds(2), .seconds(1)])
    }

    func testSuccessArrivingAtExpiryDeadlineIsRejected() async {
        let attempts = ThreadSafeBox(0)
        let clock = DeviceAuthVirtualClock()
        handlerStore.handler = { request in
            _ = Self.nextAttempt(attempts)
            clock.advance(by: .seconds(5))
            return (
                MockURLProtocol.httpResponse(for: request, status: 200),
                Data(#"{"access_token":"TOO-LATE"}"#.utf8))
        }

        do {
            _ = try await makeAuth(clock: clock).pollForToken(
                deviceCode: "DEV",
                interval: 1,
                expiresIn: 5
            ) { _ in }
            XCTFail("Expected .expiredToken")
        } catch TwitchDeviceAuthError.expiredToken {
            // expected
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        XCTAssertEqual(attempts.value, 1)
        XCTAssertTrue(clock.delays.isEmpty)
    }

    func testMalformedNonTransientResponseStopsWithoutSleeping() async {
        let attempts = ThreadSafeBox(0)
        let clock = DeviceAuthVirtualClock()
        handlerStore.handler = { request in
            _ = Self.nextAttempt(attempts)
            return (
                MockURLProtocol.httpResponse(for: request, status: 400),
                Data("not-json".utf8))
        }

        do {
            _ = try await makeAuth(clock: clock).pollForToken(
                deviceCode: "DEV",
                interval: 1,
                expiresIn: 30
            ) { _ in }
            XCTFail("Expected terminal .unknown error")
        } catch TwitchDeviceAuthError.unknown(let message) {
            XCTAssertEqual(message, "not-json")
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        XCTAssertEqual(attempts.value, 1)
        XCTAssertTrue(clock.delays.isEmpty)
    }

    func testCancellationDuringPollingSleepStopsImmediately() async {
        let attempts = ThreadSafeBox(0)
        let clock = DeviceAuthVirtualClock()
        handlerStore.handler = { request in
            _ = Self.nextAttempt(attempts)
            return (
                MockURLProtocol.httpResponse(for: request, status: 400),
                Data(#"{"message":"authorization_pending"}"#.utf8))
        }
        let auth = TwitchDeviceAuth(
            clientID: "test-client",
            scopes: ["user:read:chat"],
            session: MockURLProtocol.makeSession(handlerStore: handlerStore),
            pollingNow: { clock.now },
            pollingSleep: { _, _ in throw CancellationError() }
        )

        do {
            _ = try await auth.pollForToken(
                deviceCode: "DEV",
                interval: 1,
                expiresIn: 30
            ) { _ in }
            XCTFail("Expected CancellationError")
        } catch is CancellationError {
            // expected
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        XCTAssertEqual(attempts.value, 1)
    }

    func testMissingExpiryMetadataStopsAtFallbackDeadline() async {
        let attempts = ThreadSafeBox(0)
        let clock = DeviceAuthVirtualClock()
        handlerStore.handler = { request in
            _ = Self.nextAttempt(attempts)
            return (
                MockURLProtocol.httpResponse(for: request, status: 400),
                Data(#"{"message":"authorization_pending"}"#.utf8))
        }

        do {
            _ = try await makeAuth(clock: clock).pollForToken(
                deviceCode: "DEV",
                interval: 1
            ) { _ in }
            XCTFail("Expected .expiredToken")
        } catch TwitchDeviceAuthError.expiredToken {
            // expected
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        XCTAssertEqual(attempts.value, 600)
        XCTAssertEqual(clock.delays.count, 600)
    }

    func testPollForTokenRejectsUnsafeTimingMetadataBeforeRequest() async {
        for timing in [
            (interval: Int.max, expiresIn: 600),
            (interval: 5, expiresIn: Int.max),
        ] {
            do {
                _ = try await makeAuth().pollForToken(
                    deviceCode: "DEV",
                    interval: timing.interval,
                    expiresIn: timing.expiresIn
                ) { _ in }
                XCTFail("Expected .invalidResponse")
            } catch TwitchDeviceAuthError.invalidResponse {
                // expected
            } catch {
                XCTFail("Unexpected error: \(error)")
            }
        }
    }

    func testPollForTokenAccessDeniedThrows() async {
        handlerStore.handler = { request in
            (MockURLProtocol.httpResponse(for: request, status: 400),
             Data(#"{"error":"access_denied"}"#.utf8))
        }

        do {
            _ = try await makeAuth().pollForToken(deviceCode: "DEV", interval: 1) { _ in }
            XCTFail("Expected .accessDenied")
        } catch TwitchDeviceAuthError.accessDenied {
            // expected
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testPollForTokenInvalidClientThrows() async {
        handlerStore.handler = { request in
            (MockURLProtocol.httpResponse(for: request, status: 400),
             Data(#"{"error":"invalid_client"}"#.utf8))
        }

        do {
            _ = try await makeAuth().pollForToken(deviceCode: "DEV", interval: 1) { _ in }
            XCTFail("Expected .invalidClient")
        } catch TwitchDeviceAuthError.invalidClient {
            // expected
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testPollForTokenEmptyDeviceCodeThrowsInvalidClient() async {
        do {
            _ = try await makeAuth().pollForToken(deviceCode: "", interval: 5) { _ in }
            XCTFail("Expected .invalidClient")
        } catch TwitchDeviceAuthError.invalidClient {
            // expected
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
}
