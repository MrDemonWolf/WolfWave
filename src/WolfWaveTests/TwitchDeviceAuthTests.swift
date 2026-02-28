//
//  TwitchDeviceAuthTests.swift
//  WolfWaveTests
//
//  Created by MrDemonWolf, Inc. on 2/27/26.
//

import XCTest
@testable import WolfWave

final class TwitchDeviceAuthTests: XCTestCase {

    // MARK: - Error Type Tests

    func testInvalidResponseErrorDescription() {
        let error = TwitchDeviceAuthError.invalidResponse
        XCTAssertEqual(error.errorDescription, "Invalid response from Twitch")
    }

    func testAccessDeniedErrorDescription() {
        let error = TwitchDeviceAuthError.accessDenied
        XCTAssertEqual(error.errorDescription, "Access denied by user")
    }

    func testExpiredTokenErrorDescription() {
        let error = TwitchDeviceAuthError.expiredToken
        XCTAssertEqual(error.errorDescription, "Device code expired")
    }

    func testAuthorizationPendingErrorDescription() {
        let error = TwitchDeviceAuthError.authorizationPending
        XCTAssertEqual(error.errorDescription, "Waiting for user authorization")
    }

    func testSlowDownErrorDescription() {
        let error = TwitchDeviceAuthError.slowDown
        XCTAssertEqual(error.errorDescription, "Polling too quickly")
    }

    func testInvalidClientErrorDescription() {
        let error = TwitchDeviceAuthError.invalidClient
        XCTAssertEqual(error.errorDescription, "Invalid client credentials")
    }

    func testUnknownErrorDescription() {
        let error = TwitchDeviceAuthError.unknown("Something went wrong")
        XCTAssertEqual(error.errorDescription, "Something went wrong")
    }

    // MARK: - Request Device Code Tests

    func testRequestDeviceCodeWithEmptyClientIDThrowsInvalidClient() async {
        let auth = TwitchDeviceAuth(clientID: "", scopes: ["chat:read"])
        do {
            _ = try await auth.requestDeviceCode()
            XCTFail("Expected invalidClient error")
        } catch let error as TwitchDeviceAuthError {
            if case .invalidClient = error {
                // Expected
            } else {
                XCTFail("Expected invalidClient, got \(error)")
            }
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }

    // MARK: - Poll For Token Validation Tests

    func testPollForTokenWithEmptyDeviceCodeThrowsInvalidClient() async {
        let auth = TwitchDeviceAuth(clientID: "test-id", scopes: ["chat:read"])
        do {
            _ = try await auth.pollForToken(
                deviceCode: "", interval: 5, progress: { _ in }
            )
            XCTFail("Expected invalidClient error")
        } catch let error as TwitchDeviceAuthError {
            if case .invalidClient = error {
                // Expected
            } else {
                XCTFail("Expected invalidClient, got \(error)")
            }
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }

    func testPollForTokenWithZeroIntervalThrowsInvalidResponse() async {
        let auth = TwitchDeviceAuth(clientID: "test-id", scopes: ["chat:read"])
        do {
            _ = try await auth.pollForToken(
                deviceCode: "test-code", interval: 0, progress: { _ in }
            )
            XCTFail("Expected invalidResponse error")
        } catch let error as TwitchDeviceAuthError {
            if case .invalidResponse = error {
                // Expected
            } else {
                XCTFail("Expected invalidResponse, got \(error)")
            }
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }

    // MARK: - Device Code Response Tests

    func testDeviceCodeResponseProperties() {
        let response = TwitchDeviceCodeResponse(
            deviceCode: "abc123",
            userCode: "WOLF-1234",
            verificationURI: "https://www.twitch.tv/activate",
            verificationURIComplete: "https://www.twitch.tv/activate?user-code=WOLF-1234",
            expiresIn: 600,
            interval: 5
        )
        XCTAssertEqual(response.deviceCode, "abc123")
        XCTAssertEqual(response.userCode, "WOLF-1234")
        XCTAssertEqual(response.verificationURI, "https://www.twitch.tv/activate")
        XCTAssertEqual(response.verificationURIComplete, "https://www.twitch.tv/activate?user-code=WOLF-1234")
        XCTAssertEqual(response.expiresIn, 600)
        XCTAssertEqual(response.interval, 5)
    }

    func testDeviceCodeResponseWithoutCompleteURI() {
        let response = TwitchDeviceCodeResponse(
            deviceCode: "abc123",
            userCode: "WOLF-1234",
            verificationURI: "https://www.twitch.tv/activate",
            verificationURIComplete: nil,
            expiresIn: 600,
            interval: 5
        )
        XCTAssertNil(response.verificationURIComplete)
    }
}
