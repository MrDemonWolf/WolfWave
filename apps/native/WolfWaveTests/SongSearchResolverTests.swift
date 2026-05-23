//
//  SongSearchResolverTests.swift
//  WolfWaveTests
//
//  Created by MrDemonWolf, Inc. on 5/22/26.
//

import XCTest

@testable import WolfWave

// MARK: - SongSearchResolverTests

/// Covers `SongSearchResolver` routing — plain text vs. link queries — using
/// `MockAppleMusicController` (declared in `SongRequestServiceTests`) and a
/// `MockURLProtocol`-backed `LinkResolverService`.
///
/// The `.found` result is not exercised here: it requires a MusicKit `Song`,
/// which cannot be constructed in a unit test. Routing is verified via the
/// distinct non-found results each path produces.
final class SongSearchResolverTests: XCTestCase {

    private var controller: MockAppleMusicController!

    override func setUp() {
        super.setUp()
        controller = MockAppleMusicController()
    }

    override func tearDown() {
        MockURLProtocol.reset()
        controller = nil
        super.tearDown()
    }

    private func makeResolver() -> SongSearchResolver {
        SongSearchResolver(
            linkResolver: LinkResolverService(session: MockURLProtocol.makeSession()),
            musicController: controller
        )
    }

    func testEmptyQueryReturnsError() async {
        let result = await makeResolver().resolve(query: "   ")

        guard case .error = result else {
            XCTFail("Expected .error, got \(result)")
            return
        }
    }

    func testPlainTextQueryRoutesToCatalogSearch() async {
        // MockAppleMusicController.search always reports .notFound.
        let result = await makeResolver().resolve(query: "some song name")

        guard case .notFound(let query) = result else {
            XCTFail("Expected .notFound, got \(result)")
            return
        }
        XCTAssertEqual(query, "some song name")
    }

    func testAppleMusicLinkRoutesToControllerResolve() async {
        // controller.resolve reports .notFound → resolveLink maps to .linkNotFound.
        let result = await makeResolver()
            .resolve(query: "check https://music.apple.com/us/album/x/1")

        guard case .linkNotFound = result else {
            XCTFail("Expected .linkNotFound, got \(result)")
            return
        }
    }

    func testSpotifyLinkResolvesViaOEmbedThenSearchesCatalog() async {
        MockURLProtocol.requestHandler = { request in
            (MockURLProtocol.httpResponse(for: request, status: 200),
             Data(#"{"title":"Tune","author_name":"Band"}"#.utf8))
        }

        let result = await makeResolver()
            .resolve(query: "https://open.spotify.com/track/abc")

        // oEmbed yields "Tune" + "Band" → catalog search for "Tune Band".
        guard case .notFound(let query) = result else {
            XCTFail("Expected .notFound, got \(result)")
            return
        }
        XCTAssertEqual(query, "Tune Band")
    }
}
