//
//  HTTPClientTests.swift
//  WolfWaveTests
//
//  Created by MrDemonWolf, Inc. on 5/22/26.
//

import XCTest

@testable import WolfWave

// MARK: - HTTPClientTests

/// Exercises `HTTPClient` request/response handling against `MockURLProtocol`,
/// covering JSON decoding, status validation, and error mapping.
final class HTTPClientTests: XCTestCase {

    private var client: HTTPClient!

    override func setUp() {
        super.setUp()
        client = HTTPClient(session: MockURLProtocol.makeSession())
    }

    override func tearDown() {
        MockURLProtocol.reset()
        client = nil
        super.tearDown()
    }

    private struct Payload: Decodable, Equatable {
        let name: String
        let count: Int
    }

    private func url() -> URL {
        URL(string: "https://example.invalid/resource")!
    }

    // MARK: - GET

    func testGetDecodesJSONOnSuccess() async throws {
        MockURLProtocol.requestHandler = { request in
            (MockURLProtocol.httpResponse(for: request, status: 200),
             Data(#"{"name":"wolf","count":3}"#.utf8))
        }

        let result: Payload = try await client.get(url: url())

        XCTAssertEqual(result, Payload(name: "wolf", count: 3))
    }

    func testGetThrowsUnexpectedStatusOnNon2xx() async {
        MockURLProtocol.requestHandler = { request in
            (MockURLProtocol.httpResponse(for: request, status: 404), Data("missing".utf8))
        }

        do {
            let _: Payload = try await client.get(url: url())
            XCTFail("Expected HTTPError.unexpectedStatus")
        } catch HTTPClient.HTTPError.unexpectedStatus(let code, _) {
            XCTAssertEqual(code, 404)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testGetThrowsDecodingFailedOnMalformedJSON() async {
        MockURLProtocol.requestHandler = { request in
            (MockURLProtocol.httpResponse(for: request, status: 200), Data("not json".utf8))
        }

        do {
            let _: Payload = try await client.get(url: url())
            XCTFail("Expected HTTPError.decodingFailed")
        } catch HTTPClient.HTTPError.decodingFailed {
            // expected
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testGetThrowsTransportOnNetworkFailure() async {
        MockURLProtocol.requestHandler = { _ in throw URLError(.notConnectedToInternet) }

        do {
            let _: Payload = try await client.get(url: url())
            XCTFail("Expected HTTPError.transport")
        } catch HTTPClient.HTTPError.transport {
            // expected
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    // MARK: - Data / POST

    func testDataReturnsRawBytes() async throws {
        let body = Data("raw-bytes".utf8)
        MockURLProtocol.requestHandler = { request in
            (MockURLProtocol.httpResponse(for: request, status: 200), body)
        }

        let result = try await client.data(url: url())

        XCTAssertEqual(result, body)
    }

    func testPostFormSetsURLEncodedContentTypeAndDecodes() async throws {
        MockURLProtocol.requestHandler = { request in
            XCTAssertEqual(
                request.value(forHTTPHeaderField: "Content-Type"),
                "application/x-www-form-urlencoded"
            )
            return (MockURLProtocol.httpResponse(for: request, status: 200),
                    Data(#"{"name":"ok","count":1}"#.utf8))
        }

        let result: Payload = try await client.postForm(url: url(), form: ["grant": "x"])

        XCTAssertEqual(result, Payload(name: "ok", count: 1))
    }
}
