//
//  HelixClientTests.swift
//  WolfWave
//
//  Created by Nathanial Henniges on 2026-05-28.
//  Copyright © 2026 MrDemonWolf, Inc. All rights reserved.
//

import XCTest

@testable import WolfWave

// MARK: - HelixClientTests

/// Exercises `HelixClient` against `MockURLProtocol`, covering auth header
/// construction, JSON body encoding, status-specific error mapping (401, 429),
/// and decode failures.
@MainActor
final class HelixClientTests: XCTestCase {

    private var helix: HelixClient!
    private let credentials = HelixClient.Credentials(token: "tok_abc", clientID: "client_xyz")

    override func setUp() {
        super.setUp()
        helix = HelixClient(http: HTTPClient(session: MockURLProtocol.makeSession()))
    }

    override func tearDown() {
        MockURLProtocol.reset()
        helix = nil
        super.tearDown()
    }

    private func url() -> URL {
        URL(string: "https://api.twitch.tv/helix/test")!
    }

    private struct Reward: Decodable, Equatable {
        struct Item: Decodable, Equatable {
            let id: String
            let cost: Int
        }
        let data: [Item]
    }

    // MARK: - Header Construction

    func testHeadersIncludeBearerTokenAndClientID() async throws {
        nonisolated(unsafe) var captured: URLRequest?
        MockURLProtocol.requestHandler = { request in
            captured = request
            return (
                MockURLProtocol.httpResponse(for: request, status: 200),
                Data(#"{"data":[]}"#.utf8)
            )
        }

        let _: Reward = try await helix.get(url: url(), credentials: credentials)

        let auth = captured?.value(forHTTPHeaderField: "Authorization")
        let clientID = captured?.value(forHTTPHeaderField: "Client-Id")
        let contentType = captured?.value(forHTTPHeaderField: "Content-Type")
        XCTAssertEqual(auth, "Bearer tok_abc")
        XCTAssertEqual(clientID, "client_xyz")
        XCTAssertEqual(contentType, "application/json")
        XCTAssertEqual(captured?.httpMethod, "GET")
    }

    // MARK: - Success Decoding

    func testGetDecodesSnakeCaseResponse() async throws {
        MockURLProtocol.requestHandler = { request in
            (
                MockURLProtocol.httpResponse(for: request, status: 200),
                Data(#"{"data":[{"id":"r1","cost":100}]}"#.utf8)
            )
        }

        let reward: Reward = try await helix.get(url: url(), credentials: credentials)
        XCTAssertEqual(reward, Reward(data: [.init(id: "r1", cost: 100)]))
    }

    func testPostSerializesJSONBody() async throws {
        nonisolated(unsafe) var capturedBody: Data?
        MockURLProtocol.requestHandler = { request in
            if let stream = request.httpBodyStream {
                stream.open()
                defer { stream.close() }
                var buffer = Data()
                let bufferSize = 1024
                let bytes = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
                defer { bytes.deallocate() }
                while stream.hasBytesAvailable {
                    let read = stream.read(bytes, maxLength: bufferSize)
                    if read > 0 { buffer.append(bytes, count: read) }
                    if read <= 0 { break }
                }
                capturedBody = buffer
            }
            return (
                MockURLProtocol.httpResponse(for: request, status: 200),
                Data(#"{"data":[{"id":"r1","cost":50}]}"#.utf8)
            )
        }

        let _: Reward = try await helix.post(
            url: url(), credentials: credentials, body: ["cost": 50, "title": "demo"])

        let json = try XCTUnwrap(
            capturedBody.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
        )
        XCTAssertEqual(json["cost"] as? Int, 50)
        XCTAssertEqual(json["title"] as? String, "demo")
    }

    // MARK: - Status Mapping

    func testThrowsUnauthorizedOn401() async {
        MockURLProtocol.requestHandler = { request in
            (
                MockURLProtocol.httpResponse(for: request, status: 401),
                Data("token revoked".utf8)
            )
        }

        do {
            let _: Reward = try await helix.get(url: url(), credentials: credentials)
            XCTFail("Expected unauthorized error")
        } catch let HelixClient.HelixError.unauthorized(body) {
            XCTAssertEqual(body, "token revoked")
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testThrowsRateLimitedOn429() async {
        MockURLProtocol.requestHandler = { request in
            (
                MockURLProtocol.httpResponse(for: request, status: 429),
                Data("slow down".utf8)
            )
        }

        do {
            let _: Reward = try await helix.get(url: url(), credentials: credentials)
            XCTFail("Expected rateLimited error")
        } catch let HelixClient.HelixError.rateLimited(body) {
            XCTAssertEqual(body, "slow down")
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testThrowsHTTPOnOther4xx() async {
        MockURLProtocol.requestHandler = { request in
            (
                MockURLProtocol.httpResponse(for: request, status: 404),
                Data("not found".utf8)
            )
        }

        do {
            let _: Reward = try await helix.get(url: url(), credentials: credentials)
            XCTFail("Expected http error")
        } catch let HelixClient.HelixError.http(status, body) {
            XCTAssertEqual(status, 404)
            XCTAssertEqual(body, "not found")
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testThrowsHTTPOn5xx() async {
        MockURLProtocol.requestHandler = { request in
            (
                MockURLProtocol.httpResponse(for: request, status: 503),
                Data("upstream".utf8)
            )
        }

        do {
            let _: Reward = try await helix.get(url: url(), credentials: credentials)
            XCTFail("Expected http error")
        } catch let HelixClient.HelixError.http(status, _) {
            XCTAssertEqual(status, 503)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    // MARK: - Decoding Failures

    func testThrowsDecodingFailedOnMalformedJSON() async {
        MockURLProtocol.requestHandler = { request in
            (
                MockURLProtocol.httpResponse(for: request, status: 200),
                Data("not json".utf8)
            )
        }

        do {
            let _: Reward = try await helix.get(url: url(), credentials: credentials)
            XCTFail("Expected decoding error")
        } catch HelixClient.HelixError.decodingFailed {
            // expected
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    // MARK: - Raw / JSON Object Paths

    func testSendJSONReturnsParsedDictionary() async throws {
        MockURLProtocol.requestHandler = { request in
            (
                MockURLProtocol.httpResponse(for: request, status: 200),
                Data(#"{"ok":true,"count":2}"#.utf8)
            )
        }

        let json = try await helix.sendJSON(
            url: url(), method: "POST", credentials: credentials, body: ["x": 1])

        XCTAssertEqual(json?["ok"] as? Bool, true)
        XCTAssertEqual(json?["count"] as? Int, 2)
    }

    func testSendJSONReturnsNilForEmpty204() async throws {
        MockURLProtocol.requestHandler = { request in
            (
                MockURLProtocol.httpResponse(for: request, status: 204),
                Data()
            )
        }

        let json = try await helix.sendJSON(
            url: url(), method: "PATCH", credentials: credentials, body: ["cost": 100])

        XCTAssertNil(json)
    }

    func testSendRawReturnsStatusForBranching() async throws {
        MockURLProtocol.requestHandler = { request in
            (
                MockURLProtocol.httpResponse(for: request, status: 403),
                Data("missing scope".utf8)
            )
        }

        let (data, status) = try await helix.sendRaw(
            url: url(), method: "POST", credentials: credentials, body: nil)

        XCTAssertEqual(status, 403)
        XCTAssertEqual(String(data: data, encoding: .utf8), "missing scope")
    }

    // MARK: - Transport Errors

    func testTransportErrorIsMapped() async {
        MockURLProtocol.requestHandler = { _ in
            throw URLError(.notConnectedToInternet)
        }

        do {
            let _: Reward = try await helix.get(url: url(), credentials: credentials)
            XCTFail("Expected transport error")
        } catch HelixClient.HelixError.transport {
            // expected
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
}
