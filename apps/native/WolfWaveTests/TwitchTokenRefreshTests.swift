//
//  TwitchTokenRefreshTests.swift
//  WolfWave
//
//  Created by Nathanial Henniges on 2026-06-06.
//  Copyright © 2026 MrDemonWolf, Inc. All rights reserved.
//

import XCTest

@testable import WolfWave

// MARK: - TwitchTokenRefreshTests

/// Covers the refresh-token resilience added in B3:
/// - `TwitchDeviceAuth.parseTokenResponse` (pure parse, with/without refresh).
/// - `refreshAccessToken` over `grant_type=refresh_token` (success + failure),
///   driven by `MockURLProtocol`.
/// - `TwitchTokenRefresher.attemptReactiveRefresh` persisting the new tokens via
///   the injectable in-memory Keychain backend (never the real Keychain).
///
/// The live socket orchestration around the refresh is not integration-tested
/// here; a second 401 requests re-auth while transient failures keep backing off.
@MainActor
final class TwitchTokenRefreshTests: XCTestCase {

    private var previousBackend: KeychainBackend!
    private var backend: InMemoryKeychainBackend!
    private let handlerStore = MockURLProtocol.HandlerStore()

    override func setUp() async throws {
        try await super.setUp()
        handlerStore.handler = nil
        Self.resetRedemptionDefaults()
        await SharedTestStateIsolation.acquireAsync()
        previousBackend = KeychainService.backend
        backend = InMemoryKeychainBackend()
        KeychainService.backend = backend
    }

    override func tearDown() async throws {
        Self.resetRedemptionDefaults()
        handlerStore.handler = nil
        KeychainService.backend = previousBackend
        SharedTestStateIsolation.release()
        try await super.tearDown()
    }

    nonisolated private static func resetRedemptionDefaults() {
        let defaults = DefaultsStore.store
        [
            AppConstants.UserDefaults.songRequestEnabled,
            AppConstants.UserDefaults.songRequestChannelPointsEnabled,
            AppConstants.UserDefaults.songRequestBitsEnabled,
            AppConstants.UserDefaults.songRequestChannelPointsRewardID,
            AppConstants.UserDefaults.songRequestChannelPointsRewardIdentity,
            AppConstants.UserDefaults.songRequestChannelPointsCost,
            AppConstants.UserDefaults.songRequestRedemptionStatus,
        ].forEach { defaults.removeObject(forKey: $0) }
    }

    private func storeManagedRewardIdentity(
        rewardID: String,
        broadcasterID: String = "broadcaster"
    ) {
        XCTAssertTrue(
            TwitchManagedRewardStore.store(
                .init(
                    rewardID: rewardID,
                    broadcasterID: broadcasterID),
                replacing: TwitchManagedRewardStore.snapshot()))
    }

    private func enableManagedReward(rewardID: String) {
        DefaultsStore.store.set(true, forKey: AppConstants.UserDefaults.songRequestEnabled)
        DefaultsStore.store.set(
            true,
            forKey: AppConstants.UserDefaults.songRequestChannelPointsEnabled)
        DefaultsStore.store.set(
            false,
            forKey: AppConstants.UserDefaults.songRequestBitsEnabled)
        storeManagedRewardIdentity(rewardID: rewardID)
    }

    nonisolated private static func emptyUnfulfilledRedemptionsResponse(
        for request: URLRequest
    ) -> (HTTPURLResponse, Data)? {
        guard request.httpMethod == "GET",
              request.url?.path.hasSuffix("/redemptions") == true else {
            return nil
        }
        return (
            MockURLProtocol.httpResponse(for: request, status: 200),
            Data(#"{"data":[],"pagination":{}}"#.utf8))
    }

    private func makeAuth(clientID: String = "test-client") -> TwitchDeviceAuth {
        TwitchDeviceAuth(
            clientID: clientID,
            scopes: ["user:read:chat"],
            session: MockURLProtocol.makeSession(handlerStore: handlerStore)
        )
    }

    // MARK: - parseTokenResponse

    func testParseTokenResponseWithRefreshAndExpiry() {
        let json = #"{"access_token":"AT","refresh_token":"RT","expires_in":14400}"#
        let parsed = TwitchDeviceAuth.parseTokenResponse(Data(json.utf8))
        XCTAssertEqual(parsed?.accessToken, "AT")
        XCTAssertEqual(parsed?.refreshToken, "RT")
        XCTAssertEqual(parsed?.expiresIn, 14400)
    }

    func testParseTokenResponseMissingRefreshIsNil() {
        let json = #"{"access_token":"AT"}"#
        let parsed = TwitchDeviceAuth.parseTokenResponse(Data(json.utf8))
        XCTAssertEqual(parsed?.accessToken, "AT")
        XCTAssertNil(parsed?.refreshToken)
        XCTAssertNil(parsed?.expiresIn)
    }

    func testParseTokenResponseEmptyRefreshTreatedAsNil() {
        let json = #"{"access_token":"AT","refresh_token":""}"#
        XCTAssertNil(TwitchDeviceAuth.parseTokenResponse(Data(json.utf8))?.refreshToken)
    }

    func testParseTokenResponseMissingAccessTokenReturnsNil() {
        let json = #"{"refresh_token":"RT"}"#
        XCTAssertNil(TwitchDeviceAuth.parseTokenResponse(Data(json.utf8)))
    }

    func testParseTokenResponseGarbageReturnsNil() {
        XCTAssertNil(TwitchDeviceAuth.parseTokenResponse(Data("not json".utf8)))
    }

    // MARK: - refreshAccessToken

    func testRefreshAccessTokenSuccess() async throws {
        handlerStore.handler = { request in
            let json = #"{"access_token":"NEW_AT","refresh_token":"NEW_RT","expires_in":14400}"#
            return (MockURLProtocol.httpResponse(for: request, status: 200), Data(json.utf8))
        }

        let response = try await makeAuth().refreshAccessToken(refreshToken: "OLD_RT")
        XCTAssertEqual(response.accessToken, "NEW_AT")
        XCTAssertEqual(response.refreshToken, "NEW_RT")
    }

    /// Reads a URLProtocol-intercepted request body. Prefers `httpBody` when the
    /// transport set it; otherwise falls back to draining `httpBodyStream` (how
    /// `URLProtocol` typically exposes the body), so the assertion is robust
    /// across either representation.
    nonisolated private static func bodyString(of request: URLRequest) -> String {
        if let body = request.httpBody, !body.isEmpty {
            return String(data: body, encoding: .utf8) ?? ""
        }
        guard let stream = request.httpBodyStream else { return "" }
        stream.open()
        defer { stream.close() }
        var buffer = Data()
        let size = 1024
        let bytes = UnsafeMutablePointer<UInt8>.allocate(capacity: size)
        defer { bytes.deallocate() }
        while stream.hasBytesAvailable {
            let read = stream.read(bytes, maxLength: size)
            if read > 0 { buffer.append(bytes, count: read) }
            if read <= 0 { break }
        }
        return String(data: buffer, encoding: .utf8) ?? ""
    }

    nonisolated private static func queryValue(
        _ name: String,
        in request: URLRequest
    ) -> String? {
        request.url.flatMap {
            URLComponents(url: $0, resolvingAgainstBaseURL: false)
        }?.queryItems?.first(where: { $0.name == name })?.value
    }

    func testRefreshAccessTokenSendsGrantTypeRefreshToken() async throws {
        nonisolated(unsafe) var captured = ""
        handlerStore.handler = { request in
            captured = Self.bodyString(of: request)
            let json = #"{"access_token":"NEW_AT","refresh_token":"NEW_RT"}"#
            return (MockURLProtocol.httpResponse(for: request, status: 200), Data(json.utf8))
        }

        _ = try await makeAuth().refreshAccessToken(refreshToken: "OLD_RT")

        XCTAssertTrue(captured.contains("grant_type=refresh_token"), "body: \(captured)")
        XCTAssertTrue(captured.contains("refresh_token=OLD_RT"), "body: \(captured)")
    }

    func testRefreshAccessTokenEmptyRefreshThrows() async {
        do {
            _ = try await makeAuth().refreshAccessToken(refreshToken: "")
            XCTFail("Expected throw")
        } catch TwitchDeviceAuthError.invalidResponse {
            // expected
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testRefreshAccessTokenDeadRefreshThrowsInvalidClient() async {
        handlerStore.handler = { request in
            let json = #"{"error":"invalid_grant","message":"Invalid refresh token"}"#
            return (MockURLProtocol.httpResponse(for: request, status: 400), Data(json.utf8))
        }

        do {
            _ = try await makeAuth().refreshAccessToken(refreshToken: "DEAD")
            XCTFail("Expected throw")
        } catch TwitchDeviceAuthError.invalidClient {
            // expected: caller falls back to interactive re-auth
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testRefreshAccessTokenServerErrorPreservesStatus() async {
        handlerStore.handler = { request in
            (MockURLProtocol.httpResponse(for: request, status: 500), Data("boom".utf8))
        }

        do {
            _ = try await makeAuth().refreshAccessToken(refreshToken: "RT")
            XCTFail("Expected throw")
        } catch TwitchDeviceAuthError.http(let status, let retryAfter) {
            XCTAssertEqual(status, 500)
            XCTAssertNil(retryAfter)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testRefreshAccessTokenRequiresRotatedRefreshToken() async {
        handlerStore.handler = { request in
            (
                MockURLProtocol.httpResponse(for: request, status: 200),
                Data(#"{"access_token":"NEW_AT"}"#.utf8))
        }

        do {
            _ = try await makeAuth().refreshAccessToken(refreshToken: "OLD_RT")
            XCTFail("Expected .invalidResponse")
        } catch TwitchDeviceAuthError.invalidResponse {
            // expected
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testRetryAfterParsesDeltaAndHTTPDateFormats() {
        XCTAssertEqual(TwitchDeviceAuth.retryAfterDuration("12"), .seconds(12))
        let now = Date(timeIntervalSince1970: 784_111_777)
        for value in [
            "Sun, 06 Nov 1994 08:49:49 GMT",
            "Sunday, 06-Nov-94 08:49:49 GMT",
            "Sun Nov  6 08:49:49 1994",
        ] {
            XCTAssertEqual(
                TwitchDeviceAuth.retryAfterDuration(value, now: now),
                .seconds(12))
        }
        XCTAssertEqual(
            TwitchDeviceAuth.retryAfterDuration("1e308"),
            .seconds(300))
        XCTAssertNil(TwitchDeviceAuth.retryAfterDuration("1e309"))
        XCTAssertNil(TwitchDeviceAuth.retryAfterDuration("nan"))
        XCTAssertNil(TwitchDeviceAuth.retryAfterDuration("-1"))
    }

    // MARK: - Fresh EventSub managed-redemption reconciliation

    func testFreshEventSubRecoversDuplicateMissedRedemptionsBeforeSubscribeAndUnpause()
        async throws {
        enableManagedReward(rewardID: "reward")
        try KeychainService.saveTwitchCredentialGrant(
            .init(accessToken: "ACCESS", userID: "broadcaster")
        )

        let directory = FileManager.default.temporaryDirectory
            .appending(path: "wolfwave-redemption-reconcile-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let outbox = TwitchRedemptionResolutionOutbox(
            fileURL: directory.appending(path: "outbox.json"))
        _ = try outbox.enqueueIntake(
            broadcasterID: "broadcaster",
            rewardID: "reward",
            redemptionID: "missed-1")

        let operations = ThreadSafeBox<[String]>([])
        let channelHandler: MockURLProtocol.Handler = { request in
            let path = request.url?.path ?? ""
            let body = Self.bodyString(of: request)
            if path.hasSuffix("/channel_points/custom_rewards/redemptions") {
                if request.httpMethod == "GET" {
                    operations.mutate { $0.append("fetch-unfulfilled") }
                    return (
                        MockURLProtocol.httpResponse(for: request, status: 200),
                        Data(
                            #"{"data":[{"id":"missed-1"},{"id":"missed-2"},{"id":"missed-1"}],"pagination":{}}"#.utf8)
                    )
                }
                let redemptionID = Self.queryValue("id", in: request) ?? ""
                operations.mutate { $0.append("cancel:\(redemptionID)") }
                XCTAssertTrue(body.contains("CANCELED"))
                return (MockURLProtocol.httpResponse(for: request, status: 204), Data())
            }
            if request.httpMethod == "GET" {
                operations.mutate { $0.append("ensure-existing") }
                return (
                    MockURLProtocol.httpResponse(for: request, status: 200),
                    Data(#"{"data":[{"id":"reward"}]}"#.utf8)
                )
            }
            if body.contains(#""is_paused":true"#) {
                operations.mutate { $0.append("pause") }
            } else if body.contains(#""is_paused":false"#) {
                operations.mutate { $0.append("unpause") }
                XCTAssertTrue(body.contains(#""is_enabled":true"#))
            } else if body.contains(#""cost":"#) {
                operations.mutate { $0.append("cost") }
            }
            return (MockURLProtocol.httpResponse(for: request, status: 204), Data())
        }
        let eventSubHandler: MockURLProtocol.Handler = { request in
            operations.mutate { $0.append("subscribe") }
            return (
                MockURLProtocol.httpResponse(for: request, status: 202),
                Data(#"{"data":[{"id":"subscription"}]}"#.utf8)
            )
        }
        let service = TwitchChatService(
            eventSubHTTPClient: HTTPClient(
                session: MockURLProtocol.makeSession(handler: eventSubHandler)),
            channelPointsService: TwitchChannelPointsService(
                session: MockURLProtocol.makeSession(handler: channelHandler)),
            redemptionResolutionOutbox: outbox,
            redemptionClientIDProvider: { "client" })
        await service.configureManagedRedemptionSessionForTesting()

        await service.subscribeToRedemptionsIfEnabled()

        XCTAssertTrue(outbox.pendingItems().isEmpty)
        XCTAssertEqual(
            RedemptionStatus(
                rawValue: DefaultsStore.store.string(
                    forKey: AppConstants.UserDefaults.songRequestRedemptionStatus) ?? ""),
            .ok)
        let completed = operations.value
        XCTAssertEqual(
            completed.filter { $0.hasPrefix("cancel:") }.sorted(),
            ["cancel:missed-1", "cancel:missed-2"])
        let fetchIndex = try XCTUnwrap(completed.firstIndex(of: "fetch-unfulfilled"))
        let firstCancelIndex = try XCTUnwrap(
            completed.indices.filter { completed[$0].hasPrefix("cancel:") }.min())
        let lastCancelIndex = try XCTUnwrap(
            completed.indices.filter { completed[$0].hasPrefix("cancel:") }.max())
        let subscribeIndex = try XCTUnwrap(completed.firstIndex(of: "subscribe"))
        let unpauseIndex = try XCTUnwrap(completed.firstIndex(of: "unpause"))
        XCTAssertLessThan(fetchIndex, firstCancelIndex)
        XCTAssertLessThan(lastCancelIndex, subscribeIndex)
        XCTAssertLessThan(subscribeIndex, unpauseIndex)
    }

    func testFreshEventSubStorageFailureKeepsRewardPausedAndSkipsSubscription()
        async throws {
        enum InjectedFailure: Error {
            case write
        }

        enableManagedReward(rewardID: "reward")
        try KeychainService.saveTwitchCredentialGrant(
            .init(accessToken: "ACCESS", userID: "broadcaster")
        )
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "wolfwave-redemption-reconcile-store-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let writes = ThreadSafeBox(0)
        let outbox = TwitchRedemptionResolutionOutbox(
            fileURL: directory.appending(path: "outbox.json"),
            atomicWriter: { data, url in
                var attempt = 0
                writes.mutate {
                    $0 += 1
                    attempt = $0
                }
                if attempt == 2 { throw InjectedFailure.write }
                try data.write(to: url, options: .atomic)
            })
        let operations = ThreadSafeBox<[String]>([])
        let eventSubRequests = ThreadSafeBox(0)
        let channelHandler: MockURLProtocol.Handler = { request in
            let path = request.url?.path ?? ""
            let body = Self.bodyString(of: request)
            if path.hasSuffix("/channel_points/custom_rewards/redemptions") {
                operations.mutate { $0.append("fetch-unfulfilled") }
                return (
                    MockURLProtocol.httpResponse(for: request, status: 200),
                    Data(
                        #"{"data":[{"id":"missed"}],"pagination":{}}"#.utf8)
                )
            }
            if request.httpMethod == "GET" {
                return (
                    MockURLProtocol.httpResponse(for: request, status: 200),
                    Data(#"{"data":[{"id":"reward"}]}"#.utf8)
                )
            }
            if body.contains(#""is_paused":true"#) {
                operations.mutate { $0.append("pause") }
            } else if body.contains(#""is_paused":false"#) {
                operations.mutate { $0.append("unpause") }
            }
            return (MockURLProtocol.httpResponse(for: request, status: 204), Data())
        }
        let service = TwitchChatService(
            eventSubHTTPClient: HTTPClient(
                session: MockURLProtocol.makeSession { request in
                    eventSubRequests.mutate { $0 += 1 }
                    return (
                        MockURLProtocol.httpResponse(for: request, status: 202),
                        Data())
                }),
            channelPointsService: TwitchChannelPointsService(
                session: MockURLProtocol.makeSession(handler: channelHandler)),
            redemptionResolutionOutbox: outbox,
            redemptionClientIDProvider: { "client" })
        await service.configureManagedRedemptionSessionForTesting()

        await service.subscribeToRedemptionsIfEnabled()

        XCTAssertEqual(writes.value, 2)
        XCTAssertTrue(outbox.intakeStorageIsUnavailable())
        XCTAssertTrue(outbox.pendingItems().isEmpty)
        XCTAssertEqual(eventSubRequests.value, 0)
        XCTAssertFalse(operations.value.contains("unpause"))
        XCTAssertFalse(operations.value.contains { $0.hasPrefix("cancel:") })
        XCTAssertTrue(operations.value.contains("pause"))
        XCTAssertEqual(
            RedemptionStatus(
                rawValue: DefaultsStore.store.string(
                    forKey: AppConstants.UserDefaults.songRequestRedemptionStatus) ?? ""),
            .storageUnavailable)
    }

    func testFreshEventSubRecoveryAPIFailureKeepsRewardPausedAndSkipsSubscription()
        async throws {
        enableManagedReward(rewardID: "reward")
        try KeychainService.saveTwitchCredentialGrant(
            .init(accessToken: "ACCESS", userID: "broadcaster")
        )
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "wolfwave-redemption-reconcile-api-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let outbox = TwitchRedemptionResolutionOutbox(
            fileURL: directory.appending(path: "outbox.json"))
        let operations = ThreadSafeBox<[String]>([])
        let eventSubRequests = ThreadSafeBox(0)
        let channelHandler: MockURLProtocol.Handler = { request in
            let path = request.url?.path ?? ""
            let body = Self.bodyString(of: request)
            if path.hasSuffix("/channel_points/custom_rewards/redemptions") {
                operations.mutate { $0.append("fetch-unfulfilled") }
                return (
                    MockURLProtocol.httpResponse(for: request, status: 503),
                    Data("temporary".utf8)
                )
            }
            if request.httpMethod == "GET" {
                return (
                    MockURLProtocol.httpResponse(for: request, status: 200),
                    Data(#"{"data":[{"id":"reward"}]}"#.utf8)
                )
            }
            if body.contains(#""is_paused":true"#) {
                operations.mutate { $0.append("pause") }
            } else if body.contains(#""is_paused":false"#) {
                operations.mutate { $0.append("unpause") }
            }
            return (MockURLProtocol.httpResponse(for: request, status: 204), Data())
        }
        let service = TwitchChatService(
            eventSubHTTPClient: HTTPClient(
                session: MockURLProtocol.makeSession { request in
                    eventSubRequests.mutate { $0 += 1 }
                    return (
                        MockURLProtocol.httpResponse(for: request, status: 202),
                        Data())
                }),
            channelPointsService: TwitchChannelPointsService(
                session: MockURLProtocol.makeSession(handler: channelHandler)),
            redemptionResolutionOutbox: outbox,
            redemptionClientIDProvider: { "client" })
        await service.configureManagedRedemptionSessionForTesting()

        await service.subscribeToRedemptionsIfEnabled()

        XCTAssertEqual(eventSubRequests.value, 0)
        XCTAssertFalse(operations.value.contains("unpause"))
        XCTAssertTrue(operations.value.contains("pause"))
        XCTAssertTrue(outbox.pendingItems().isEmpty)
        XCTAssertFalse(outbox.intakeStorageIsUnavailable())
        XCTAssertEqual(
            RedemptionStatus(
                rawValue: DefaultsStore.store.string(
                    forKey: AppConstants.UserDefaults.songRequestRedemptionStatus) ?? ""),
            .subscribeFailed)
    }

    func testFreshEventSubClearsDeletedStoredRewardAndRecreatesItHeld()
        async throws {
        enableManagedReward(rewardID: "stale-reward")
        try KeychainService.saveTwitchCredentialGrant(
            .init(accessToken: "ACCESS", userID: "broadcaster")
        )
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "wolfwave-redemption-recreate-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let outbox = TwitchRedemptionResolutionOutbox(
            fileURL: directory.appending(path: "outbox.json"))
        let operations = ThreadSafeBox<[String]>([])
        let channelHandler: MockURLProtocol.Handler = { request in
            let path = request.url?.path ?? ""
            let rewardID = Self.queryValue("id", in: request) ?? ""
            let body = Self.bodyString(of: request)
            if path.hasSuffix("/channel_points/custom_rewards/redemptions") {
                operations.mutate { $0.append("fetch:\(Self.queryValue("reward_id", in: request) ?? "")") }
                return (
                    MockURLProtocol.httpResponse(for: request, status: 200),
                    Data(#"{"data":[],"pagination":{}}"#.utf8)
                )
            }
            if request.httpMethod == "POST" {
                operations.mutate { $0.append("create") }
                XCTAssertTrue(body.contains(#""is_enabled":false"#))
                return (
                    MockURLProtocol.httpResponse(for: request, status: 200),
                    Data(#"{"data":[{"id":"fresh-reward"}]}"#.utf8)
                )
            }
            if request.httpMethod == "GET" {
                operations.mutate { $0.append("unexpected-lookup") }
                return (
                    MockURLProtocol.httpResponse(for: request, status: 200),
                    Data(#"{"data":[]}"#.utf8)
                )
            }
            if body.contains(#""is_paused":true"#) {
                operations.mutate { $0.append("pause:\(rewardID)") }
                let status = rewardID == "stale-reward" ? 404 : 204
                return (MockURLProtocol.httpResponse(for: request, status: status), Data())
            }
            if body.contains(#""is_paused":false"#) {
                operations.mutate { $0.append("unpause:\(rewardID)") }
                XCTAssertTrue(body.contains(#""is_enabled":true"#))
            } else if body.contains(#""cost":"#) {
                operations.mutate { $0.append("cost:\(rewardID)") }
            }
            return (MockURLProtocol.httpResponse(for: request, status: 204), Data())
        }
        let eventSubHandler: MockURLProtocol.Handler = { request in
            operations.mutate { $0.append("subscribe") }
            return (
                MockURLProtocol.httpResponse(for: request, status: 202),
                Data(#"{"data":[{"id":"subscription"}]}"#.utf8)
            )
        }
        let service = TwitchChatService(
            eventSubHTTPClient: HTTPClient(
                session: MockURLProtocol.makeSession(handler: eventSubHandler)),
            channelPointsService: TwitchChannelPointsService(
                session: MockURLProtocol.makeSession(handler: channelHandler)),
            redemptionResolutionOutbox: outbox,
            redemptionClientIDProvider: { "client" })
        await service.configureManagedRedemptionSessionForTesting()

        await service.subscribeToRedemptionsIfEnabled()

        XCTAssertEqual(
            DefaultsStore.store.string(
                forKey: AppConstants.UserDefaults.songRequestChannelPointsRewardID),
            "fresh-reward")
        XCTAssertTrue(outbox.pendingItems().isEmpty)
        let completed = operations.value
        XCTAssertFalse(completed.contains("unexpected-lookup"))
        let stalePause = try XCTUnwrap(completed.firstIndex(of: "pause:stale-reward"))
        let create = try XCTUnwrap(completed.firstIndex(of: "create"))
        let freshPause = try XCTUnwrap(completed.firstIndex(of: "pause:fresh-reward"))
        let fetch = try XCTUnwrap(completed.firstIndex(of: "fetch:fresh-reward"))
        let subscribe = try XCTUnwrap(completed.firstIndex(of: "subscribe"))
        let unpause = try XCTUnwrap(completed.firstIndex(of: "unpause:fresh-reward"))
        XCTAssertLessThan(stalePause, create)
        XCTAssertLessThan(create, freshPause)
        XCTAssertLessThan(freshPause, fetch)
        XCTAssertLessThan(fetch, subscribe)
        XCTAssertLessThan(subscribe, unpause)
    }

    func testHeldReconciliationClearsPersistentOpaqueRecoveryRisk() async throws {
        enableManagedReward(rewardID: "reward")
        try KeychainService.saveTwitchCredentialGrant(
            .init(
                accessToken: "ACCESS",
                refreshToken: "REFRESH",
                username: "wolf",
                userID: "broadcaster"))
        let directory = makeIsolatedTempDirectory(prefix: "wolfwave-opaque-reconciliation")
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appending(path: "outbox.json")
        try Data("not-json".utf8).write(to: file, options: .atomic)
        let outbox = TwitchRedemptionResolutionOutbox(fileURL: file)
        XCTAssertTrue(outbox.hasOpaqueRecoveryRisk())

        let channelHandler: MockURLProtocol.Handler = { request in
            let path = request.url?.path ?? ""
            if request.httpMethod == "GET",
               path.hasSuffix("/redemptions") {
                return (
                    MockURLProtocol.httpResponse(for: request, status: 200),
                    Data(#"{"data":[],"pagination":{}}"#.utf8))
            }
            if request.httpMethod == "GET" {
                return (
                    MockURLProtocol.httpResponse(for: request, status: 200),
                    Data(#"{"data":[{"id":"reward"}]}"#.utf8))
            }
            return (
                MockURLProtocol.httpResponse(for: request, status: 204),
                Data())
        }
        let eventSubHandler: MockURLProtocol.Handler = { request in
            (
                MockURLProtocol.httpResponse(for: request, status: 202),
                Data(#"{"data":[{"id":"subscription"}]}"#.utf8))
        }
        let service = TwitchChatService(
            eventSubHTTPClient: HTTPClient(
                session: MockURLProtocol.makeSession(handler: eventSubHandler)),
            channelPointsService: TwitchChannelPointsService(
                session: MockURLProtocol.makeSession(handler: channelHandler)),
            redemptionResolutionOutbox: outbox,
            redemptionClientIDProvider: { "client" })
        await service.configureManagedRedemptionSessionForTesting()

        await service.subscribeToRedemptionsIfEnabled()

        XCTAssertFalse(outbox.hasOpaqueRecoveryRisk())
        let leftChannel = await service.leaveChannel()
        XCTAssertTrue(leftChannel)
    }

    func testCredentialClearWaitsForManagedRewardPauseBeforeDeletingKeychain()
        async throws {
        enableManagedReward(rewardID: "reward")
        try KeychainService.saveTwitchCredentialGrant(
            .init(
                accessToken: "OLD_ACCESS",
                refreshToken: "OLD_REFRESH",
                username: "wolf",
                userID: "broadcaster"))
        let pauseEntered = DispatchSemaphore(value: 0)
        let releasePause = DispatchSemaphore(value: 0)
        let captured = ThreadSafeBox<URLRequest?>(nil)
        let channelHandler: MockURLProtocol.Handler = { request in
            if let response = Self.emptyUnfulfilledRedemptionsResponse(
                for: request) {
                return response
            }
            captured.value = request
            pauseEntered.signal()
            guard releasePause.wait(timeout: .now() + 2) == .success else {
                throw URLError(.timedOut)
            }
            return (MockURLProtocol.httpResponse(for: request, status: 204), Data())
        }
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "wolfwave-redemption-teardown-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let service = TwitchChatService(
            channelPointsService: TwitchChannelPointsService(
                session: MockURLProtocol.makeSession(handler: channelHandler)),
            redemptionResolutionOutbox: TwitchRedemptionResolutionOutbox(
                fileURL: directory.appending(path: "outbox.json")),
            redemptionClientIDProvider: { "client" })
        await service.configureManagedRedemptionSessionForTesting(
            token: "OLD_ACCESS")
        let viewModel = TwitchViewModel(
            cancelTokenValidationSchedule: {},
            restartTokenValidationSchedule: {})
        viewModel.twitchService = service

        let clearing = Task { @MainActor in
            await viewModel.clearCredentials()
        }
        let didEnterPause = await waitForSemaphore(
            pauseEntered,
            timeout: .now() + 2)
        XCTAssertTrue(didEnterPause)
        XCTAssertEqual(KeychainService.loadTwitchToken(), "OLD_ACCESS")
        XCTAssertEqual(
            TwitchCredentialStore.shared.connectionSnapshot()?.accessToken,
            "OLD_ACCESS")

        releasePause.signal()
        _ = await clearing.value

        XCTAssertNil(KeychainService.loadTwitchToken())
        let request = try XCTUnwrap(captured.value)
        XCTAssertEqual(request.httpMethod, "PATCH")
        XCTAssertEqual(request.timeoutInterval, 5)
        XCTAssertEqual(
            request.value(forHTTPHeaderField: "Authorization"),
            "Bearer OLD_ACCESS")
        XCTAssertTrue(Self.bodyString(of: request).contains(#""is_paused":true"#))
    }

    func testCredentialClearRefusesFailedRewardPauseAndRestartsValidation() async throws {
        enableManagedReward(rewardID: "reward")
        try KeychainService.saveTwitchCredentialGrant(
            .init(
                accessToken: "OLD_ACCESS",
                refreshToken: "OLD_REFRESH",
                username: "wolf",
                userID: "broadcaster"))
        let captured = ThreadSafeBox<URLRequest?>(nil)
        let channelHandler: MockURLProtocol.Handler = { request in
            if let response = Self.emptyUnfulfilledRedemptionsResponse(
                for: request) {
                return response
            }
            captured.value = request
            return (
                MockURLProtocol.httpResponse(for: request, status: 503),
                Data("unavailable".utf8))
        }
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "wolfwave-redemption-teardown-failure-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let service = TwitchChatService(
            channelPointsService: TwitchChannelPointsService(
                session: MockURLProtocol.makeSession(handler: channelHandler)),
            redemptionResolutionOutbox: TwitchRedemptionResolutionOutbox(
                fileURL: directory.appending(path: "outbox.json")),
            redemptionClientIDProvider: { "client" })
        await service.configureManagedRedemptionSessionForTesting(
            token: "OLD_ACCESS")
        let restarts = ThreadSafeBox(0)
        let viewModel = TwitchViewModel(
            cancelTokenValidationSchedule: {},
            restartTokenValidationSchedule: {
                restarts.mutate { $0 += 1 }
            })
        viewModel.twitchService = service

        let cleared = await viewModel.clearCredentials()

        XCTAssertFalse(cleared)
        XCTAssertEqual(KeychainService.loadTwitchToken(), "OLD_ACCESS")
        XCTAssertEqual(
            TwitchCredentialStore.shared.connectionSnapshot()?.accessToken,
            "OLD_ACCESS")
        let state = await service.managedRedemptionIdentityForTesting()
        XCTAssertEqual(state.oauthToken, "OLD_ACCESS")
        XCTAssertEqual(state.broadcasterID, "broadcaster")
        XCTAssertEqual(viewModel.connectionError?.id, "twitch.disconnectFailed")
        XCTAssertEqual(restarts.value, 1)
        let request = try XCTUnwrap(captured.value)
        XCTAssertEqual(request.timeoutInterval, 5)
        XCTAssertTrue(Self.bodyString(of: request).contains(#""is_paused":true"#))
    }

    func testCredentialClearWithoutServicePreservesManagedRewardOwner() async throws {
        enableManagedReward(rewardID: "reward")
        let grant = KeychainService.TwitchCredentialGrant(
            accessToken: "ACCESS",
            refreshToken: "REFRESH",
            username: "wolf",
            userID: "broadcaster")
        try KeychainService.saveTwitchCredentialGrant(grant)
        let restarts = ThreadSafeBox(0)
        let viewModel = TwitchViewModel(
            cancelTokenValidationSchedule: {},
            restartTokenValidationSchedule: {
                restarts.mutate { $0 += 1 }
            })
        viewModel.twitchService = nil

        let cleared = await viewModel.clearCredentials()

        XCTAssertFalse(cleared)
        XCTAssertEqual(KeychainService.loadTwitchCredentialGrant(), grant)
        XCTAssertEqual(
            DefaultsStore.store.string(
                forKey: AppConstants.UserDefaults.songRequestChannelPointsRewardID),
            "reward")
        XCTAssertEqual(restarts.value, 1)
        XCTAssertEqual(viewModel.connectionError?.id, "twitch.disconnectFailed")
    }

    func testDisconnectedServiceUsesStoredBroadcasterGrantToPauseBeforeClear()
        async throws {
        enableManagedReward(rewardID: "reward")
        try KeychainService.saveTwitchCredentialGrant(
            .init(
                accessToken: "STORED_ACCESS",
                refreshToken: "STORED_REFRESH",
                username: "wolf",
                userID: "broadcaster"))
        let captured = ThreadSafeBox<URLRequest?>(nil)
        let channelHandler: MockURLProtocol.Handler = { request in
            if let response = Self.emptyUnfulfilledRedemptionsResponse(
                for: request) {
                return response
            }
            captured.value = request
            return (MockURLProtocol.httpResponse(for: request, status: 204), Data())
        }
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "wolfwave-disconnected-redemption-teardown-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let service = TwitchChatService(
            channelPointsService: TwitchChannelPointsService(
                session: MockURLProtocol.makeSession(handler: channelHandler)),
            redemptionResolutionOutbox: TwitchRedemptionResolutionOutbox(
                fileURL: directory.appending(path: "outbox.json")),
            redemptionClientIDProvider: { "stored-client" })
        let viewModel = TwitchViewModel(
            cancelTokenValidationSchedule: {},
            restartTokenValidationSchedule: {})
        viewModel.twitchService = service

        let cleared = await viewModel.clearCredentials()

        XCTAssertTrue(cleared)
        XCTAssertNil(KeychainService.loadTwitchToken())
        let request = try XCTUnwrap(captured.value)
        XCTAssertEqual(
            request.value(forHTTPHeaderField: "Authorization"),
            "Bearer STORED_ACCESS")
        XCTAssertEqual(
            request.value(forHTTPHeaderField: "Client-Id"),
            "stored-client")
        XCTAssertEqual(Self.queryValue("broadcaster_id", in: request), "broadcaster")
        XCTAssertEqual(Self.queryValue("id", in: request), "reward")
        XCTAssertTrue(Self.bodyString(of: request).contains(#""is_paused":true"#))
    }

    func testMissingManagedRewardIsSafeToClearAndForgetsStoredID() async throws {
        enableManagedReward(rewardID: "missing-reward")
        try KeychainService.saveTwitchCredentialGrant(
            .init(
                accessToken: "ACCESS",
                refreshToken: "REFRESH",
                username: "wolf",
                userID: "broadcaster"))
        let channelHandler: MockURLProtocol.Handler = { request in
            return (
                MockURLProtocol.httpResponse(for: request, status: 404),
                Data("missing".utf8))
        }
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "wolfwave-missing-redemption-teardown-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let service = TwitchChatService(
            channelPointsService: TwitchChannelPointsService(
                session: MockURLProtocol.makeSession(handler: channelHandler)),
            redemptionResolutionOutbox: TwitchRedemptionResolutionOutbox(
                fileURL: directory.appending(path: "outbox.json")),
            redemptionClientIDProvider: { "client" })
        let viewModel = TwitchViewModel(
            cancelTokenValidationSchedule: {},
            restartTokenValidationSchedule: {})
        viewModel.twitchService = service

        let cleared = await viewModel.clearCredentials()

        XCTAssertTrue(cleared)
        XCTAssertNil(KeychainService.loadTwitchToken())
        XCTAssertNil(
            DefaultsStore.store.string(
                forKey: AppConstants.UserDefaults.songRequestChannelPointsRewardID))
    }

    func testSupersededLeavePreservesKeychainAndNewerSameAccountOwner() async throws {
        enableManagedReward(rewardID: "reward")
        try KeychainService.saveTwitchCredentialGrant(
            .init(
                accessToken: "OLD_ACCESS",
                refreshToken: "OLD_REFRESH",
                username: "wolf",
                userID: "broadcaster"))
        let pauseEntered = DispatchSemaphore(value: 0)
        let releasePause = DispatchSemaphore(value: 0)
        let channelHandler: MockURLProtocol.Handler = { request in
            if let response = Self.emptyUnfulfilledRedemptionsResponse(
                for: request) {
                return response
            }
            pauseEntered.signal()
            guard releasePause.wait(timeout: .now() + 2) == .success else {
                throw URLError(.timedOut)
            }
            return (MockURLProtocol.httpResponse(for: request, status: 204), Data())
        }
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "wolfwave-redemption-stale-leave-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let service = TwitchChatService(
            channelPointsService: TwitchChannelPointsService(
                session: MockURLProtocol.makeSession(handler: channelHandler)),
            redemptionResolutionOutbox: TwitchRedemptionResolutionOutbox(
                fileURL: directory.appending(path: "outbox.json")))
        await service.configureManagedRedemptionSessionForTesting(
            token: "OLD_ACCESS")

        let viewModel = TwitchViewModel(
            cancelTokenValidationSchedule: {},
            restartTokenValidationSchedule: {})
        viewModel.twitchService = service
        let clearing = Task { @MainActor in
            await viewModel.clearCredentials()
        }
        let didEnterPause = await waitForSemaphore(
            pauseEntered,
            timeout: .now() + 2)
        XCTAssertTrue(didEnterPause)

        await service.supersedeChannelOwnershipForTesting()
        releasePause.signal()
        _ = await clearing.value

        let state = await service.managedRedemptionIdentityForTesting()
        XCTAssertEqual(state.broadcasterID, "broadcaster")
        XCTAssertEqual(state.botID, "broadcaster")
        XCTAssertEqual(KeychainService.loadTwitchToken(), "OLD_ACCESS")
        XCTAssertEqual(viewModel.connectionError?.id, "twitch.disconnectFailed")
        XCTAssertEqual(state.oauthToken, "OLD_ACCESS")
        XCTAssertEqual(state.clientID, "client")
    }

    func testSupersededLeaveReconcilesAfterItsStalePauseCompletes() async throws {
        enableManagedReward(rewardID: "reward")
        try KeychainService.saveTwitchCredentialGrant(
            .init(
                accessToken: "ACCESS",
                refreshToken: "REFRESH",
                username: "wolf",
                userID: "broadcaster"))
        let firstPauseEntered = DispatchSemaphore(value: 0)
        let releaseFirstPause = DispatchSemaphore(value: 0)
        let patchCount = ThreadSafeBox(0)
        let operations = ThreadSafeBox<[String]>([])
        let channelHandler: MockURLProtocol.Handler = { request in
            let body = Self.bodyString(of: request)
            let path = request.url?.path ?? ""
            if request.httpMethod == "PATCH" {
                var attempt = 0
                patchCount.mutate {
                    $0 += 1
                    attempt = $0
                }
                if attempt == 1 {
                    operations.mutate { $0.append("stale-pause") }
                    firstPauseEntered.signal()
                    guard releaseFirstPause.wait(timeout: .now() + 2) == .success else {
                        throw URLError(.timedOut)
                    }
                } else if body.contains(#""is_paused":false"#) {
                    operations.mutate { $0.append("repair-unpause") }
                } else if body.contains(#""is_paused":true"#) {
                    operations.mutate { $0.append("repair-pause") }
                } else if body.contains(#""cost":"#) {
                    operations.mutate { $0.append("repair-cost") }
                }
                return (MockURLProtocol.httpResponse(for: request, status: 204), Data())
            }
            if request.httpMethod == "GET", path.hasSuffix("/redemptions") {
                operations.mutate { $0.append("repair-fetch") }
                return (
                    MockURLProtocol.httpResponse(for: request, status: 200),
                    Data(#"{"data":[],"pagination":{}}"#.utf8))
            }
            if request.httpMethod == "GET" {
                operations.mutate { $0.append("repair-lookup") }
                return (
                    MockURLProtocol.httpResponse(for: request, status: 200),
                    Data(#"{"data":[{"id":"reward"}]}"#.utf8))
            }
            return (MockURLProtocol.httpResponse(for: request, status: 500), Data())
        }
        let eventSubHandler: MockURLProtocol.Handler = { request in
            operations.mutate { $0.append("repair-subscribe") }
            return (
                MockURLProtocol.httpResponse(for: request, status: 202),
                Data(#"{"data":[{"id":"subscription"}]}"#.utf8))
        }
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "wolfwave-stale-pause-repair-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let service = TwitchChatService(
            eventSubHTTPClient: HTTPClient(
                session: MockURLProtocol.makeSession(handler: eventSubHandler)),
            channelPointsService: TwitchChannelPointsService(
                session: MockURLProtocol.makeSession(handler: channelHandler)),
            redemptionResolutionOutbox: TwitchRedemptionResolutionOutbox(
                fileURL: directory.appending(path: "outbox.json")),
            redemptionClientIDProvider: { "client" })
        await service.configureManagedRedemptionSessionForTesting(token: "ACCESS")

        let leaving = Task { await service.leaveChannel() }
        let entered = await waitForSemaphore(
            firstPauseEntered,
            timeout: .now() + 2)
        XCTAssertTrue(entered)

        let socketSession = URLSession(configuration: .ephemeral)
        defer { socketSession.invalidateAndCancel() }
        let replacement = socketSession.webSocketTask(
            with: try XCTUnwrap(URL(string: "wss://eventsub.wss.twitch.tv/replacement")))
        _ = await service.installLiveChatSessionForTesting(
            replacement,
            actorToken: "ACCESS",
            botID: "broadcaster")
        await service.supersedeChannelOwnershipForTesting()
        releaseFirstPause.signal()

        let left = await leaving.value

        XCTAssertFalse(left)
        XCTAssertTrue(service.currentlyConnected)
        XCTAssertEqual(operations.value.last, "repair-unpause")
        let subscribe = try XCTUnwrap(
            operations.value.firstIndex(of: "repair-subscribe"))
        let unpause = try XCTUnwrap(
            operations.value.firstIndex(of: "repair-unpause"))
        XCTAssertLessThan(subscribe, unpause)

        DefaultsStore.store.removeObject(
            forKey: AppConstants.UserDefaults.songRequestChannelPointsRewardID)
        await service.leaveChannel()
    }

    func testNoRewardForeignBroadcasterOutboxBlocksCredentialClear() async throws {
        try KeychainService.saveTwitchCredentialGrant(
            .init(
                accessToken: "ACCESS-B",
                refreshToken: "REFRESH-B",
                username: "account-b",
                userID: "account-b"))
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "wolfwave-foreign-outbox-teardown-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let outbox = TwitchRedemptionResolutionOutbox(
            fileURL: directory.appending(path: "outbox.json"))
        _ = try outbox.enqueue(
            broadcasterID: "account-a",
            rewardID: "reward-a",
            redemptionID: "redemption-a",
            resolution: .canceled)
        let requests = ThreadSafeBox(0)
        let handler: MockURLProtocol.Handler = { request in
            requests.mutate { $0 += 1 }
            return (
                MockURLProtocol.httpResponse(for: request, status: 204),
                Data())
        }
        let service = TwitchChatService(
            channelPointsService: TwitchChannelPointsService(
                session: MockURLProtocol.makeSession(handler: handler)),
            redemptionResolutionOutbox: outbox,
            redemptionClientIDProvider: { "client" })
        let viewModel = TwitchViewModel(
            cancelTokenValidationSchedule: {},
            restartTokenValidationSchedule: {})
        viewModel.twitchService = service

        let cleared = await viewModel.clearCredentials()

        XCTAssertFalse(cleared)
        XCTAssertEqual(KeychainService.loadTwitchToken(), "ACCESS-B")
        XCTAssertEqual(outbox.pendingItems().count, 1)
        XCTAssertEqual(requests.value, 0)
    }

    func testRetryingPersistedRedemptionBlocksCredentialClear() async throws {
        storeManagedRewardIdentity(rewardID: "reward")
        try KeychainService.saveTwitchCredentialGrant(
            .init(
                accessToken: "ACCESS",
                refreshToken: "REFRESH",
                username: "wolf",
                userID: "broadcaster"))
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "wolfwave-retrying-outbox-teardown-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let outbox = TwitchRedemptionResolutionOutbox(
            fileURL: directory.appending(path: "outbox.json"))
        _ = try outbox.enqueue(
            broadcasterID: "broadcaster",
            rewardID: "reward",
            redemptionID: "redemption",
            resolution: .canceled)
        let handler: MockURLProtocol.Handler = { request in
            let body = Self.bodyString(of: request)
            let status = body.contains(#""status":"CANCELED""#) ? 503 : 204
            return (
                MockURLProtocol.httpResponse(for: request, status: status),
                Data())
        }
        let service = TwitchChatService(
            channelPointsService: TwitchChannelPointsService(
                session: MockURLProtocol.makeSession(handler: handler)),
            redemptionResolutionOutbox: outbox,
            redemptionClientIDProvider: { "client" })
        await service.configureManagedRedemptionSessionForTesting()
        await service.setRedemptionResolutionSleep { _ in
            throw CancellationError()
        }
        let viewModel = TwitchViewModel(
            cancelTokenValidationSchedule: {},
            restartTokenValidationSchedule: {})
        viewModel.twitchService = service

        let cleared = await viewModel.clearCredentials()

        XCTAssertFalse(cleared)
        XCTAssertEqual(KeychainService.loadTwitchToken(), "ACCESS")
        XCTAssertEqual(outbox.pendingItems().count, 1)
    }

    func testLiveRedemptionIntakeSettlesAndDrainsBeforeCredentialClear() async throws {
        storeManagedRewardIdentity(rewardID: "reward")
        try KeychainService.saveTwitchCredentialGrant(
            .init(
                accessToken: "ACCESS",
                refreshToken: "REFRESH",
                username: "wolf",
                userID: "broadcaster"))
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "wolfwave-live-intake-teardown-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let outbox = TwitchRedemptionResolutionOutbox(
            fileURL: directory.appending(path: "outbox.json"))
        let intake = try outbox.enqueueIntake(
            broadcasterID: "broadcaster",
            rewardID: "reward",
            redemptionID: "redemption").item
        let requests = ThreadSafeBox<[String]>([])
        let handler: MockURLProtocol.Handler = { request in
            if let response = Self.emptyUnfulfilledRedemptionsResponse(
                for: request) {
                return response
            }
            requests.mutate { $0.append(Self.bodyString(of: request)) }
            return (
                MockURLProtocol.httpResponse(for: request, status: 204),
                Data())
        }
        let service = TwitchChatService(
            channelPointsService: TwitchChannelPointsService(
                session: MockURLProtocol.makeSession(handler: handler)),
            redemptionResolutionOutbox: outbox,
            redemptionClientIDProvider: { "client" })
        await service.configureManagedRedemptionSessionForTesting()
        let intakeGate = OAuthIdentityGate()
        await service.installTeardownLiveIntakeForTesting(item: intake) {
            await intakeGate.suspend()
            _ = try? outbox.updateResolution(intake.id, to: .canceled)
        }
        let intakeDidSuspend = await waitUntil { await intakeGate.suspended }
        XCTAssertTrue(intakeDidSuspend)

        let viewModel = TwitchViewModel(
            cancelTokenValidationSchedule: {},
            restartTokenValidationSchedule: {})
        viewModel.twitchService = service
        let clearResult = ThreadSafeBox<Bool?>(nil)
        let clearing = Task { @MainActor in
            clearResult.value = await viewModel.clearCredentials()
        }
        try await Task.sleep(for: .milliseconds(100))

        XCTAssertNil(clearResult.value)
        XCTAssertEqual(KeychainService.loadTwitchToken(), "ACCESS")

        await intakeGate.resume()
        await clearing.value

        XCTAssertEqual(clearResult.value, true)
        XCTAssertNil(KeychainService.loadTwitchToken())
        XCTAssertTrue(outbox.pendingItems().isEmpty)
        XCTAssertTrue(requests.value.contains {
            $0.contains(#""status":"CANCELED""#)
        })
    }

    func testDelayedSetupUnpauseCompletesBeforeFinalTeardownPause() async throws {
        storeManagedRewardIdentity(rewardID: "reward")
        try KeychainService.saveTwitchCredentialGrant(
            .init(
                accessToken: "ACCESS",
                refreshToken: "REFRESH",
                username: "wolf",
                userID: "broadcaster"))
        let unpauseEntered = DispatchSemaphore(value: 0)
        let releaseUnpause = DispatchSemaphore(value: 0)
        let operations = ThreadSafeBox<[String]>([])
        let handler: MockURLProtocol.Handler = { request in
            if let response = Self.emptyUnfulfilledRedemptionsResponse(
                for: request) {
                return response
            }
            let body = Self.bodyString(of: request)
            if body.contains(#""is_paused":false"#) {
                operations.mutate { $0.append("unpause") }
                unpauseEntered.signal()
                guard releaseUnpause.wait(timeout: .now() + 2) == .success else {
                    throw URLError(.timedOut)
                }
            } else if body.contains(#""is_paused":true"#) {
                operations.mutate { $0.append("pause") }
            }
            return (
                MockURLProtocol.httpResponse(for: request, status: 204),
                Data())
        }
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "wolfwave-setup-teardown-order-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let service = TwitchChatService(
            channelPointsService: TwitchChannelPointsService(
                session: MockURLProtocol.makeSession(handler: handler)),
            redemptionResolutionOutbox: TwitchRedemptionResolutionOutbox(
                fileURL: directory.appending(path: "outbox.json")),
            redemptionClientIDProvider: { "client" })
        await service.configureManagedRedemptionSessionForTesting()
        let unpausing = Task {
            try await service.runManagedRewardUnpauseUnderSetupLeaseForTesting(
                rewardID: "reward")
        }
        let unpauseDidStart = await waitForSemaphore(
            unpauseEntered,
            timeout: .now() + 2)
        XCTAssertTrue(unpauseDidStart)

        let viewModel = TwitchViewModel(
            cancelTokenValidationSchedule: {},
            restartTokenValidationSchedule: {})
        viewModel.twitchService = service
        let clearing = Task { @MainActor in
            await viewModel.clearCredentials()
        }
        try await Task.sleep(for: .milliseconds(100))

        XCTAssertEqual(operations.value, ["unpause"])
        XCTAssertEqual(KeychainService.loadTwitchToken(), "ACCESS")

        releaseUnpause.signal()
        try await unpausing.value
        let cleared = await clearing.value

        XCTAssertTrue(cleared)
        XCTAssertEqual(operations.value, ["unpause", "pause"])
        XCTAssertNil(KeychainService.loadTwitchToken())
    }

    func testFailedUnpersistedRefundBlocksClearUntilRetrySettles() async throws {
        storeManagedRewardIdentity(rewardID: "reward")
        try KeychainService.saveTwitchCredentialGrant(
            .init(
                accessToken: "ACCESS",
                refreshToken: "REFRESH",
                username: "wolf",
                userID: "broadcaster"))
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "wolfwave-containment-teardown-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let writeAttempts = ThreadSafeBox(0)
        let outbox = TwitchRedemptionResolutionOutbox(
            fileURL: directory.appending(path: "outbox.json"),
            atomicWriter: { data, url in
                var attempt = 0
                writeAttempts.mutate {
                    $0 += 1
                    attempt = $0
                }
                if attempt == 1 {
                    throw URLError(.cannotWriteToFile)
                }
                try data.write(to: url, options: .atomic)
            })
        let refundFails = ThreadSafeBox(true)
        let handler: MockURLProtocol.Handler = { request in
            if let response = Self.emptyUnfulfilledRedemptionsResponse(
                for: request) {
                return response
            }
            let body = Self.bodyString(of: request)
            let isRefund = body.contains(#""status":"CANCELED""#)
            let status = isRefund && refundFails.value ? 500 : 204
            return (
                MockURLProtocol.httpResponse(for: request, status: status),
                Data())
        }
        let service = TwitchChatService(
            channelPointsService: TwitchChannelPointsService(
                session: MockURLProtocol.makeSession(handler: handler)),
            redemptionResolutionOutbox: outbox,
            redemptionClientIDProvider: { "client" })
        await service.configureManagedRedemptionSessionForTesting()
        let retryGate = OAuthIdentityGate()
        await service.setRedemptionResolutionSleep { _ in
            await retryGate.suspend()
        }
        await service.handleChannelPointsRedemption([
            "event": [
                "id": "redemption",
                "broadcaster_user_id": "broadcaster",
                "user_name": "Viewer",
                "user_input": "A song",
                "reward": ["id": "reward"],
            ]
        ])
        let retryDidSuspend = await waitUntil { await retryGate.suspended }
        XCTAssertTrue(retryDidSuspend)

        let viewModel = TwitchViewModel(
            cancelTokenValidationSchedule: {},
            restartTokenValidationSchedule: {})
        viewModel.twitchService = service

        let firstClear = await viewModel.clearCredentials()

        XCTAssertFalse(firstClear)
        XCTAssertEqual(KeychainService.loadTwitchToken(), "ACCESS")

        refundFails.value = false
        await retryGate.resume()
        await service.awaitPaidRedemptionTasksForTeardownTesting()
        let secondClear = await viewModel.clearCredentials()

        XCTAssertTrue(secondClear)
        XCTAssertNil(KeychainService.loadTwitchToken())
    }

    func testOpaqueOutboxRiskBlocksNormalClearButFactoryOverrideCanDiscard()
        async throws {
        storeManagedRewardIdentity(rewardID: "reward")
        try KeychainService.saveTwitchCredentialGrant(
            .init(
                accessToken: "ACCESS",
                refreshToken: "REFRESH",
                username: "wolf",
                userID: "broadcaster"))
        enum InjectedFailure: Error {
            case quarantine
        }
        let directory = makeIsolatedTempDirectory(prefix: "wolfwave-opaque-teardown")
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appending(path: "outbox.json")
        try Data("not-json".utf8).write(to: file, options: .atomic)
        let outbox = TwitchRedemptionResolutionOutbox(
            fileURL: file,
            quarantineMover: { _, _ in throw InjectedFailure.quarantine })
        XCTAssertTrue(outbox.hasOpaqueRecoveryRisk())
        let pauses = ThreadSafeBox(0)
        let handler: MockURLProtocol.Handler = { request in
            if let response = Self.emptyUnfulfilledRedemptionsResponse(
                for: request) {
                return response
            }
            pauses.mutate { $0 += 1 }
            return (
                MockURLProtocol.httpResponse(for: request, status: 204),
                Data())
        }
        let service = TwitchChatService(
            channelPointsService: TwitchChannelPointsService(
                session: MockURLProtocol.makeSession(handler: handler)),
            redemptionResolutionOutbox: outbox,
            redemptionClientIDProvider: { "client" })
        await service.configureManagedRedemptionSessionForTesting()
        let viewModel = TwitchViewModel(
            cancelTokenValidationSchedule: {},
            restartTokenValidationSchedule: {})
        viewModel.twitchService = service

        let normalClear = await viewModel.clearCredentials()

        XCTAssertFalse(normalClear)
        XCTAssertEqual(KeychainService.loadTwitchToken(), "ACCESS")
        XCTAssertEqual(pauses.value, 1)

        let factoryClear = await viewModel.clearCredentials(
            discardOpaqueRedemptionRecovery: true)

        XCTAssertTrue(factoryClear)
        XCTAssertNil(KeychainService.loadTwitchToken())
        XCTAssertEqual(pauses.value, 2)
    }

    func testCredentiallessNoRewardOpaqueOutboxCannotReportSafe() async throws {
        enum InjectedFailure: Error {
            case quarantine
        }
        let directory = makeIsolatedTempDirectory(prefix: "wolfwave-opaque-fast-path")
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appending(path: "outbox.json")
        try Data("not-json".utf8).write(to: file, options: .atomic)
        let service = TwitchChatService(
            redemptionResolutionOutbox: TwitchRedemptionResolutionOutbox(
                fileURL: file,
                quarantineMover: { _, _ in throw InjectedFailure.quarantine }))

        let safe = await service.pauseManagedRewardBeforeCredentialTeardown()

        XCTAssertFalse(safe)
    }

    // MARK: - Durable redemption resolution replay

    func testUnknownPersistedRedemptionIntakeRefundsOnStartupAndDrains() async throws {
        storeManagedRewardIdentity(rewardID: "reward")
        try KeychainService.saveTwitchCredentialGrant(
            .init(accessToken: "ACCESS", userID: "broadcaster")
        )

        let directory = FileManager.default.temporaryDirectory
            .appending(path: "wolfwave-redemption-intake-replay-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let outbox = TwitchRedemptionResolutionOutbox(
            fileURL: directory.appending(path: "outbox.json"))
        _ = try outbox.enqueueIntake(
            broadcasterID: "broadcaster",
            rewardID: "reward",
            redemptionID: "redemption"
        )
        let requests = ThreadSafeBox<[URLRequest]>([])
        let handler: MockURLProtocol.Handler = { request in
            requests.mutate { $0.append(request) }
            return (
                MockURLProtocol.httpResponse(for: request, status: 204),
                Data()
            )
        }
        let service = TwitchChatService(
            channelPointsService: TwitchChannelPointsService(
                session: MockURLProtocol.makeSession(handler: handler)),
            redemptionResolutionOutbox: outbox,
            redemptionClientIDProvider: { "client" }
        )

        await service.replayPendingRedemptionResolutions()
        await service.awaitRedemptionResolutionWorkersForTesting()

        XCTAssertTrue(outbox.pendingItems().isEmpty)
        let request = try XCTUnwrap(requests.value.first)
        XCTAssertEqual(requests.value.count, 1)
        XCTAssertTrue(Self.bodyString(of: request).contains("CANCELED"))
    }

    func testPersistedRedemption404DrainsOnlyForExactManagedOwner() async throws {
        storeManagedRewardIdentity(rewardID: "reward")
        try KeychainService.saveTwitchCredentialGrant(
            .init(
                accessToken: "ACCESS",
                refreshToken: "REFRESH",
                username: "wolf",
                userID: "broadcaster"))
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "wolfwave-redemption-owner-404-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let outbox = TwitchRedemptionResolutionOutbox(
            fileURL: directory.appending(path: "outbox.json"))
        _ = try outbox.enqueue(
            broadcasterID: "broadcaster",
            rewardID: "reward",
            redemptionID: "redemption",
            resolution: .canceled)
        let handler: MockURLProtocol.Handler = { request in
            (
                MockURLProtocol.httpResponse(for: request, status: 404),
                Data("not found".utf8))
        }
        let service = TwitchChatService(
            channelPointsService: TwitchChannelPointsService(
                session: MockURLProtocol.makeSession(handler: handler)),
            redemptionResolutionOutbox: outbox,
            redemptionClientIDProvider: { "client" })

        await service.replayPendingRedemptionResolutions()
        await service.awaitRedemptionResolutionWorkersForTesting()

        XCTAssertTrue(outbox.pendingItems().isEmpty)
    }

    func testPersistedRedemption404StaysPendingAfterManagedOwnerChanges()
        async throws {
        storeManagedRewardIdentity(rewardID: "reward")
        try KeychainService.saveTwitchCredentialGrant(
            .init(
                accessToken: "ACCESS",
                refreshToken: "REFRESH",
                username: "wolf",
                userID: "broadcaster"))
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "wolfwave-redemption-stale-owner-404-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let outbox = TwitchRedemptionResolutionOutbox(
            fileURL: directory.appending(path: "outbox.json"))
        _ = try outbox.enqueue(
            broadcasterID: "broadcaster",
            rewardID: "reward",
            redemptionID: "redemption",
            resolution: .canceled)
        let patchEntered = DispatchSemaphore(value: 0)
        let releasePatch = DispatchSemaphore(value: 0)
        let handler: MockURLProtocol.Handler = { request in
            patchEntered.signal()
            guard releasePatch.wait(timeout: .now() + 2) == .success else {
                throw URLError(.timedOut)
            }
            return (
                MockURLProtocol.httpResponse(for: request, status: 404),
                Data("not found".utf8))
        }
        let service = TwitchChatService(
            channelPointsService: TwitchChannelPointsService(
                session: MockURLProtocol.makeSession(handler: handler)),
            redemptionResolutionOutbox: outbox,
            redemptionClientIDProvider: { "client" })

        await service.replayPendingRedemptionResolutions()
        let patchDidStart = await waitForSemaphore(
            patchEntered,
            timeout: .now() + 2)
        XCTAssertTrue(patchDidStart)
        let oldIdentity = TwitchManagedRewardStore.Identity(
            rewardID: "reward",
            broadcasterID: "broadcaster")
        XCTAssertTrue(TwitchManagedRewardStore.remove(matching: oldIdentity))
        XCTAssertTrue(
            TwitchManagedRewardStore.store(
                .init(
                    rewardID: "replacement",
                    broadcasterID: "other-account"),
                replacing: .none))
        releasePatch.signal()
        await service.awaitRedemptionResolutionWorkersForTesting()

        XCTAssertEqual(outbox.pendingItems().count, 1)
        XCTAssertEqual(
            TwitchManagedRewardStore.snapshot(),
            .owned(
                .init(
                    rewardID: "replacement",
                    broadcasterID: "other-account")))
    }

    func testPersistedRedemption401AdoptsRotatedTokenBeforeRetry() async throws {
        storeManagedRewardIdentity(rewardID: "reward")
        try KeychainService.saveTwitchCredentialGrant(
            .init(
                accessToken: "OLD_ACCESS",
                refreshToken: "OLD_REFRESH",
                username: "wolf",
                userID: "broadcaster"))
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "wolfwave-redemption-refresh-adopt-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let outbox = TwitchRedemptionResolutionOutbox(
            fileURL: directory.appending(path: "outbox.json"))
        _ = try outbox.enqueue(
            broadcasterID: "broadcaster",
            rewardID: "reward",
            redemptionID: "redemption",
            resolution: .canceled)

        let attempts = ThreadSafeBox(0)
        let authorizationHeaders = ThreadSafeBox<[String]>([])
        let handler: MockURLProtocol.Handler = { request in
            authorizationHeaders.mutate {
                $0.append(request.value(forHTTPHeaderField: "Authorization") ?? "")
            }
            var attempt = 0
            attempts.mutate {
                $0 += 1
                attempt = $0
            }
            let status = attempt == 1 ? 401 : 204
            return (MockURLProtocol.httpResponse(for: request, status: status), Data())
        }
        let staleReconnectCancelled = ThreadSafeBox(false)
        let refreshedExpectation = ThreadSafeBox<
            TwitchCredentialStore.AccessExpectation?>(nil)
        let service = TwitchChatService(
            channelPointsService: TwitchChannelPointsService(
                session: MockURLProtocol.makeSession(handler: handler)),
            redemptionResolutionOutbox: outbox,
            redemptionClientIDProvider: { "client" })
        await service.installRefreshAdoptionStateForTesting(
            token: "OLD_ACCESS",
            staleReconnectCancelled: staleReconnectCancelled)
        await service.setReactiveTokenRefresh { _, expected in
            let committed = try TwitchCredentialStore.shared.commitRefreshGrant(
                TwitchTokenResponse(
                    accessToken: "NEW_ACCESS",
                    refreshToken: "NEW_REFRESH",
                    expiresIn: nil),
                replacing: "OLD_REFRESH",
                expected: expected)
            guard committed else { return .superseded }
            let refreshed = expected.replacingAccessToken("NEW_ACCESS")
            refreshedExpectation.value = refreshed
            return .refreshed("NEW_ACCESS")
        }

        await service.replayPendingRedemptionResolutions()
        await service.awaitRedemptionResolutionWorkersForTesting()

        let actorState = await service.refreshActorStateForTesting()
        let reconnectWasRescheduled = await service.hasReconnectTaskForTesting()
        let staleReconnectWasCancelled = await waitUntil {
            staleReconnectCancelled.value
        }
        await service.cancelRefreshReconnectForTesting()
        XCTAssertEqual(attempts.value, 2)
        XCTAssertEqual(
            authorizationHeaders.value,
            ["Bearer OLD_ACCESS", "Bearer NEW_ACCESS"])
        XCTAssertEqual(KeychainService.loadTwitchToken(), "NEW_ACCESS")
        XCTAssertEqual(actorState.oauthToken, "NEW_ACCESS")
        XCTAssertEqual(actorState.reconnectToken, "NEW_ACCESS")
        XCTAssertEqual(
            TwitchCredentialStore.shared.connectionSnapshot()?.accessExpectation,
            refreshedExpectation.value)
        XCTAssertTrue(staleReconnectWasCancelled)
        XCTAssertTrue(reconnectWasRescheduled)
        XCTAssertTrue(outbox.pendingItems().isEmpty)
    }

    func testPersistedRedemptionReplayHonorsRetryAfterAndDrains() async throws {
        storeManagedRewardIdentity(rewardID: "reward")
        try KeychainService.saveTwitchCredentialGrant(
            .init(accessToken: "ACCESS", userID: "broadcaster")
        )

        let directory = FileManager.default.temporaryDirectory
            .appending(path: "wolfwave-redemption-replay-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let outbox = TwitchRedemptionResolutionOutbox(
            fileURL: directory.appending(path: "outbox.json"))
        _ = try outbox.enqueue(
            broadcasterID: "broadcaster",
            rewardID: "reward",
            redemptionID: "redemption",
            resolution: .canceled
        )

        let attempts = ThreadSafeBox(0)
        let delays = ThreadSafeBox<[Duration]>([])
        let requests = ThreadSafeBox<[URLRequest]>([])
        let handler: MockURLProtocol.Handler = { request in
            requests.mutate { $0.append(request) }
            var attempt = 0
            attempts.mutate {
                $0 += 1
                attempt = $0
            }
            if attempt == 1 {
                return (
                    MockURLProtocol.httpResponse(
                        for: request,
                        status: 429,
                        headers: ["Retry-After": "12"]),
                    Data()
                )
            }
            return (
                MockURLProtocol.httpResponse(for: request, status: 204),
                Data()
            )
        }

        let channelPoints = TwitchChannelPointsService(
            session: MockURLProtocol.makeSession(handler: handler))
        let service = TwitchChatService(
            channelPointsService: channelPoints,
            redemptionResolutionOutbox: outbox,
            redemptionClientIDProvider: { "client" }
        )
        await service.setRedemptionResolutionSleep { delay in
            delays.mutate { $0.append(delay) }
        }
        await service.replayPendingRedemptionResolutions()
        await service.awaitRedemptionResolutionWorkersForTesting()

        XCTAssertEqual(attempts.value, 2)
        XCTAssertEqual(delays.value, [.seconds(12)])
        XCTAssertTrue(outbox.pendingItems().isEmpty)
        let captured = requests.value
        XCTAssertEqual(captured.count, 2)
        let first = try XCTUnwrap(captured.first)
        XCTAssertEqual(first.httpMethod, "PATCH")
        XCTAssertEqual(first.value(forHTTPHeaderField: "Authorization"), "Bearer ACCESS")
    }

    func testPersistedRedemptionKeepsRetryingAfterInitialTransientBurst() async throws {
        storeManagedRewardIdentity(rewardID: "reward")
        try KeychainService.saveTwitchCredentialGrant(
            .init(accessToken: "ACCESS", userID: "broadcaster")
        )

        let directory = FileManager.default.temporaryDirectory
            .appending(path: "wolfwave-redemption-long-drain-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let outbox = TwitchRedemptionResolutionOutbox(
            fileURL: directory.appending(path: "outbox.json"))
        _ = try outbox.enqueue(
            broadcasterID: "broadcaster",
            rewardID: "reward",
            redemptionID: "redemption",
            resolution: .fulfilled
        )

        let attempts = ThreadSafeBox(0)
        let delays = ThreadSafeBox<[Duration]>([])
        let handler: MockURLProtocol.Handler = { request in
            var attempt = 0
            attempts.mutate {
                $0 += 1
                attempt = $0
            }
            let status = attempt <= 4 ? 503 : 204
            return (MockURLProtocol.httpResponse(for: request, status: status), Data())
        }

        let service = TwitchChatService(
            channelPointsService: TwitchChannelPointsService(
                session: MockURLProtocol.makeSession(handler: handler)),
            redemptionResolutionOutbox: outbox,
            redemptionClientIDProvider: { "client" }
        )
        await service.setRedemptionResolutionSleep { delay in
            delays.mutate { $0.append(delay) }
        }
        await service.replayPendingRedemptionResolutions()
        await service.awaitRedemptionResolutionWorkersForTesting()

        XCTAssertEqual(attempts.value, 5)
        XCTAssertEqual(
            delays.value,
            [.seconds(1), .seconds(2), .seconds(4), .seconds(8)]
        )
        XCTAssertTrue(outbox.pendingItems().isEmpty)
    }

    func testRedemption401CannotRefreshOrExpireReplacementAccount() async throws {
        storeManagedRewardIdentity(rewardID: "reward")
        await TwitchTokenRefresher.invalidateSession()
        Preferences.setTwitchReauthNeeded(false)
        defer { Preferences.setTwitchReauthNeeded(false) }
        try KeychainService.saveTwitchCredentialGrant(
            .init(
                accessToken: "ACCESS-A",
                refreshToken: "REFRESH-A",
                username: "account-a",
                userID: "broadcaster"
            )
        )

        let directory = FileManager.default.temporaryDirectory
            .appending(path: "wolfwave-redemption-account-switch-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let outbox = TwitchRedemptionResolutionOutbox(
            fileURL: directory.appending(path: "outbox.json"))
        _ = try outbox.enqueue(
            broadcasterID: "broadcaster",
            rewardID: "reward",
            redemptionID: "redemption",
            resolution: .canceled
        )

        let patchEntered = DispatchSemaphore(value: 0)
        let releasePatch = DispatchSemaphore(value: 0)
        let requests = ThreadSafeBox(0)
        let handler: MockURLProtocol.Handler = { request in
            requests.mutate { $0 += 1 }
            XCTAssertEqual(
                request.value(forHTTPHeaderField: "Authorization"),
                "Bearer ACCESS-A"
            )
            patchEntered.signal()
            guard releasePatch.wait(timeout: .now() + 2) == .success else {
                throw URLError(.timedOut)
            }
            return (
                MockURLProtocol.httpResponse(for: request, status: 401),
                Data()
            )
        }
        let service = TwitchChatService(
            channelPointsService: TwitchChannelPointsService(
                session: MockURLProtocol.makeSession(handler: handler)),
            redemptionResolutionOutbox: outbox,
            redemptionClientIDProvider: { "client" }
        )

        await service.replayPendingRedemptionResolutions()
        let entered = await waitForSemaphore(
            patchEntered,
            timeout: .now() + 2
        )
        XCTAssertTrue(entered)

        try TwitchCredentialStore.shared.replaceWithManualAccessToken("ACCESS-B")
        releasePatch.signal()
        await service.awaitRedemptionResolutionWorkersForTesting()

        XCTAssertEqual(KeychainService.loadTwitchToken(), "ACCESS-B")
        XCTAssertFalse(Preferences.twitchReauthNeeded)
        XCTAssertEqual(requests.value, 1)
        XCTAssertEqual(outbox.pendingItems().count, 1)
    }

    func testClearingCredentialsDuringChannelLookupCancelsJoinBeforeSocket() async throws {
        try KeychainService.saveTwitchCredentialGrant(
            .init(
                accessToken: "ACCESS",
                username: "Bot",
                userID: "bot-user",
                channelID: "channel"
            )
        )

        let requestEntered = DispatchSemaphore(value: 0)
        let releaseResponse = DispatchSemaphore(value: 0)
        let requests = ThreadSafeBox<[URLRequest]>([])
        let handler: MockURLProtocol.Handler = { request in
            requests.mutate { $0.append(request) }
            requestEntered.signal()
            guard releaseResponse.wait(timeout: .now() + 2) == .success else {
                throw URLError(.timedOut)
            }
            return (
                MockURLProtocol.httpResponse(for: request, status: 200),
                Data(#"{"data":[{"id":"broadcaster","login":"channel","display_name":"Channel"}]}"#.utf8)
            )
        }

        let service = TwitchChatService(
            helixHTTPClient: HTTPClient(
                session: MockURLProtocol.makeSession(handler: handler)))
        let connection = Task {
            do {
                try await service.connectToChannel(
                    channelName: "channel",
                    token: "ACCESS",
                    clientID: "client"
                )
                return false
            } catch is CancellationError {
                return true
            } catch {
                return false
            }
        }

        let entered = await waitForSemaphore(
            requestEntered,
            timeout: .now() + 2
        )
        XCTAssertTrue(entered)
        try TwitchCredentialStore.shared.clearCredentials(includingChannel: false)
        releaseResponse.signal()

        let wasCancelled = await connection.value
        XCTAssertTrue(wasCancelled)
        XCTAssertFalse(service.currentlyConnected)
        let reconnectChannel = await service.reconnectChannelForTesting()
        XCTAssertNil(reconnectChannel)
        let captured = requests.value
        XCTAssertEqual(captured.count, 1)
        let request = try XCTUnwrap(captured.first)
        XCTAssertTrue(request.url?.absoluteString.contains("login=channel") == true)
    }

    // MARK: - Keychain accessor round-trip

    func testRefreshTokenKeychainRoundTrip() throws {
        XCTAssertNil(KeychainService.loadTwitchRefreshToken())
        try KeychainService.saveTwitchCredentialGrant(
            .init(accessToken: "AT-123", refreshToken: "RT-123")
        )
        XCTAssertEqual(KeychainService.loadTwitchRefreshToken(), "RT-123")
        try KeychainService.deleteTwitchCredentialGrant()
        XCTAssertNil(KeychainService.loadTwitchRefreshToken())
    }
}

nonisolated struct TwitchRefreshActorSnapshot: Sendable {
    let oauthToken: String?
    let reconnectToken: String?
}

nonisolated struct ManagedRedemptionIdentitySnapshot: Sendable {
    let broadcasterID: String?
    let botID: String?
    let oauthToken: String?
    let clientID: String?
}

nonisolated struct EventSubTransportSnapshot: Sendable {
    let sourceIsCurrent: Bool
    let targetIsCurrent: Bool
    let hasReconnectTask: Bool
}

extension TwitchChatService {
    func runManagedRewardUnpauseUnderSetupLeaseForTesting(
        rewardID: String
    ) async throws {
        guard let broadcasterID,
              let oauthToken,
              let clientID,
              let lease = TwitchRedemptionTeardownGate.beginSetup(
                serviceID: ObjectIdentifier(self),
                broadcasterID: broadcasterID,
                generation: channelOwnershipGeneration) else {
            throw CancellationError()
        }
        defer { TwitchRedemptionTeardownGate.endSetup(lease) }
        try await channelPointsService.setRewardPaused(
            credentials: .init(
                broadcasterID: broadcasterID,
                token: oauthToken,
                clientID: clientID),
            rewardID: rewardID,
            paused: false)
    }

    func installTeardownLiveIntakeForTesting(
        item: TwitchRedemptionResolutionOutbox.Item,
        operation: @escaping @Sendable () async -> Void
    ) {
        redemptionTasks[item.id] = Task { [weak self] in
            await operation()
            await self?.finishTeardownLiveIntakeForTesting(item.id)
        }
    }

    func finishTeardownLiveIntakeForTesting(_ id: UUID) {
        redemptionTasks[id] = nil
    }

    func awaitPaidRedemptionTasksForTeardownTesting() async {
        let tasks = Array(paidRedemptionTasks.values)
        for task in tasks {
            await task.value
        }
    }

    func awaitRedemptionResolutionWorkersForTesting() async {
        let workers = Array(redemptionResolutionTasks.values)
        for worker in workers {
            await worker.value
        }
    }

    func configureManagedRedemptionSessionForTesting(
        broadcasterID: String = "broadcaster",
        token: String = "ACCESS",
        clientID: String = "client",
        sessionID: String = "eventsub-session"
    ) {
        _ = beginConnectionAttempt()
        self.broadcasterID = broadcasterID
        botID = broadcasterID
        oauthToken = token
        self.clientID = clientID
        self.sessionID = sessionID
    }

    func managedRedemptionIdentityForTesting() -> ManagedRedemptionIdentitySnapshot {
        ManagedRedemptionIdentitySnapshot(
            broadcasterID: broadcasterID,
            botID: botID,
            oauthToken: oauthToken,
            clientID: clientID)
    }

    func reconnectChannelForTesting() -> String? {
        reconnectChannelName
    }

    func installRefreshAdoptionStateForTesting(
        token: String,
        staleReconnectCancelled: ThreadSafeBox<Bool>? = nil
    ) {
        oauthToken = token
        reconnectToken = token
        reconnectChannelName = "channel"
        reconnectClientID = "client"
        guard let staleReconnectCancelled else { return }
        reconnectTask = Task {
            do {
                try await Task.sleep(for: .seconds(60))
            } catch {
                // Cancellation is the expected signal when adoption reschedules.
            }
            if Task.isCancelled {
                staleReconnectCancelled.set(true)
            }
        }
    }

    func refreshActorStateForTesting() -> TwitchRefreshActorSnapshot {
        TwitchRefreshActorSnapshot(
            oauthToken: oauthToken,
            reconnectToken: reconnectToken
        )
    }

    func cancelRefreshReconnectForTesting() {
        reconnectTask?.cancel()
        reconnectTask = nil
    }

    func hasReconnectTaskForTesting() -> Bool {
        reconnectTask != nil
    }

    func supersedeChannelOwnershipForTesting() {
        channelOwnershipGeneration &+= 1
    }

    func installLiveChatSessionForTesting(
        _ source: URLSessionWebSocketTask,
        actorToken: String = "OLD_AT",
        broadcasterID: String = "broadcaster",
        botID: String = "bot-user",
        clientID: String = "client",
        reconnectChannel: String = "channel"
    ) -> EventSubReceiveContext {
        _ = beginConnectionAttempt()
        self.broadcasterID = broadcasterID
        self.botID = botID
        oauthToken = actorToken
        self.clientID = clientID
        reconnectChannelName = reconnectChannel
        reconnectToken = actorToken
        reconnectClientID = clientID
        webSocketTask = source
        welcomedWebSocketTask = source
        sessionID = "source-session"
        setConnected(true)
        return EventSubReceiveContext(
            generation: connectionGeneration,
            webSocketTask: source)
    }

    func eventSubTransportSnapshotForTesting(
        source: URLSessionWebSocketTask,
        target: URLSessionWebSocketTask
    ) -> EventSubTransportSnapshot {
        EventSubTransportSnapshot(
            sourceIsCurrent: webSocketTask === source,
            targetIsCurrent: webSocketTask === target,
            hasReconnectTask: reconnectTask != nil)
    }
}

actor OAuthIdentityGate {
    private(set) var suspended = false
    private var released = false
    private var resumeWaiters: [CheckedContinuation<Void, Never>] = []

    func suspend() async {
        suspended = true
        guard !released else { return }
        await withCheckedContinuation { continuation in
            resumeWaiters.append(continuation)
        }
    }

    func resume() {
        released = true
        resumeWaiters.forEach { $0.resume() }
        resumeWaiters.removeAll()
    }
}
