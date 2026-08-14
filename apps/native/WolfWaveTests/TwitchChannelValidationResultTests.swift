//
//  TwitchChannelValidationResultTests.swift
//  WolfWave
//
//  Created by Nathanial Henniges on 2026-08-14.
//  Copyright © 2026 MrDemonWolf, Inc. All rights reserved.
//

import XCTest
@testable import WolfWave

/// Covers the split between "your sign-in is bad" and "your sign-in is fine,
/// the lookup failed for another reason".
///
/// `GET /helix/users` requires no scope, so 401 is the only status that
/// implicates the token. Everything else Twitch refuses means the credentials
/// were accepted, and telling the user to reconnect would waste their time.
final class TwitchChannelValidationResultTests: XCTestCase {

    // MARK: - Connection Error Vocabulary

    /// An unknown login comes back as HTTP 200 with an empty data array. That is
    /// a real answer, not a failed request, and it used to be signalled by
    /// string-matching `networkError("Unable to resolve username")`.
    func testChannelNotFoundIsItsOwnCase() {
        let error = TwitchChatService.ConnectionError.channelNotFound
        XCTAssertEqual(error.errorDescription, "No Twitch channel by that name")
    }

    func testNotPermittedKeepsItsStatusCode() {
        let error = TwitchChatService.ConnectionError.notPermitted(status: 403)
        XCTAssertEqual(error.errorDescription, "Twitch refused the request (HTTP 403)")
    }

    /// The old code flattened every non-401 into `networkError("HTTP 429")`,
    /// making a rate limit indistinguishable from an outage.
    func testNotPermittedDistinguishesStatuses() {
        let rateLimited = TwitchChatService.ConnectionError.notPermitted(status: 429)
        let serverError = TwitchChatService.ConnectionError.notPermitted(status: 503)
        XCTAssertNotEqual(rateLimited.errorDescription, serverError.errorDescription)
    }

    // MARK: - Result Equality

    func testNotPermittedResultsCompareByStatus() {
        XCTAssertEqual(
            TwitchChatService.ChannelValidationResult.notPermitted(status: 429),
            .notPermitted(status: 429)
        )
        XCTAssertNotEqual(
            TwitchChatService.ChannelValidationResult.notPermitted(status: 429),
            .notPermitted(status: 500)
        )
        XCTAssertNotEqual(
            TwitchChatService.ChannelValidationResult.notPermitted(status: 403),
            .authenticationFailed
        )
    }

    // MARK: - User-Facing Copy

    /// Every message on this path leads with the sign-in being fine, because
    /// the user's instinct otherwise is to reconnect.
    @MainActor
    func testEveryNotPermittedMessageSaysTheSignInIsFine() {
        for status in [403, 429, 500, 502, 503] {
            let message = TwitchViewModel.notPermittedMessage(status: status)
            XCTAssertTrue(
                message.contains("sign-in is fine"),
                "HTTP \(status) should reassure about the sign-in, got: \(message)"
            )
        }
    }

    @MainActor
    func testRateLimitAndOutageReadDifferently() {
        let rateLimited = TwitchViewModel.notPermittedMessage(status: 429)
        let outage = TwitchViewModel.notPermittedMessage(status: 503)
        XCTAssertTrue(rateLimited.contains("rate limiting"))
        XCTAssertTrue(outage.contains("having trouble"))
        XCTAssertNotEqual(rateLimited, outage)
    }

    /// A raw status code is fine as supporting detail, but never for the two
    /// cases we can name properly.
    @MainActor
    func testNamedCasesDoNotLeakRawStatusCodes() {
        XCTAssertFalse(TwitchViewModel.notPermittedMessage(status: 429).contains("429"))
        XCTAssertFalse(TwitchViewModel.notPermittedMessage(status: 503).contains("503"))
        XCTAssertTrue(TwitchViewModel.notPermittedMessage(status: 403).contains("403"))
    }

    // MARK: - Token Validation Result

    func testMissingScopesIsDistinctFromInvalid() {
        let missing = TwitchChatService.TokenValidationResult.missingScopes(["bits:read"])
        XCTAssertNotEqual(missing, .invalid)
        XCTAssertNotEqual(missing, .valid)
        XCTAssertEqual(missing, .missingScopes(["bits:read"]))
    }

    func testMissingScopesCarriesEveryMissingScope() {
        let scopes = ["channel:manage:polls", "bits:read"]
        guard case .missingScopes(let reported) =
                TwitchChatService.TokenValidationResult.missingScopes(scopes) else {
            return XCTFail("Expected missingScopes")
        }
        XCTAssertEqual(reported, scopes)
    }
}
