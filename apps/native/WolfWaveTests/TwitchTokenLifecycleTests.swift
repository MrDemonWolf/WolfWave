//
//  TwitchTokenLifecycleTests.swift
//  WolfWave
//
//  Created by Nathanial Henniges on 2026-08-11.
//  Copyright © 2026 MrDemonWolf, Inc. All rights reserved.
//

import XCTest

@testable import WolfWave

// MARK: - TwitchTokenLifecycleTests

/// Covers credential persistence, OAuth validation ownership, reactive refresh,
/// token adoption, and EventSub reconnect behavior.
@MainActor
final class TwitchTokenLifecycleTests: XCTestCase {

    private var previousBackend: KeychainBackend!
    private var backend: InMemoryKeychainBackend!
    private let handlerStore = MockURLProtocol.HandlerStore()

    override func setUp() {
        super.setUp()
        handlerStore.handler = nil
        resetRedemptionDefaults()
        KeychainBackendTestIsolation.acquire()
        previousBackend = KeychainService.backend
        backend = InMemoryKeychainBackend()
        KeychainService.backend = backend
    }

    override func tearDown() {
        resetRedemptionDefaults()
        handlerStore.handler = nil
        KeychainService.backend = previousBackend
        KeychainBackendTestIsolation.release()
        super.tearDown()
    }

    private func resetRedemptionDefaults() {
        let defaults = UserDefaults.standard
        [
            AppConstants.UserDefaults.songRequestEnabled,
            AppConstants.UserDefaults.songRequestChannelPointsEnabled,
            AppConstants.UserDefaults.songRequestBitsEnabled,
            AppConstants.UserDefaults.songRequestChannelPointsRewardID,
            AppConstants.UserDefaults.songRequestChannelPointsRewardIdentity,
            AppConstants.UserDefaults.songRequestChannelPointsCost,
            AppConstants.UserDefaults.songRequestRedemptionStatus,
            AppConstants.UserDefaults.twitchPendingImportedChannelName,
        ].forEach { defaults.removeObject(forKey: $0) }
    }

    // MARK: - attemptReactiveRefresh (persistence)

    func testAtomicDeviceGrantWriteFailurePreservesCompletePriorAccount() throws {
        let failingBackend = InspectableKeychainBackend()
        KeychainService.backend = failingBackend
        let prior = KeychainService.TwitchCredentialGrant(
            accessToken: "OLD_ACCESS",
            refreshToken: "OLD_REFRESH",
            username: "old_user",
            userID: "old_id",
            channelID: "old-channel"
        )
        try KeychainService.saveTwitchCredentialGrant(prior)
        let revision = TwitchCredentialStore.shared.supersede()
        failingBackend.failNextSave(
            for: KeychainService.twitchCredentialGrantAccount)

        XCTAssertThrowsError(
            try TwitchCredentialStore.shared.commitDeviceGrant(
                TwitchTokenResponse(
                    accessToken: "NEW_ACCESS",
                    refreshToken: "NEW_REFRESH",
                    expiresIn: nil
                ),
                expectedRevision: revision
            )
        )
        XCTAssertEqual(KeychainService.loadTwitchCredentialGrant(), prior)
        XCTAssertEqual(
            TwitchCredentialStore.shared.revision(
                matchingAccessToken: "OLD_ACCESS"),
            revision
        )
    }

    func testOAuthReplacementCancelRestoresOnlyCurrentValidationOwner() async throws {
        let prior = KeychainService.TwitchCredentialGrant(
            accessToken: "OLD_ACCESS",
            refreshToken: "OLD_REFRESH",
            username: "old_user",
            userID: "old_id",
            channelID: "old-channel"
        )
        try KeychainService.saveTwitchCredentialGrant(prior)

        let requestEntered = DispatchSemaphore(value: 0)
        let releaseRequest = DispatchSemaphore(value: 0)
        let auth = TwitchDeviceAuth(
            clientID: "client",
            scopes: AppConstants.Twitch.allScopes,
            session: MockURLProtocol.makeSession { request in
                requestEntered.signal()
                _ = releaseRequest.wait(timeout: .now() + 2)
                return (
                    MockURLProtocol.httpResponse(for: request, status: 503),
                    Data("temporary".utf8)
                )
            }
        )
        let cancellations = ThreadSafeBox(0)
        let restarts = ThreadSafeBox(0)
        let viewModel = TwitchViewModel(
            cancelTokenValidationSchedule: {
                cancellations.mutate { $0 += 1 }
            },
            restartTokenValidationSchedule: {
                restarts.mutate { $0 += 1 }
            },
            makeOAuthClient: { ("client", auth) }
        )

        viewModel.startOAuth()
        let flow = try XCTUnwrap(viewModel.oAuthTask)
        XCTAssertEqual(cancellations.value, 1)
        let requestDidStart = await waitForSemaphore(
            requestEntered, timeout: .now() + 2)
        XCTAssertTrue(requestDidStart)

        let cancellation = Task { @MainActor in
            await viewModel.cancelOAuth()
        }
        releaseRequest.signal()
        await cancellation.value
        await flow.value

        XCTAssertEqual(restarts.value, 1)
        XCTAssertEqual(KeychainService.loadTwitchCredentialGrant(), prior)
        XCTAssertEqual(viewModel.authState, .idle)
    }

    func testCancelOAuthWaitsForBlockedLeaveBeforeRestoringValidation() async throws {
        let prior = KeychainService.TwitchCredentialGrant(
            accessToken: "OLD_ACCESS",
            refreshToken: "OLD_REFRESH",
            username: "old_user",
            userID: "old_id")
        try KeychainService.saveTwitchCredentialGrant(prior)
        let gate = OAuthIdentityGate()
        let cancellations = ThreadSafeBox(0)
        let restarts = ThreadSafeBox(0)
        let cancellationFinished = ThreadSafeBox(false)
        let auth = TwitchDeviceAuth(
            clientID: "client",
            scopes: AppConstants.Twitch.allScopes,
            session: MockURLProtocol.makeSession { request in
                (
                    MockURLProtocol.httpResponse(for: request, status: 503),
                    Data("temporary".utf8))
            })
        let viewModel = TwitchViewModel(
            cancelTokenValidationSchedule: {
                cancellations.mutate { $0 += 1 }
            },
            restartTokenValidationSchedule: {
                restarts.mutate { $0 += 1 }
            },
            makeOAuthClient: { ("client", auth) },
            leaveAccountService: { _, _ in
                await gate.suspend()
                return false
            })

        viewModel.startOAuth()
        let leaveDidSuspend = await waitUntil { await gate.suspended }
        XCTAssertTrue(leaveDidSuspend)
        XCTAssertEqual(cancellations.value, 1)

        let cancellation = Task { @MainActor in
            await viewModel.cancelOAuth()
            cancellationFinished.value = true
        }
        await Task.yield()

        XCTAssertFalse(cancellationFinished.value)
        XCTAssertEqual(restarts.value, 0)
        await gate.resume()
        await cancellation.value

        XCTAssertTrue(cancellationFinished.value)
        XCTAssertEqual(restarts.value, 1)
        XCTAssertEqual(KeychainService.loadTwitchCredentialGrant(), prior)
        XCTAssertEqual(viewModel.authState, .idle)
        XCTAssertEqual(viewModel.statusMessage, "")
    }

    func testOAuthOwnerReleaseRestoresValidationBeforeTaskStarts() async throws {
        let prior = KeychainService.TwitchCredentialGrant(
            accessToken: "OLD_ACCESS",
            refreshToken: "OLD_REFRESH",
            username: "old_user",
            userID: "old_id"
        )
        try KeychainService.saveTwitchCredentialGrant(prior)
        let auth = TwitchDeviceAuth(
            clientID: "client",
            scopes: AppConstants.Twitch.allScopes,
            session: MockURLProtocol.makeSession { request in
                (
                    MockURLProtocol.httpResponse(for: request, status: 503),
                    Data("temporary".utf8)
                )
            }
        )
        let cancellations = ThreadSafeBox(0)
        let restarts = ThreadSafeBox(0)
        var viewModel: TwitchViewModel? = TwitchViewModel(
            cancelTokenValidationSchedule: {
                cancellations.set(cancellations.value + 1)
            },
            restartTokenValidationSchedule: {
                restarts.set(restarts.value + 1)
            },
            makeOAuthClient: { ("client", auth) }
        )
        weak var releasedViewModel = viewModel

        viewModel?.startOAuth()
        let flow = try XCTUnwrap(viewModel?.oAuthTask)
        XCTAssertEqual(cancellations.value, 1)
        viewModel = nil

        XCTAssertNil(releasedViewModel)
        await flow.value
        XCTAssertEqual(restarts.value, 1)
        XCTAssertEqual(KeychainService.loadTwitchCredentialGrant(), prior)
    }

    func testOAuthRequestFailureRestoresSurvivingGrantValidationOwner() async throws {
        let prior = KeychainService.TwitchCredentialGrant(
            accessToken: "OLD_ACCESS",
            refreshToken: "OLD_REFRESH",
            username: "old_user",
            userID: "old_id"
        )
        try KeychainService.saveTwitchCredentialGrant(prior)
        let auth = TwitchDeviceAuth(
            clientID: "client",
            scopes: AppConstants.Twitch.allScopes,
            session: MockURLProtocol.makeSession { request in
                (
                    MockURLProtocol.httpResponse(for: request, status: 503),
                    Data("temporary".utf8)
                )
            }
        )
        let cancellations = ThreadSafeBox(0)
        let restarts = ThreadSafeBox(0)
        let viewModel = TwitchViewModel(
            cancelTokenValidationSchedule: {
                cancellations.mutate { $0 += 1 }
            },
            restartTokenValidationSchedule: {
                restarts.mutate { $0 += 1 }
            },
            makeOAuthClient: { ("client", auth) }
        )

        viewModel.startOAuth()
        await viewModel.oAuthTask?.value

        XCTAssertEqual(cancellations.value, 1)
        XCTAssertEqual(restarts.value, 1)
        XCTAssertEqual(KeychainService.loadTwitchCredentialGrant(), prior)
        if case .error = viewModel.authState {
            // expected
        } else {
            XCTFail("Terminal device-code failure should remain visible")
        }
    }

    func testSupersededOAuthFlowCannotRestartValidationOverRetry() async throws {
        let prior = KeychainService.TwitchCredentialGrant(
            accessToken: "OLD_ACCESS",
            refreshToken: "OLD_REFRESH",
            username: "old_user",
            userID: "old_id"
        )
        try KeychainService.saveTwitchCredentialGrant(prior)

        let firstRequestEntered = DispatchSemaphore(value: 0)
        let releaseFirstRequest = DispatchSemaphore(value: 0)
        let firstAuth = TwitchDeviceAuth(
            clientID: "client",
            scopes: AppConstants.Twitch.allScopes,
            session: MockURLProtocol.makeSession { request in
                firstRequestEntered.signal()
                _ = releaseFirstRequest.wait(timeout: .now() + 2)
                return (
                    MockURLProtocol.httpResponse(for: request, status: 503),
                    Data("first".utf8)
                )
            }
        )
        let secondAuth = TwitchDeviceAuth(
            clientID: "client",
            scopes: AppConstants.Twitch.allScopes,
            session: MockURLProtocol.makeSession { request in
                (
                    MockURLProtocol.httpResponse(for: request, status: 503),
                    Data("second".utf8)
                )
            }
        )
        let factoryCalls = ThreadSafeBox(0)
        let cancellations = ThreadSafeBox(0)
        let restarts = ThreadSafeBox(0)
        let viewModel = TwitchViewModel(
            cancelTokenValidationSchedule: {
                cancellations.mutate { $0 += 1 }
            },
            restartTokenValidationSchedule: {
                restarts.mutate { $0 += 1 }
            },
            makeOAuthClient: {
                let call = factoryCalls.value
                factoryCalls.set(call + 1)
                return ("client", call == 0 ? firstAuth : secondAuth)
            }
        )

        viewModel.startOAuth()
        let firstFlow = try XCTUnwrap(viewModel.oAuthTask)
        let firstRequestDidStart = await waitForSemaphore(
            firstRequestEntered, timeout: .now() + 2)
        XCTAssertTrue(firstRequestDidStart)

        viewModel.startOAuth()
        let secondFlow = try XCTUnwrap(viewModel.oAuthTask)
        releaseFirstRequest.signal()
        await firstFlow.value
        await secondFlow.value

        XCTAssertEqual(cancellations.value, 2)
        XCTAssertEqual(restarts.value, 1)
        XCTAssertEqual(factoryCalls.value, 2)
        XCTAssertEqual(KeychainService.loadTwitchCredentialGrant(), prior)
    }

    func testSuccessfulOAuthFlowInstallsSingleValidationOwner() async throws {
        let requests = ThreadSafeBox(0)
        let auth = TwitchDeviceAuth(
            clientID: "client",
            scopes: AppConstants.Twitch.allScopes,
            session: MockURLProtocol.makeSession { request in
                requests.mutate { $0 += 1 }
                if request.url?.absoluteString == AppConstants.API.twitchOAuthDevice {
                    let json = #"""
                    {"device_code":"DEV","user_code":"CODE",
                     "verification_uri":"https://twitch.tv/activate",
                     "expires_in":600,"interval":1}
                    """#
                    return (
                        MockURLProtocol.httpResponse(for: request, status: 200),
                        Data(json.utf8)
                    )
                }
                let json = #"{"access_token":"ACCESS","refresh_token":"REFRESH"}"#
                return (
                    MockURLProtocol.httpResponse(for: request, status: 200),
                    Data(json.utf8)
                )
            }
        )
        let cancellations = ThreadSafeBox(0)
        let restarts = ThreadSafeBox(0)
        let viewModel = TwitchViewModel(
            cancelTokenValidationSchedule: {
                cancellations.mutate { $0 += 1 }
            },
            restartTokenValidationSchedule: {
                restarts.mutate { $0 += 1 }
            },
            makeOAuthClient: { ("client", auth) },
            resolveBotIdentity: { token, _, revision in
                _ = try TwitchCredentialStore.shared.commitIdentity(
                    username: "wolfwave",
                    userID: "broadcaster",
                    matchingAccessToken: token,
                    expectedRevision: revision
                )
            }
        )

        viewModel.startOAuth()
        let flow = try XCTUnwrap(viewModel.oAuthTask)
        await flow.value

        XCTAssertEqual(requests.value, 2)
        XCTAssertEqual(cancellations.value, 2)
        XCTAssertEqual(restarts.value, 1)
        XCTAssertEqual(KeychainService.loadTwitchToken(), "ACCESS")
        XCTAssertEqual(KeychainService.loadTwitchRefreshToken(), "REFRESH")
        XCTAssertEqual(viewModel.botUsername, "wolfwave")
        XCTAssertEqual(viewModel.authState, .idle)
    }

    func testOAuthCommitRestartsValidationBeforeIdentityFailure() async throws {
        enum IdentityFailure: Error {
            case injected
        }

        let restarts = ThreadSafeBox(0)
        let viewModel = TwitchViewModel(
            cancelTokenValidationSchedule: {},
            restartTokenValidationSchedule: {
                restarts.mutate { $0 += 1 }
            },
            resolveBotIdentity: { _, _, _ in
                throw IdentityFailure.injected
            }
        )
        let revision = TwitchCredentialStore.shared.supersede()
        await viewModel.handleOAuthSuccess(
            grant: TwitchTokenResponse(
                accessToken: "ACCESS",
                refreshToken: "REFRESH",
                expiresIn: nil
            ),
            clientID: "client",
            generation: 0,
            credentialRevision: revision
        )

        XCTAssertEqual(restarts.value, 1)
        XCTAssertEqual(KeychainService.loadTwitchToken(), "ACCESS")
        XCTAssertEqual(KeychainService.loadTwitchRefreshToken(), "REFRESH")
        if case .error = viewModel.authState {
            // expected
        } else {
            XCTFail("Identity failure should remain visible to the user")
        }
    }

    func testOAuthCommitKeepsValidationOwnerWhenIdentityTaskIsCancelled() async throws {
        let restarts = ThreadSafeBox(0)
        let gate = OAuthIdentityGate()
        let viewModel = TwitchViewModel(
            cancelTokenValidationSchedule: {},
            restartTokenValidationSchedule: {
                restarts.mutate { $0 += 1 }
            },
            resolveBotIdentity: { _, _, _ in
                await gate.suspend()
                try Task.checkCancellation()
            }
        )
        let revision = TwitchCredentialStore.shared.supersede()
        let completion = Task { @MainActor in
            await viewModel.handleOAuthSuccess(
                grant: TwitchTokenResponse(
                    accessToken: "ACCESS",
                    refreshToken: "REFRESH",
                    expiresIn: nil
                ),
                clientID: "client",
                generation: 0,
                credentialRevision: revision
            )
        }

        let identityLookupSuspended = await waitUntil { await gate.suspended }
        XCTAssertTrue(identityLookupSuspended)
        XCTAssertEqual(restarts.value, 1)
        XCTAssertEqual(KeychainService.loadTwitchToken(), "ACCESS")
        completion.cancel()
        await gate.resume()
        await completion.value

        XCTAssertEqual(restarts.value, 1)
        XCTAssertEqual(KeychainService.loadTwitchCredentialGrant().accessToken, "ACCESS")
        XCTAssertEqual(KeychainService.loadTwitchCredentialGrant().refreshToken, "REFRESH")
    }

    func testOAuthCommitFailureRestoresPriorGrantValidationOwner() async throws {
        let failingBackend = InspectableKeychainBackend()
        KeychainService.backend = failingBackend
        let prior = KeychainService.TwitchCredentialGrant(
            accessToken: "OLD_ACCESS",
            refreshToken: "OLD_REFRESH",
            username: "old_user",
            userID: "old_id",
            channelID: "old-channel"
        )
        try KeychainService.saveTwitchCredentialGrant(prior)
        UserDefaults.standard.set(
            "imported-channel",
            forKey: AppConstants.UserDefaults.twitchPendingImportedChannelName
        )
        failingBackend.failNextSave(
            for: KeychainService.twitchCredentialGrantAccount)
        let restarts = ThreadSafeBox(0)
        let identityCalls = ThreadSafeBox(0)
        let viewModel = TwitchViewModel(
            cancelTokenValidationSchedule: {},
            restartTokenValidationSchedule: {
                restarts.mutate { $0 += 1 }
            },
            resolveBotIdentity: { _, _, _ in
                identityCalls.mutate { $0 += 1 }
            }
        )
        let revision = TwitchCredentialStore.shared.supersede()

        await viewModel.handleOAuthSuccess(
            grant: TwitchTokenResponse(
                accessToken: "NEW_ACCESS",
                refreshToken: "NEW_REFRESH",
                expiresIn: nil
            ),
            clientID: "client",
            generation: 0,
            credentialRevision: revision
        )

        XCTAssertEqual(restarts.value, 1)
        XCTAssertEqual(identityCalls.value, 0)
        XCTAssertEqual(KeychainService.loadTwitchCredentialGrant(), prior)
        XCTAssertEqual(
            Preferences.pendingImportedTwitchChannelName,
            "imported-channel"
        )
    }

    func testOAuthCommitAtomicallyPromotesPendingImportedChannel() async throws {
        try KeychainService.saveTwitchCredentialGrant(
            .init(
                accessToken: "OLD_ACCESS",
                refreshToken: "OLD_REFRESH",
                username: "old_user",
                userID: "old_id",
                channelID: "old-channel"
            )
        )
        UserDefaults.standard.set(
            "  Imported-Channel  ",
            forKey: AppConstants.UserDefaults.twitchPendingImportedChannelName
        )
        let viewModel = TwitchViewModel(
            cancelTokenValidationSchedule: {},
            restartTokenValidationSchedule: {},
            resolveBotIdentity: { token, _, revision in
                guard try TwitchCredentialStore.shared.commitIdentity(
                    username: "new_user",
                    userID: "new_id",
                    matchingAccessToken: token,
                    expectedRevision: revision
                ) else {
                    throw CancellationError()
                }
            }
        )
        viewModel.channelID = "visible-draft"
        let revision = TwitchCredentialStore.shared.supersede()

        await viewModel.handleOAuthSuccess(
            grant: .init(
                accessToken: "NEW_ACCESS",
                refreshToken: "NEW_REFRESH",
                expiresIn: nil
            ),
            clientID: "client",
            generation: 0,
            credentialRevision: revision
        )

        XCTAssertEqual(
            try KeychainService.loadTwitchCredentialGrantChecked(),
            .init(
                accessToken: "NEW_ACCESS",
                refreshToken: "NEW_REFRESH",
                username: "new_user",
                userID: "new_id",
                channelID: "imported-channel"
            )
        )
        XCTAssertEqual(viewModel.channelID, "imported-channel")
        XCTAssertEqual(Preferences.pendingImportedTwitchChannelName, "")
    }

    func testKeychainReadFailureConservativelyRestoresValidationOwner() throws {
        let failingBackend = InspectableKeychainBackend()
        KeychainService.backend = failingBackend
        try KeychainService.saveTwitchCredentialGrant(
            .init(accessToken: "ACCESS", channelID: "channel")
        )
        let cancellations = ThreadSafeBox(0)
        let restarts = ThreadSafeBox(0)
        let viewModel = TwitchViewModel(
            cancelTokenValidationSchedule: {
                cancellations.mutate { $0 += 1 }
            },
            restartTokenValidationSchedule: {
                restarts.mutate { $0 += 1 }
            }
        )
        failingBackend.failNextLoad(
            for: KeychainService.twitchCredentialGrantAccount
        )

        viewModel.restoreTokenValidationScheduleForStoredCredential()

        XCTAssertEqual(cancellations.value, 0)
        XCTAssertEqual(restarts.value, 1)
    }

    func testJoinTeardownFailureKeepsCanonicalChannelAndSignedInUI() async throws {
        try KeychainService.saveTwitchCredentialGrant(
            .init(
                accessToken: "ACCESS",
                refreshToken: "REFRESH",
                username: "bot",
                userID: "bot-id",
                channelID: "old-channel"
            )
        )
        let validationRequests = ThreadSafeBox(0)
        let service = TwitchChatService(
            helixHTTPClient: HTTPClient(
                session: MockURLProtocol.makeSession { request in
                    validationRequests.mutate { $0 += 1 }
                    let body = #"{"data":[{"id":"new-id","login":"new-channel","display_name":"New Channel"}]}"#
                    return (
                        MockURLProtocol.httpResponse(for: request, status: 200),
                        Data(body.utf8)
                    )
                }
            )
        )
        let teardownAttempts = ThreadSafeBox(0)
        let viewModel = TwitchViewModel(
            twitchClientIDProvider: { "client" },
            leaveAccountService: { _, _ in
                teardownAttempts.mutate { $0 += 1 }
                return false
            }
        )
        viewModel.twitchService = service
        viewModel.credentialsSaved = true
        viewModel.channelID = "new-channel"

        viewModel.joinChannel()
        let finished = await waitUntil {
            await MainActor.run {
                !viewModel.isConnecting
                    && viewModel.statusMessage.contains("safely disconnect")
            }
        }

        XCTAssertTrue(finished)
        XCTAssertEqual(validationRequests.value, 1)
        XCTAssertEqual(teardownAttempts.value, 1)
        XCTAssertEqual(viewModel.authState, .idle)
        XCTAssertEqual(viewModel.channelValidationState, .error("Could not safely disconnect"))
        XCTAssertEqual(
            try KeychainService.loadTwitchCredentialGrantChecked().channelID,
            "old-channel"
        )
    }

    func testInvalidJoinDraftNeverTearsDownOrCommitsCanonicalChannel() async throws {
        try KeychainService.saveTwitchCredentialGrant(
            .init(
                accessToken: "ACCESS",
                refreshToken: "REFRESH",
                username: "bot",
                userID: "bot-id",
                channelID: "old-channel"
            )
        )
        let service = TwitchChatService(
            helixHTTPClient: HTTPClient(
                session: MockURLProtocol.makeSession { request in
                    (
                        MockURLProtocol.httpResponse(for: request, status: 200),
                        Data(#"{"data":[]}"#.utf8)
                    )
                }
            )
        )
        let teardownAttempts = ThreadSafeBox(0)
        let viewModel = TwitchViewModel(
            twitchClientIDProvider: { "client" },
            leaveAccountService: { _, _ in
                teardownAttempts.mutate { $0 += 1 }
                return true
            }
        )
        viewModel.twitchService = service
        viewModel.credentialsSaved = true
        viewModel.channelID = "missing-channel"

        viewModel.joinChannel()
        let finished = await waitUntil {
            await MainActor.run {
                !viewModel.isConnecting
                    && viewModel.channelValidationState == .invalid
            }
        }

        XCTAssertTrue(finished)
        XCTAssertEqual(teardownAttempts.value, 0)
        XCTAssertEqual(viewModel.channelValidationState, .invalid)
        XCTAssertTrue(viewModel.statusMessage.contains("not found"))
        XCTAssertEqual(
            try KeychainService.loadTwitchCredentialGrantChecked().channelID,
            "old-channel"
        )
    }

    func testManualCredentialWriteFailureRestoresPriorGrantValidationOwner() async throws {
        let failingBackend = InspectableKeychainBackend()
        KeychainService.backend = failingBackend
        let prior = KeychainService.TwitchCredentialGrant(
            accessToken: "OLD_ACCESS",
            refreshToken: "OLD_REFRESH",
            username: "old_user",
            userID: "old_id"
        )
        try KeychainService.saveTwitchCredentialGrant(prior)
        failingBackend.failNextSave(
            for: KeychainService.twitchCredentialGrantAccount)
        let restarts = ThreadSafeBox(0)
        let viewModel = TwitchViewModel(
            cancelTokenValidationSchedule: {},
            restartTokenValidationSchedule: {
                restarts.mutate { $0 += 1 }
            }
        )
        viewModel.oauthToken = "NEW_ACCESS"
        viewModel.channelID = "new-channel"

        await viewModel.saveCredentials()

        XCTAssertEqual(restarts.value, 1)
        XCTAssertEqual(KeychainService.loadTwitchCredentialGrant(), prior)
        XCTAssertTrue(viewModel.statusMessage.contains("Failed to save"))
    }

    func testReactiveRefreshPersistsNewTokens() async throws {
        await TwitchTokenRefresher.invalidateSession()
        try KeychainService.saveTwitchCredentialGrant(
            .init(accessToken: "OLD_AT", refreshToken: "OLD_RT", channelID: "channel")
        )
        handlerStore.handler = { request in
            let json = #"{"access_token":"NEW_AT","refresh_token":"NEW_RT"}"#
            return (MockURLProtocol.httpResponse(for: request, status: 200), Data(json.utf8))
        }

        let result = try await TwitchTokenRefresher.attemptReactiveRefresh(
            clientID: "test-client",
            session: MockURLProtocol.makeSession(handlerStore: handlerStore),
            maxTransientAttempts: 1
        )

        XCTAssertEqual(result, .refreshed("NEW_AT"))
        XCTAssertEqual(KeychainService.loadTwitchToken(), "NEW_AT")
        XCTAssertEqual(KeychainService.loadTwitchRefreshToken(), "NEW_RT")
        XCTAssertEqual(KeychainService.loadTwitchChannelID(), "channel")
    }

    func testConcurrentRefreshCallersShareOneNetworkFlight() async throws {
        await TwitchTokenRefresher.invalidateSession()
        try KeychainService.saveTwitchCredentialGrant(
            .init(accessToken: "OLD_AT", refreshToken: "OLD_RT")
        )
        let requestEntered = DispatchSemaphore(value: 0)
        let releaseResponse = DispatchSemaphore(value: 0)
        let secondJoined = DispatchSemaphore(value: 0)
        let attempts = ThreadSafeBox(0)
        let handler: MockURLProtocol.Handler = { request in
            attempts.mutate { $0 += 1 }
            requestEntered.signal()
            guard releaseResponse.wait(timeout: .now() + 2) == .success else {
                throw URLError(.timedOut)
            }
            return (
                MockURLProtocol.httpResponse(for: request, status: 200),
                Data(#"{"access_token":"NEW_AT","refresh_token":"NEW_RT"}"#.utf8)
            )
        }
        let session = MockURLProtocol.makeSession(handler: handler)

        let first = Task {
            try await TwitchTokenRefresher.attemptReactiveRefresh(
                clientID: "test-client",
                session: session
            )
        }
        let entered = await waitForSemaphore(
            requestEntered,
            timeout: .now() + 2
        )
        XCTAssertTrue(entered)

        let second = Task {
            try await TwitchTokenRefresher.attemptReactiveRefresh(
                clientID: "test-client",
                session: session,
                onJoinedExistingFlight: { secondJoined.signal() }
            )
        }
        let joined = await waitForSemaphore(
            secondJoined,
            timeout: .now() + 2
        )
        XCTAssertTrue(joined)
        releaseResponse.signal()

        let firstResult = try await first.value
        let secondResult = try await second.value
        XCTAssertEqual(firstResult, .refreshed("NEW_AT"))
        XCTAssertEqual(secondResult, .refreshed("NEW_AT"))
        XCTAssertEqual(attempts.value, 1)
    }

    func testStaleRefreshResponseCannotOverwriteReplacementAccount() async throws {
        await TwitchTokenRefresher.invalidateSession()
        try KeychainService.saveTwitchCredentialGrant(
            .init(accessToken: "OLD_AT", refreshToken: "OLD_RT")
        )
        let expected = try XCTUnwrap(
            TwitchCredentialStore.shared
                .connectionSnapshot(
                    matchingAccessToken: "OLD_AT"
                )?.accessExpectation
        )
        let requestEntered = DispatchSemaphore(value: 0)
        let releaseResponse = DispatchSemaphore(value: 0)
        let handler: MockURLProtocol.Handler = { request in
            requestEntered.signal()
            guard releaseResponse.wait(timeout: .now() + 2) == .success else {
                throw URLError(.timedOut)
            }
            return (
                MockURLProtocol.httpResponse(for: request, status: 200),
                Data(#"{"access_token":"STALE_AT","refresh_token":"STALE_RT"}"#.utf8)
            )
        }

        let session = MockURLProtocol.makeSession(handler: handler)
        let refresh = Task {
            try await TwitchTokenRefresher.attemptReactiveRefresh(
                clientID: "test-client",
                expected: expected,
                session: session
            )
        }
        let entered = await waitForSemaphore(
            requestEntered,
            timeout: .now() + 2
        )
        XCTAssertTrue(entered)

        let replacementRevision = TwitchCredentialStore.shared.supersede()
        let replacement = TwitchTokenResponse(
            accessToken: "NEW_ACCOUNT_AT",
            refreshToken: "NEW_ACCOUNT_RT",
            expiresIn: nil
        )
        XCTAssertTrue(
            try TwitchCredentialStore.shared.commitDeviceGrant(
                replacement,
                expectedRevision: replacementRevision
            )
        )
        releaseResponse.signal()

        let result = try await refresh.value
        XCTAssertEqual(result, .superseded)
        XCTAssertEqual(KeychainService.loadTwitchToken(), "NEW_ACCOUNT_AT")
        XCTAssertEqual(KeychainService.loadTwitchRefreshToken(), "NEW_ACCOUNT_RT")
    }

    func testReactiveRefreshHonorsRetryAfterThenSucceeds() async throws {
        await TwitchTokenRefresher.invalidateSession()
        try KeychainService.saveTwitchCredentialGrant(
            .init(accessToken: "OLD_AT", refreshToken: "OLD_RT")
        )
        let attempts = ThreadSafeBox(0)
        let delays = ThreadSafeBox<[Duration]>([])
        let handler: MockURLProtocol.Handler = { request in
            let attempt = attempts.value
            attempts.value = attempt + 1
            if attempt == 0 {
                return (
                    MockURLProtocol.httpResponse(
                        for: request, status: 429, headers: ["Retry-After": "12"]),
                    Data())
            }
            return (
                MockURLProtocol.httpResponse(for: request, status: 200),
                Data(#"{"access_token":"NEW_AT","refresh_token":"NEW_RT"}"#.utf8))
        }

        let result = try await TwitchTokenRefresher.attemptReactiveRefresh(
            clientID: "test-client",
            session: MockURLProtocol.makeSession(handler: handler),
            sleep: { delay in delays.mutate { $0.append(delay) } })

        XCTAssertEqual(result, .refreshed("NEW_AT"))
        XCTAssertEqual(delays.value, [.seconds(12)])
    }

    func testReactiveRefreshDoesNotRetryPermanentStatus() async throws {
        await TwitchTokenRefresher.invalidateSession()
        try KeychainService.saveTwitchCredentialGrant(
            .init(accessToken: "OLD_AT", refreshToken: "OLD_RT")
        )
        let attempts = ThreadSafeBox(0)
        let delays = ThreadSafeBox<[Duration]>([])
        handlerStore.handler = { request in
            attempts.mutate { $0 += 1 }
            return (MockURLProtocol.httpResponse(for: request, status: 403), Data())
        }

        let result = try await TwitchTokenRefresher.attemptReactiveRefresh(
            clientID: "test-client",
            session: MockURLProtocol.makeSession(handlerStore: handlerStore),
            sleep: { delay in delays.mutate { $0.append(delay) } })

        XCTAssertEqual(result, .invalid)
        XCTAssertEqual(attempts.value, 1)
        XCTAssertTrue(delays.value.isEmpty)
        XCTAssertEqual(KeychainService.loadTwitchRefreshToken(), "OLD_RT")
    }

    func testMalformedRefreshSuccessDoesNotReplaceStoredGrant() async throws {
        await TwitchTokenRefresher.invalidateSession()
        try KeychainService.saveTwitchCredentialGrant(
            .init(accessToken: "OLD_AT", refreshToken: "OLD_RT")
        )
        handlerStore.handler = { request in
            (
                MockURLProtocol.httpResponse(for: request, status: 200),
                Data(#"{"access_token":"NEW_AT"}"#.utf8))
        }

        let result = try await TwitchTokenRefresher.attemptReactiveRefresh(
            clientID: "test-client",
            session: MockURLProtocol.makeSession(handlerStore: handlerStore))

        XCTAssertEqual(result, .invalid)
        XCTAssertEqual(KeychainService.loadTwitchToken(), "OLD_AT")
        XCTAssertEqual(KeychainService.loadTwitchRefreshToken(), "OLD_RT")
    }

    func testReactiveRefreshReturnsInvalidWithoutStoredRefreshToken() async throws {
        await TwitchTokenRefresher.invalidateSession()
        XCTAssertNil(KeychainService.loadTwitchRefreshToken())
        let result = try await TwitchTokenRefresher.attemptReactiveRefresh(
            clientID: "test-client"
        )
        XCTAssertEqual(result, .invalid)
    }

    func testReactiveRefreshReturnsInvalidWithEmptyClientID() async throws {
        await TwitchTokenRefresher.invalidateSession()
        try KeychainService.saveTwitchCredentialGrant(
            .init(accessToken: "AT", refreshToken: "RT")
        )
        let result = try await TwitchTokenRefresher.attemptReactiveRefresh(clientID: "")
        XCTAssertEqual(result, .invalid)
    }

    func testStaleExpectedCredentialDoesNotStartReplacementAccountRefresh() async throws {
        await TwitchTokenRefresher.invalidateSession()
        try KeychainService.saveTwitchCredentialGrant(
            .init(accessToken: "OLD_AT", refreshToken: "OLD_RT")
        )
        let expected = try XCTUnwrap(
            TwitchCredentialStore.shared
                .connectionSnapshot(
                    matchingAccessToken: "OLD_AT"
                )?.accessExpectation
        )

        let replacementRevision = TwitchCredentialStore.shared.supersede()
        XCTAssertTrue(
            try TwitchCredentialStore.shared.commitDeviceGrant(
                TwitchTokenResponse(
                    accessToken: "NEW_ACCOUNT_AT",
                    refreshToken: "NEW_ACCOUNT_RT",
                    expiresIn: nil
                ),
                expectedRevision: replacementRevision
            )
        )

        let attempts = ThreadSafeBox(0)
        let result = try await TwitchTokenRefresher.attemptReactiveRefresh(
            clientID: "test-client",
            expected: expected,
            session: MockURLProtocol.makeSession { request in
                attempts.mutate { $0 += 1 }
                return (
                    MockURLProtocol.httpResponse(for: request, status: 500),
                    Data()
                )
            }
        )

        XCTAssertEqual(result, .superseded)
        XCTAssertEqual(attempts.value, 0)
        XCTAssertEqual(KeychainService.loadTwitchToken(), "NEW_ACCOUNT_AT")
        XCTAssertEqual(KeychainService.loadTwitchRefreshToken(), "NEW_ACCOUNT_RT")
    }

    func testHourlyRotationAdoptsActiveAndPendingReconnectTokens() async throws {
        await TwitchTokenRefresher.invalidateSession()
        try KeychainService.saveTwitchCredentialGrant(
            .init(
                accessToken: "OLD_AT",
                refreshToken: "OLD_RT",
                username: "wolf",
                userID: "user"
            )
        )
        let rejected = try XCTUnwrap(
            TwitchCredentialStore.shared
                .connectionSnapshot(
                    matchingAccessToken: "OLD_AT"
                )?.accessExpectation
        )
        XCTAssertTrue(
            try TwitchCredentialStore.shared.commitRefreshGrant(
                TwitchTokenResponse(
                    accessToken: "NEW_AT",
                    refreshToken: "NEW_RT",
                    expiresIn: nil
                ),
                replacing: "OLD_RT",
                expected: rejected
            )
        )
        let refreshed = rejected.replacingAccessToken("NEW_AT")

        let staleReconnectCancelled = ThreadSafeBox(false)
        let service = TwitchChatService()
        await service.installRefreshAdoptionStateForTesting(
            token: "OLD_AT",
            staleReconnectCancelled: staleReconnectCancelled
        )

        let adopted = await service.adoptRefreshedAccessCredential(
            refreshed,
            replacing: rejected
        )
        let actorState = await service.refreshActorStateForTesting()
        let cancellationObserved = await waitUntil {
            staleReconnectCancelled.value
        }
        await service.cancelRefreshReconnectForTesting()

        XCTAssertTrue(adopted)
        XCTAssertEqual(actorState.oauthToken, "NEW_AT")
        XCTAssertEqual(actorState.reconnectToken, "NEW_AT")
        XCTAssertTrue(cancellationObserved)
    }

    func testStaleHourlyRotationCannotMutateReplacementActorState() async throws {
        try KeychainService.saveTwitchCredentialGrant(
            .init(accessToken: "OLD_AT", refreshToken: "OLD_RT")
        )
        let rejected = try XCTUnwrap(
            TwitchCredentialStore.shared
                .connectionSnapshot(
                    matchingAccessToken: "OLD_AT"
                )?.accessExpectation
        )

        let replacementRevision = TwitchCredentialStore.shared.supersede()
        XCTAssertTrue(
            try TwitchCredentialStore.shared.commitDeviceGrant(
                TwitchTokenResponse(
                    accessToken: "ACCOUNT_B_AT",
                    refreshToken: "ACCOUNT_B_RT",
                    expiresIn: nil
                ),
                expectedRevision: replacementRevision
            )
        )

        let service = TwitchChatService()
        await service.installRefreshAdoptionStateForTesting(token: "OLD_AT")
        let adopted = await service.adoptRefreshedAccessCredential(
            rejected.replacingAccessToken("STALE_ROTATION"),
            replacing: rejected
        )
        let actorState = await service.refreshActorStateForTesting()

        XCTAssertFalse(adopted)
        XCTAssertEqual(actorState.oauthToken, "OLD_AT")
        XCTAssertEqual(actorState.reconnectToken, "OLD_AT")
    }

    func testDefaultRefreshAdoptionRetiresLiveSocketAndReconnectsWithNewToken()
        async throws {
        try KeychainService.saveTwitchCredentialGrant(
            .init(
                accessToken: "OLD_AT",
                refreshToken: "OLD_RT",
                username: "bot",
                userID: "bot-user"))
        let rejected = try XCTUnwrap(
            TwitchCredentialStore.shared.connectionSnapshot(
                matchingAccessToken: "OLD_AT")?.accessExpectation)
        XCTAssertTrue(
            try TwitchCredentialStore.shared.commitRefreshGrant(
                TwitchTokenResponse(
                    accessToken: "NEW_AT",
                    refreshToken: "NEW_RT",
                    expiresIn: nil),
                replacing: "OLD_RT",
                expected: rejected))
        let refreshed = rejected.replacingAccessToken("NEW_AT")

        let socketSession = URLSession(configuration: .ephemeral)
        defer { socketSession.invalidateAndCancel() }
        let source = socketSession.webSocketTask(
            with: try XCTUnwrap(URL(string: "wss://eventsub.wss.twitch.tv/source")))
        let target = socketSession.webSocketTask(
            with: try XCTUnwrap(URL(string: "wss://eventsub.wss.twitch.tv/target")))
        let helixAuthorization = ThreadSafeBox<[String]>([])
        let factoryCalls = ThreadSafeBox(0)
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "wolfwave-live-adoption-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let service = TwitchChatService(
            helixHTTPClient: HTTPClient(
                session: MockURLProtocol.makeSession { request in
                    helixAuthorization.mutate {
                        $0.append(
                            request.value(forHTTPHeaderField: "Authorization") ?? "")
                    }
                    return (
                        MockURLProtocol.httpResponse(for: request, status: 200),
                        Data(
                            #"{"data":[{"id":"broadcaster","login":"channel","display_name":"Channel"}]}"#.utf8))
                }),
            redemptionResolutionOutbox: TwitchRedemptionResolutionOutbox(
                fileURL: directory.appending(path: "outbox.json")),
            eventSubWebSocketFactory: { _ in
                factoryCalls.mutate { $0 += 1 }
                return target
            },
            eventSubWebSocketResume: { _ in },
            eventSubWebSocketReceive: { _ in
                try await Task.sleep(for: .seconds(3_600))
                throw CancellationError()
            })
        _ = await service.installLiveChatSessionForTesting(
            source,
            actorToken: "OLD_AT")

        let adopted = await service.adoptRefreshedAccessCredential(
            refreshed,
            replacing: rejected)
        let reconnected = await waitUntil(timeout: .seconds(4)) {
            factoryCalls.value == 1
        }

        XCTAssertTrue(adopted)
        XCTAssertTrue(reconnected)
        XCTAssertEqual(helixAuthorization.value, ["Bearer NEW_AT"])
        let transport = await service.eventSubTransportSnapshotForTesting(
            source: source,
            target: target)
        XCTAssertFalse(transport.sourceIsCurrent)
        XCTAssertTrue(transport.targetIsCurrent)
        let actorState = await service.refreshActorStateForTesting()
        XCTAssertEqual(actorState.oauthToken, "NEW_AT")
        XCTAssertEqual(actorState.reconnectToken, "NEW_AT")
        await service.leaveChannel()
    }

    #if DEBUG
    func testChatSubscription401AdoptsStoredSameBotRotationAndReconnects()
        async throws {
        Preferences.setTwitchReauthNeeded(false)
        defer { Preferences.setTwitchReauthNeeded(false) }
        try KeychainService.saveTwitchCredentialGrant(
            .init(
                accessToken: "NEW_AT",
                refreshToken: "NEW_RT",
                username: "bot",
                userID: "bot-user"))

        let socketSession = URLSession(configuration: .ephemeral)
        defer { socketSession.invalidateAndCancel() }
        let source = socketSession.webSocketTask(
            with: try XCTUnwrap(URL(string: "wss://eventsub.wss.twitch.tv/source")))
        let target = socketSession.webSocketTask(
            with: try XCTUnwrap(URL(string: "wss://eventsub.wss.twitch.tv/target")))
        let subscriptionAuthorization = ThreadSafeBox<[String]>([])
        let helixAuthorization = ThreadSafeBox<[String]>([])
        let factoryCalls = ThreadSafeBox(0)
        let eventSubClient = HTTPClient(
            session: MockURLProtocol.makeSession { request in
                subscriptionAuthorization.mutate {
                    $0.append(request.value(forHTTPHeaderField: "Authorization") ?? "")
                }
                return (
                    MockURLProtocol.httpResponse(for: request, status: 401),
                    Data("unauthorized".utf8))
            })
        let helixClient = HTTPClient(
            session: MockURLProtocol.makeSession { request in
                helixAuthorization.mutate {
                    $0.append(request.value(forHTTPHeaderField: "Authorization") ?? "")
                }
                return (
                    MockURLProtocol.httpResponse(for: request, status: 200),
                    Data(
                        #"{"data":[{"id":"broadcaster","login":"channel","display_name":"Channel"}]}"#.utf8))
            })
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "wolfwave-eventsub-chat-rotation-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let service = TwitchChatService(
            eventSubHTTPClient: eventSubClient,
            helixHTTPClient: helixClient,
            redemptionResolutionOutbox: TwitchRedemptionResolutionOutbox(
                fileURL: directory.appending(path: "outbox.json")),
            eventSubWebSocketFactory: { _ in
                factoryCalls.mutate { $0 += 1 }
                return target
            },
            eventSubWebSocketResume: { _ in },
            eventSubWebSocketReceive: { _ in
                try await Task.sleep(for: .seconds(3_600))
                throw CancellationError()
            })
        let context = await service.installLiveChatSessionForTesting(
            source,
            actorToken: "OLD_AT")

        let subscribed = await service.subscribeToChannelChatMessageForTesting(
            receiveContext: context)
        let reconnected = await waitUntil(timeout: .seconds(4)) {
            factoryCalls.value == 1
        }

        XCTAssertFalse(subscribed)
        XCTAssertTrue(reconnected)
        XCTAssertEqual(subscriptionAuthorization.value, ["Bearer OLD_AT"])
        XCTAssertEqual(helixAuthorization.value, ["Bearer NEW_AT"])
        let transport = await service.eventSubTransportSnapshotForTesting(
            source: source,
            target: target)
        XCTAssertFalse(transport.sourceIsCurrent)
        XCTAssertTrue(transport.targetIsCurrent)
        let actorState = await service.refreshActorStateForTesting()
        XCTAssertEqual(actorState.oauthToken, "NEW_AT")
        XCTAssertEqual(actorState.reconnectToken, "NEW_AT")
        XCTAssertFalse(Preferences.twitchReauthNeeded)
        await service.leaveChannel()
    }

    func testChatSubscription401RejectsStoredDifferentUserWithoutReconnect()
        async throws {
        Preferences.setTwitchReauthNeeded(false)
        defer { Preferences.setTwitchReauthNeeded(false) }
        try KeychainService.saveTwitchCredentialGrant(
            .init(
                accessToken: "OTHER_AT",
                refreshToken: "OTHER_RT",
                username: "other",
                userID: "other-user"))

        let socketSession = URLSession(configuration: .ephemeral)
        defer { socketSession.invalidateAndCancel() }
        let source = socketSession.webSocketTask(
            with: try XCTUnwrap(URL(string: "wss://eventsub.wss.twitch.tv/source")))
        let target = socketSession.webSocketTask(
            with: try XCTUnwrap(URL(string: "wss://eventsub.wss.twitch.tv/target")))
        let factoryCalls = ThreadSafeBox(0)
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "wolfwave-eventsub-chat-account-switch-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let service = TwitchChatService(
            eventSubHTTPClient: HTTPClient(
                session: MockURLProtocol.makeSession { request in
                    return (
                        MockURLProtocol.httpResponse(for: request, status: 401),
                        Data("unauthorized".utf8))
                }),
            redemptionResolutionOutbox: TwitchRedemptionResolutionOutbox(
                fileURL: directory.appending(path: "outbox.json")),
            eventSubWebSocketFactory: { _ in
                factoryCalls.mutate { $0 += 1 }
                return target
            },
            eventSubWebSocketResume: { _ in },
            eventSubWebSocketReceive: { _ in
                try await Task.sleep(for: .seconds(3_600))
                throw CancellationError()
            })
        let context = await service.installLiveChatSessionForTesting(
            source,
            actorToken: "OLD_AT")

        let subscribed = await service.subscribeToChannelChatMessageForTesting(
            receiveContext: context)

        XCTAssertFalse(subscribed)
        XCTAssertEqual(factoryCalls.value, 0)
        let transport = await service.eventSubTransportSnapshotForTesting(
            source: source,
            target: target)
        XCTAssertFalse(transport.sourceIsCurrent)
        XCTAssertFalse(transport.targetIsCurrent)
        XCTAssertFalse(transport.hasReconnectTask)
        let actorState = await service.refreshActorStateForTesting()
        XCTAssertEqual(actorState.oauthToken, "OLD_AT")
        XCTAssertEqual(actorState.reconnectToken, "OLD_AT")
        XCTAssertFalse(Preferences.twitchReauthNeeded)
        await service.leaveChannel()
    }
    #endif

}
