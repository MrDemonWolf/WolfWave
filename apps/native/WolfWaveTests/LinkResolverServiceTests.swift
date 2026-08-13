//
//  LinkResolverServiceTests.swift
//  WolfWave
//
//  Created by Nathanial Henniges on 2026-05-22.
//  Copyright © 2026 MrDemonWolf, Inc. All rights reserved.
//

import XCTest

@testable import WolfWave

// MARK: - LinkResolverServiceTests

/// Covers `LinkResolverService` link detection and oEmbed resolution, driving
/// the network layer with `MockURLProtocol`.
@MainActor
final class LinkResolverServiceTests: XCTestCase {

    private var resolver: LinkResolverService!
    private let handlerStore = MockURLProtocol.HandlerStore()

    override func setUp() async throws {
        try await super.setUp()
        handlerStore.handler = nil
        resolver = LinkResolverService(session: MockURLProtocol.makeSession(handlerStore: handlerStore))
    }

    override func tearDown() async throws {
        handlerStore.handler = nil
        resolver = nil
        try await super.tearDown()
    }

    // MARK: - Link Detection

    func testDetectsSpotifyLink() {
        XCTAssertTrue(LinkResolverService.isSpotifyLink("https://open.spotify.com/track/abc"))
        XCTAssertTrue(LinkResolverService.isSpotifyLink("https://open.spotify.com/intl-fr/track/abc"))
        XCTAssertTrue(LinkResolverService.isSpotifyLink("https://spotify.link/abc"))
        XCTAssertFalse(LinkResolverService.isSpotifyLink("https://example.com/track"))
        XCTAssertFalse(LinkResolverService.isSpotifyLink("https://open.spotify.com.evil.test/track/abc"))
    }

    func testDetectsYouTubeLink() {
        XCTAssertTrue(LinkResolverService.isYouTubeLink("https://youtu.be/abc"))
        XCTAssertTrue(LinkResolverService.isYouTubeLink("https://www.youtube.com/watch?v=abc"))
        XCTAssertFalse(LinkResolverService.isYouTubeLink("https://www.youtube.com/watch"))
        XCTAssertFalse(LinkResolverService.isYouTubeLink("https://www.youtube.com/watch?v="))
        XCTAssertFalse(LinkResolverService.isYouTubeLink("https://example.com"))
        XCTAssertFalse(LinkResolverService.isYouTubeLink("https://notyoutube.com/watch?v=abc"))
    }

    func testDetectsAppleMusicLink() {
        XCTAssertTrue(LinkResolverService.isAppleMusicLink("https://music.apple.com/us/album/x/1?i=2"))
        XCTAssertTrue(LinkResolverService.isAppleMusicLink("https://music.apple.com/gb/song/x/2"))
        XCTAssertFalse(LinkResolverService.isAppleMusicLink("https://example.com"))
        XCTAssertFalse(LinkResolverService.isAppleMusicLink("http://music.apple.com/us/album/x/1"))
        XCTAssertFalse(LinkResolverService.isAppleMusicLink("https://music.apple.com.evil.test/us/album/x/1"))
        XCTAssertFalse(LinkResolverService.isAppleMusicLink("https://evil.test/music.apple.com/us/album/x/1"))
        XCTAssertFalse(LinkResolverService.isAppleMusicLink("https://music.apple.com/us/browse"))
        XCTAssertFalse(LinkResolverService.isAppleMusicLink("https://music.apple.com/usa/album/x/1"))
        XCTAssertFalse(LinkResolverService.isAppleMusicLink("https://music.apple.com/us/album/x/not-an-id"))
    }

    func testExtractURLFindsFirstSupportedURLAndTrimsPunctuation() {
        XCTAssertEqual(
            LinkResolverService.extractURL(
                from: "ignore https://example.com/info, play (https://open.spotify.com/track/abc)."
            ),
            "https://open.spotify.com/track/abc"
        )
        XCTAssertNil(LinkResolverService.extractURL(from: "no link here"))
        XCTAssertNil(LinkResolverService.extractURL(from: "https://example.com/not-music"))
    }

    // MARK: - Resolution

    func testResolveAppleMusicReturnsURLWithoutNetwork() async {
        let expected = "https://music.apple.com/us/album/x/123?i=456"
        let result = await resolver.resolve(url: expected)

        guard case .appleMusicURL(let url) = result else {
            XCTFail("Expected .appleMusicURL, got \(result)")
            return
        }
        XCTAssertEqual(url.absoluteString, expected)
    }

    func testResolveRejectsAppleMusicLookalikeHost() async {
        let result = await resolver.resolve(
            url: "https://example.com/music.apple.com/us/album/x/123"
        )

        guard case .notFound = result else {
            XCTFail("Expected .notFound, got \(result)")
            return
        }
    }

    func testResolveRejectsAppleMusicUserInfoAndInsecureTransport() async {
        let rejectedURLs = [
            "https://attacker@music.apple.com/us/album/x/123",
            "http://music.apple.com/us/album/x/123"
        ]

        for url in rejectedURLs {
            let result = await resolver.resolve(url: url)
            guard case .notFound = result else {
                XCTFail("Expected .notFound for \(url), got \(result)")
                continue
            }
        }
    }

    func testResolveSpotifyParsesOEmbedResponse() async {
        handlerStore.handler = { request in
            (MockURLProtocol.httpResponse(for: request, status: 200),
             Data(#"{"title":"Song Name","author_name":"Artist Name"}"#.utf8))
        }

        let result = await resolver.resolve(url: "https://open.spotify.com/track/abc")

        guard case .found(let title, let artist) = result else {
            XCTFail("Expected .found, got \(result)")
            return
        }
        XCTAssertEqual(title, "Song Name")
        XCTAssertEqual(artist, "Artist Name")
    }

    func testResolveOEmbed404IsNotFound() async {
        handlerStore.handler = { request in
            (MockURLProtocol.httpResponse(for: request, status: 404), Data())
        }

        let result = await resolver.resolve(url: "https://open.spotify.com/track/abc")

        guard case .notFound = result else {
            XCTFail("Expected .notFound, got \(result)")
            return
        }
    }

    func testResolveOEmbedServerErrorIsError() async {
        handlerStore.handler = { request in
            (MockURLProtocol.httpResponse(for: request, status: 500), Data())
        }

        let result = await resolver.resolve(url: "https://youtu.be/abc")

        guard case .error = result else {
            XCTFail("Expected .error, got \(result)")
            return
        }
    }

    func testResolveUnknownLinkIsNotFound() async {
        let result = await resolver.resolve(url: "https://example.com/whatever")

        guard case .notFound = result else {
            XCTFail("Expected .notFound, got \(result)")
            return
        }
    }
}
