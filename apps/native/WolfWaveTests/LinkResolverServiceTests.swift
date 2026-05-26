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

    override func setUp() {
        super.setUp()
        resolver = LinkResolverService(session: MockURLProtocol.makeSession())
    }

    override func tearDown() {
        MockURLProtocol.reset()
        resolver = nil
        super.tearDown()
    }

    // MARK: - Link Detection

    func testDetectsSpotifyLink() {
        XCTAssertTrue(LinkResolverService.isSpotifyLink("https://open.spotify.com/track/abc"))
        XCTAssertTrue(LinkResolverService.isSpotifyLink("https://spotify.link/abc"))
        XCTAssertFalse(LinkResolverService.isSpotifyLink("https://example.com/track"))
    }

    func testDetectsYouTubeLink() {
        XCTAssertTrue(LinkResolverService.isYouTubeLink("https://youtu.be/abc"))
        XCTAssertTrue(LinkResolverService.isYouTubeLink("https://www.youtube.com/watch?v=abc"))
        XCTAssertFalse(LinkResolverService.isYouTubeLink("https://example.com"))
    }

    func testDetectsAppleMusicLink() {
        XCTAssertTrue(LinkResolverService.isAppleMusicLink("https://music.apple.com/us/album/x/1"))
        XCTAssertFalse(LinkResolverService.isAppleMusicLink("https://example.com"))
    }

    func testExtractURLFindsFirstURLInMessage() {
        XCTAssertEqual(
            LinkResolverService.extractURL(from: "play this https://x.com/y now"),
            "https://x.com/y"
        )
        XCTAssertNil(LinkResolverService.extractURL(from: "no link here"))
    }

    // MARK: - Resolution

    func testResolveAppleMusicReturnsURLWithoutNetwork() async {
        let result = await resolver.resolve(url: "https://music.apple.com/us/album/x/123")

        guard case .appleMusicURL = result else {
            XCTFail("Expected .appleMusicURL, got \(result)")
            return
        }
    }

    func testResolveSpotifyParsesOEmbedResponse() async {
        MockURLProtocol.requestHandler = { request in
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
        MockURLProtocol.requestHandler = { request in
            (MockURLProtocol.httpResponse(for: request, status: 404), Data())
        }

        let result = await resolver.resolve(url: "https://open.spotify.com/track/abc")

        guard case .notFound = result else {
            XCTFail("Expected .notFound, got \(result)")
            return
        }
    }

    func testResolveOEmbedServerErrorIsError() async {
        MockURLProtocol.requestHandler = { request in
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
