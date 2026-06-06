//
//  MapHelixErrorTests.swift
//  WolfWave
//
//  Created by Nathanial Henniges on 2026-06-06.
//  Copyright © 2026 MrDemonWolf, Inc. All rights reserved.
//

import XCTest
@testable import WolfWave

/// Table tests for the file-scope `mapHelixError` helper in `TwitchChatService`.
///
/// The contract that matters for re-auth resilience is the 401 ->
/// `.authenticationFailed` mapping: a token that expired mid-session must surface
/// as an auth failure (so the UI can prompt a re-sign-in) and not as a generic
/// network error. Every other `HTTPError` collapses to `.networkError(...)`.
final class MapHelixErrorTests: XCTestCase {

    private struct DummyError: Error {}

    /// Convenience: classify a mapped `ConnectionError` into a comparable token so
    /// the table below can assert without `ConnectionError` being `Equatable`.
    private enum Kind: Equatable {
        case authenticationFailed
        case network(String)
        case other
    }

    private func kind(_ error: TwitchChatService.ConnectionError) -> Kind {
        switch error {
        case .authenticationFailed: return .authenticationFailed
        case .networkError(let msg): return .network(msg)
        default: return .other
        }
    }

    // MARK: - 401 mapping

    func testUnauthorizedMapsToAuthenticationFailed() {
        let mapped = mapHelixError(HTTPClient.HTTPError.unexpectedStatus(401, body: "unauthorized"))
        XCTAssertEqual(kind(mapped), .authenticationFailed,
                       "401 must surface as .authenticationFailed for re-auth")
    }

    // MARK: - Table over the remaining HTTPError cases

    func testHTTPErrorCasesMapToNetworkErrors() {
        let cases: [(HTTPClient.HTTPError, Kind)] = [
            (.unexpectedStatus(403, body: ""), .network("HTTP 403")),
            (.unexpectedStatus(429, body: ""), .network("HTTP 429")),
            (.unexpectedStatus(500, body: ""), .network("HTTP 500")),
            (.invalidResponse, .network("No HTTP response")),
        ]

        for (input, expected) in cases {
            XCTAssertEqual(kind(mapHelixError(input)), expected,
                           "HTTPError \(input) should map to \(expected)")
        }
    }

    func testDecodingFailedMapsToNetworkError() {
        let mapped = mapHelixError(HTTPClient.HTTPError.decodingFailed(underlying: DummyError()))
        XCTAssertEqual(kind(mapped), .network("Unable to decode response"))
    }

    func testTransportErrorCarriesUnderlyingDescription() {
        let underlying = NSError(domain: "test", code: -1009,
                                 userInfo: [NSLocalizedDescriptionKey: "offline"])
        let mapped = mapHelixError(HTTPClient.HTTPError.transport(underlying: underlying))
        XCTAssertEqual(kind(mapped), .network("offline"))
    }

    // MARK: - Pass-through and fallback

    func testExistingConnectionErrorPassesThrough() {
        let mapped = mapHelixError(TwitchChatService.ConnectionError.authenticationFailed)
        XCTAssertEqual(kind(mapped), .authenticationFailed)
    }

    func testUnknownErrorFallsBackToNetworkError() {
        let mapped = mapHelixError(DummyError())
        if case .networkError = mapped {
            // Expected: any non-HTTPError, non-ConnectionError becomes networkError.
        } else {
            XCTFail("Unknown error should fall back to .networkError, got \(mapped)")
        }
    }
}
