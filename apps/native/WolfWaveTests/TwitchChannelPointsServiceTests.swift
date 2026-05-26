//
//  TwitchChannelPointsServiceTests.swift
//  WolfWaveTests
//
//  Created by MrDemonWolf, Inc. on 5/23/26.
//

import XCTest

@testable import WolfWave

// MARK: - Sendable Capture Box

/// Thread-safe value box used to capture state from inside `@Sendable`
/// `MockURLProtocol` request handlers without violating strict concurrency.
private final class Box<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var storedValue: Value

    init(_ value: Value) {
        self.storedValue = value
    }

    var value: Value {
        get {
            lock.lock()
            defer { lock.unlock() }
            return storedValue
        }
        set {
            lock.lock()
            storedValue = newValue
            lock.unlock()
        }
    }

    func mutate(_ body: (inout Value) -> Void) {
        lock.lock()
        body(&storedValue)
        lock.unlock()
    }
}

// MARK: - TwitchChannelPointsServiceTests

/// Covers `TwitchChannelPointsService` Helix request construction and reward
/// reconciliation, driven by `MockURLProtocol`. No real network traffic.
final class TwitchChannelPointsServiceTests: XCTestCase {

    private let storageKey = AppConstants.UserDefaults.songRequestChannelPointsRewardID

    private let creds = TwitchChannelPointsService.Credentials(
        broadcasterID: "12345",
        token: "tok_abc",
        clientID: "client_xyz"
    )

    override func setUp() {
        super.setUp()
        UserDefaults.standard.removeObject(forKey: storageKey)
    }

    override func tearDown() {
        MockURLProtocol.reset()
        UserDefaults.standard.removeObject(forKey: storageKey)
        super.tearDown()
    }

    // MARK: - Helpers

    private func makeService() -> TwitchChannelPointsService {
        TwitchChannelPointsService(session: MockURLProtocol.makeSession())
    }

    private static func bodyJSON(_ request: URLRequest) -> [String: Any] {
        // URLProtocol exposes the body via `httpBodyStream`, not `httpBody`.
        guard let stream = request.httpBodyStream else { return [:] }
        stream.open()
        defer { stream.close() }
        var data = Data()
        let buf = UnsafeMutablePointer<UInt8>.allocate(capacity: 4096)
        defer { buf.deallocate() }
        while stream.hasBytesAvailable {
            let read = stream.read(buf, maxLength: 4096)
            if read <= 0 { break }
            data.append(buf, count: read)
        }
        return (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
    }

    private static func encodeJSON(_ object: Any) -> Data {
        // swiftlint:disable:next force_try
        try! JSONSerialization.data(withJSONObject: object)
    }

    // MARK: - Request Construction

    func testEnsureRewardCreatesRewardWhenNoStoredID() async throws {
        let captured = Box<URLRequest?>(nil)
        MockURLProtocol.requestHandler = { request in
            captured.value = request
            let body: [String: Any] = ["data": [["id": "reward_new"]]]
            return (
                MockURLProtocol.httpResponse(for: request, status: 200),
                Self.encodeJSON(body)
            )
        }

        let service = makeService()
        let rewardID = try await service.ensureReward(credentials: creds, cost: 500)

        XCTAssertEqual(rewardID, "reward_new")
        XCTAssertEqual(UserDefaults.standard.string(forKey: storageKey), "reward_new")

        let request = try XCTUnwrap(captured.value)
        XCTAssertEqual(request.httpMethod, "POST")
        let url = try XCTUnwrap(request.url)
        XCTAssertTrue(url.path.hasSuffix("/channel_points/custom_rewards"))
        let comps = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
        XCTAssertEqual(comps.queryItems?.first(where: { $0.name == "broadcaster_id" })?.value, "12345")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer tok_abc")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Client-Id"), "client_xyz")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")

        let payload = Self.bodyJSON(request)
        XCTAssertEqual(payload["title"] as? String, AppConstants.Twitch.songRequestRewardTitle)
        XCTAssertEqual(payload["cost"] as? Int, 500)
        XCTAssertEqual(payload["is_user_input_required"] as? Bool, true)
        XCTAssertNotNil(payload["prompt"] as? String)
    }

    func testUpdateRewardCostSendsPatchWithCorrectQueryAndBody() async throws {
        let captured = Box<URLRequest?>(nil)
        MockURLProtocol.requestHandler = { request in
            captured.value = request
            return (MockURLProtocol.httpResponse(for: request, status: 204), Data())
        }

        try await makeService().updateRewardCost(
            credentials: creds, rewardID: "reward_abc", cost: 1000)

        let request = try XCTUnwrap(captured.value)
        XCTAssertEqual(request.httpMethod, "PATCH")
        let comps = try XCTUnwrap(
            URLComponents(url: try XCTUnwrap(request.url), resolvingAgainstBaseURL: false))
        let items = Dictionary(
            uniqueKeysWithValues: (comps.queryItems ?? []).map { ($0.name, $0.value ?? "") })
        XCTAssertEqual(items["broadcaster_id"], "12345")
        XCTAssertEqual(items["id"], "reward_abc")

        let payload = Self.bodyJSON(request)
        XCTAssertEqual(payload["cost"] as? Int, 1000)
    }

    func testResolveRedemptionFulfilledSendsFULFILLED() async throws {
        let captured = Box<URLRequest?>(nil)
        MockURLProtocol.requestHandler = { request in
            captured.value = request
            return (MockURLProtocol.httpResponse(for: request, status: 204), Data())
        }

        try await makeService().resolveRedemption(
            credentials: creds,
            rewardID: "reward_abc",
            redemptionID: "redemp_1",
            as: .fulfilled
        )

        let request = try XCTUnwrap(captured.value)
        XCTAssertEqual(request.httpMethod, "PATCH")
        let comps = try XCTUnwrap(
            URLComponents(url: try XCTUnwrap(request.url), resolvingAgainstBaseURL: false))
        XCTAssertTrue(comps.path.hasSuffix("/channel_points/custom_rewards/redemptions"))
        let items = Dictionary(
            uniqueKeysWithValues: (comps.queryItems ?? []).map { ($0.name, $0.value ?? "") })
        XCTAssertEqual(items["broadcaster_id"], "12345")
        XCTAssertEqual(items["reward_id"], "reward_abc")
        XCTAssertEqual(items["id"], "redemp_1")

        XCTAssertEqual(Self.bodyJSON(request)["status"] as? String, "FULFILLED")
    }

    func testResolveRedemptionCanceledSendsCANCELED() async throws {
        let captured = Box<URLRequest?>(nil)
        MockURLProtocol.requestHandler = { request in
            captured.value = request
            return (MockURLProtocol.httpResponse(for: request, status: 204), Data())
        }

        try await makeService().resolveRedemption(
            credentials: creds,
            rewardID: "reward_abc",
            redemptionID: "redemp_2",
            as: .canceled
        )

        let request = try XCTUnwrap(captured.value)
        XCTAssertEqual(Self.bodyJSON(request)["status"] as? String, "CANCELED")
    }

    // MARK: - Reconcile Diff

    func testEnsureRewardReturnsStoredIDWhenHelixConfirmsExistence() async throws {
        UserDefaults.standard.set("existing_id", forKey: storageKey)

        struct State { var callCount = 0; var lastMethod: String?; var lastURL: URL? }
        let state = Box(State())

        MockURLProtocol.requestHandler = { request in
            state.mutate { stored in
                stored.callCount += 1
                stored.lastMethod = request.httpMethod
                stored.lastURL = request.url
            }
            let body: [String: Any] = ["data": [["id": "existing_id"]]]
            return (
                MockURLProtocol.httpResponse(for: request, status: 200),
                Self.encodeJSON(body)
            )
        }

        let rewardID = try await makeService().ensureReward(credentials: creds, cost: 500)

        XCTAssertEqual(rewardID, "existing_id")
        let snap = state.value
        XCTAssertEqual(snap.callCount, 1, "Should not POST when GET confirms reward")
        XCTAssertEqual(snap.lastMethod, "GET")
        let comps = try XCTUnwrap(
            URLComponents(url: try XCTUnwrap(snap.lastURL), resolvingAgainstBaseURL: false))
        let items = Dictionary(
            uniqueKeysWithValues: (comps.queryItems ?? []).map { ($0.name, $0.value ?? "") })
        XCTAssertEqual(items["only_manageable_rewards"], "true")
        XCTAssertEqual(items["id"], "existing_id")
    }

    func testEnsureRewardCreatesFreshWhenStoredIDIsUnknown() async throws {
        UserDefaults.standard.set("stale_id", forKey: storageKey)
        let methods = Box<[String]>([])

        MockURLProtocol.requestHandler = { request in
            methods.mutate { $0.append(request.httpMethod ?? "") }
            if request.httpMethod == "GET" {
                let body: [String: Any] = ["data": []]
                return (
                    MockURLProtocol.httpResponse(for: request, status: 200),
                    Self.encodeJSON(body)
                )
            }
            let body: [String: Any] = ["data": [["id": "fresh_id"]]]
            return (
                MockURLProtocol.httpResponse(for: request, status: 200),
                Self.encodeJSON(body)
            )
        }

        let rewardID = try await makeService().ensureReward(credentials: creds, cost: 200)

        XCTAssertEqual(rewardID, "fresh_id")
        XCTAssertEqual(methods.value, ["GET", "POST"])
        XCTAssertEqual(UserDefaults.standard.string(forKey: storageKey), "fresh_id")
    }

    func testEnsureRewardTreats404AsMissingAndRecreates() async throws {
        UserDefaults.standard.set("gone_id", forKey: storageKey)
        let methods = Box<[String]>([])

        MockURLProtocol.requestHandler = { request in
            methods.mutate { $0.append(request.httpMethod ?? "") }
            if request.httpMethod == "GET" {
                return (
                    MockURLProtocol.httpResponse(for: request, status: 404),
                    Data("not found".utf8)
                )
            }
            let body: [String: Any] = ["data": [["id": "recreated_id"]]]
            return (
                MockURLProtocol.httpResponse(for: request, status: 200),
                Self.encodeJSON(body)
            )
        }

        let rewardID = try await makeService().ensureReward(credentials: creds, cost: 200)

        XCTAssertEqual(rewardID, "recreated_id")
        XCTAssertEqual(methods.value, ["GET", "POST"])
    }

    // MARK: - Errors

    func testCreateRewardMalformedResponseThrows() async {
        UserDefaults.standard.removeObject(forKey: storageKey)
        MockURLProtocol.requestHandler = { request in
            let body: [String: Any] = ["data": []]
            return (
                MockURLProtocol.httpResponse(for: request, status: 200),
                Self.encodeJSON(body)
            )
        }

        do {
            _ = try await makeService().ensureReward(credentials: creds, cost: 200)
            XCTFail("Expected .malformedResponse")
        } catch TwitchChannelPointsService.RewardError.malformedResponse {
            // expected
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testNon2xxStatusThrowsHTTPError() async {
        MockURLProtocol.requestHandler = { request in
            (
                MockURLProtocol.httpResponse(for: request, status: 401),
                Data("unauthorized".utf8)
            )
        }

        do {
            try await makeService().updateRewardCost(
                credentials: creds, rewardID: "x", cost: 1)
            XCTFail("Expected .http")
        } catch TwitchChannelPointsService.RewardError.http(let status, let body) {
            XCTAssertEqual(status, 401)
            XCTAssertEqual(body, "unauthorized")
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testTransportFailureThrowsTransportError() async {
        struct StubError: Error {}
        MockURLProtocol.requestHandler = { _ in throw StubError() }

        do {
            try await makeService().updateRewardCost(
                credentials: creds, rewardID: "x", cost: 1)
            XCTFail("Expected .transport")
        } catch TwitchChannelPointsService.RewardError.transport {
            // expected
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    // MARK: - Enum / Description

    func testResolutionRawValuesMatchHelix() {
        XCTAssertEqual(TwitchChannelPointsService.Resolution.fulfilled.rawValue, "FULFILLED")
        XCTAssertEqual(TwitchChannelPointsService.Resolution.canceled.rawValue, "CANCELED")
    }

    func testRewardErrorDescriptions() {
        let http = TwitchChannelPointsService.RewardError.http(status: 404, body: "oops")
        XCTAssertTrue(http.errorDescription?.contains("404") ?? false)
        XCTAssertTrue(http.errorDescription?.contains("oops") ?? false)

        struct StubError: LocalizedError { var errorDescription: String? { "boom" } }
        let transport = TwitchChannelPointsService.RewardError.transport(underlying: StubError())
        XCTAssertTrue(transport.errorDescription?.contains("boom") ?? false)

        let malformed = TwitchChannelPointsService.RewardError.malformedResponse
        XCTAssertNotNil(malformed.errorDescription)
    }
}
