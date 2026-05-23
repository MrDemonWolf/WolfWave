//
//  TwitchDeviceAuthNetworkTests.swift
//  WolfWaveTests
//
//  Created by MrDemonWolf, Inc. on 5/22/26.
//

import XCTest

@testable import WolfWave

// MARK: - TwitchDeviceAuthNetworkTests

/// Covers `TwitchDeviceAuth` OAuth Device Code networking — device-code
/// requests and single-shot token polls — driven by `MockURLProtocol`.
///
/// Multi-iteration polling (`authorization_pending` → success) is not covered
/// here: it sleeps for the poll interval between attempts. Only paths that
/// resolve on the first response are exercised.
final class TwitchDeviceAuthNetworkTests: XCTestCase {

    override func tearDown() {
        MockURLProtocol.reset()
        super.tearDown()
    }

    private func makeAuth(clientID: String = "test-client") -> TwitchDeviceAuth {
        TwitchDeviceAuth(
            clientID: clientID,
            scopes: ["user:read:chat"],
            session: MockURLProtocol.makeSession()
        )
    }

    // MARK: - requestDeviceCode

    func testRequestDeviceCodeParsesResponse() async throws {
        MockURLProtocol.requestHandler = { request in
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
        MockURLProtocol.requestHandler = { request in
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
        MockURLProtocol.requestHandler = { request in
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
        MockURLProtocol.requestHandler = { request in
            (MockURLProtocol.httpResponse(for: request, status: 200),
             Data(#"{"access_token":"ABC123"}"#.utf8))
        }

        let token = try await makeAuth().pollForToken(deviceCode: "DEV", interval: 1) { _ in }

        XCTAssertEqual(token, "ABC123")
    }

    func testPollForTokenAccessDeniedThrows() async {
        MockURLProtocol.requestHandler = { request in
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
        MockURLProtocol.requestHandler = { request in
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
