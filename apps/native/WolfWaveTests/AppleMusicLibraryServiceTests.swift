//
//  AppleMusicLibraryServiceTests.swift
//  WolfWave
//
//  Created by Nathanial Henniges on 2026-06-08.
//  Copyright © 2026 MrDemonWolf, Inc. All rights reserved.
//

import Foundation
import Testing

@testable import WolfWave

/// Covers the pure request-building seams of `AppleMusicLibraryService`: the
/// Apple Music API URL construction and the JSON bodies sent to add a song and
/// to create the requests playlist. The networked calls themselves need a live
/// MusicKit user token, so they are exercised manually, not in unit tests.
@MainActor
@Suite("Apple Music Library Service")
struct AppleMusicLibraryServiceTests {

    @Test("endpoint builds a versioned Apple Music API URL")
    func endpointBuildsVersionedURL() throws {
        let url = try AppleMusicLibraryService.endpoint("/me/library/playlists")
        #expect(url.absoluteString == "https://api.music.apple.com/v1/me/library/playlists")
    }

    @Test("endpoint embeds a playlist id in the tracks path")
    func endpointEmbedsPlaylistID() throws {
        let url = try AppleMusicLibraryService.endpoint("/me/library/playlists/p.ABC123/tracks")
        #expect(url.absoluteString == "https://api.music.apple.com/v1/me/library/playlists/p.ABC123/tracks")
    }

    @Test("add-tracks body carries the catalog song id with type songs")
    func addTracksBodyShape() throws {
        let data = try AppleMusicLibraryService.addTracksBody(forCatalogSongID: "1440889742")
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let array = json?["data"] as? [[String: Any]]
        #expect(array?.count == 1)
        #expect(array?.first?["id"] as? String == "1440889742")
        // Catalog songs are added with the catalog resource type "songs".
        #expect(array?.first?["type"] as? String == "songs")
    }

    @Test("create-playlist body names and describes the WolfWave Requests playlist")
    func createPlaylistBodyShape() throws {
        let data = try AppleMusicLibraryService.createPlaylistBody()
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let attributes = json?["attributes"] as? [String: Any]
        #expect(attributes?["name"] as? String == AppConstants.Music.requestsPlaylistName)
        #expect((attributes?["description"] as? String)?.isEmpty == false)
    }

    @Test("API base and playlist name constants are stable")
    func constantsAreStable() {
        #expect(AppConstants.Music.requestsPlaylistName == "WolfWave Requests")
        #expect(AppConstants.Music.apiBaseURL == "https://api.music.apple.com/v1")
    }

    // MARK: - Share URL resolution parsing

    @Test("share URL is extracted from a catalog playlist response")
    func parseShareURLFromCatalog() {
        let json = """
        {"data":[{"id":"pl.u-abc","type":"playlists","attributes":{"name":"WolfWave Requests","url":"https://music.apple.com/us/playlist/wolfwave-requests/pl.u-abc"}}]}
        """
        let url = AppleMusicLibraryService.parseShareURL(fromCatalogData: Data(json.utf8))
        #expect(url == "https://music.apple.com/us/playlist/wolfwave-requests/pl.u-abc")
    }

    @Test("an empty catalog response yields no share URL")
    func parseShareURLEmpty() {
        #expect(AppleMusicLibraryService.parseShareURL(fromCatalogData: Data("{\"data\":[]}".utf8)) == nil)
    }

    @Test("globalId is read from a published library playlist")
    func parseGlobalIDPublished() {
        let json = """
        {"data":[{"id":"p.xyz","type":"library-playlists","attributes":{"name":"WolfWave Requests","playParams":{"id":"p.xyz","isLibrary":true,"globalId":"pl.u-abc"}}}]}
        """
        #expect(AppleMusicLibraryService.parseGlobalID(fromLibraryData: Data(json.utf8)) == "pl.u-abc")
    }

    @Test("a private library playlist has no globalId")
    func parseGlobalIDPrivate() {
        let json = """
        {"data":[{"id":"p.xyz","type":"library-playlists","attributes":{"name":"WolfWave Requests","playParams":{"id":"p.xyz","isLibrary":true}}}]}
        """
        #expect(AppleMusicLibraryService.parseGlobalID(fromLibraryData: Data(json.utf8)) == nil)
    }

    @Test("storefront id is read from the storefront response")
    func parseStorefrontID() {
        let json = """
        {"data":[{"id":"us","type":"storefronts","attributes":{"name":"United States"}}]}
        """
        #expect(AppleMusicLibraryService.parseStorefront(fromData: Data(json.utf8)) == "us")
    }
}
