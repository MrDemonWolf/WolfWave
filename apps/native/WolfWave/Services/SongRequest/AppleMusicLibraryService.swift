//
//  AppleMusicLibraryService.swift
//  WolfWave
//
//  Created by Nathanial Henniges on 2026-06-08.
//  Copyright © 2026 MrDemonWolf, Inc. All rights reserved.
//

import Foundation
import MusicKit

/// Errors raised while writing to the user's Apple Music library.
enum AppleMusicLibraryError: LocalizedError {
    /// MusicKit has not been authorized, so no music-user-token is available.
    case notAuthorized
    /// A constructed Apple Music API URL was malformed.
    case invalidURL(String)
    /// The create-playlist call returned no resource id.
    case playlistCreateFailed

    var errorDescription: String? {
        switch self {
        case .notAuthorized:
            return "Apple Music access isn't authorized."
        case .invalidURL(let path):
            return "Invalid Apple Music API path: \(path)"
        case .playlistCreateFailed:
            return "Couldn't create the \(AppConstants.Music.requestsPlaylistName) playlist."
        }
    }
}

/// Writes viewer song requests into the user's Apple Music library.
///
/// Why this exists: macOS 26 (Tahoe) broke AppleScript playback of catalog
/// songs that are not in the user's library, and Music.app's AppleScript
/// dictionary has no Up Next / "add to queue" command. The only reliable way to
/// play an arbitrary requested song on Tahoe is to add it to the library first
/// (library tracks still play) and then play it from there. macOS also has no
/// `ApplicationMusicPlayer` / `SystemMusicPlayer`, so this uses the Apple Music
/// API directly via `MusicDataRequest`, which auto-attaches the developer token
/// and the music-user-token that MusicKit manages once the user authorizes.
///
/// All adds are funneled into one dedicated `WolfWave Requests` library playlist
/// (which also adds each song to the library) so the streamer's curated library
/// stays clean and clearable.
final class AppleMusicLibraryService {
    // MARK: - Properties

    /// Cached id of the `WolfWave Requests` library playlist, resolved lazily on
    /// the first add and reused for the rest of the session.
    private var cachedPlaylistID: String?

    // MARK: - Public API

    /// Adds a catalog song to the `WolfWave Requests` library playlist, creating
    /// the playlist on first use. Adding to a library playlist also adds the song
    /// to the user's library, which is what makes it playable via AppleScript on
    /// macOS 26.
    ///
    /// - Parameter song: The resolved catalog song to add.
    /// - Throws: `AppleMusicLibraryError` or a `MusicDataRequest.Error` (e.g. when
    ///   the user has no active Apple Music subscription).
    func addSongToRequestsPlaylist(_ song: Song) async throws {
        try ensureAuthorized()
        let playlistID = try await ensureRequestsPlaylist()
        let url = try Self.endpoint("/me/library/playlists/\(playlistID)/tracks")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try Self.addTracksBody(forCatalogSongID: song.id.rawValue)
        _ = try await MusicDataRequest(urlRequest: request).response()
        Log.debug(
            "AppleMusicLibraryService: Added \"\(song.title)\" to \(AppConstants.Music.requestsPlaylistName)",
            category: "SongRequest"
        )
    }

    /// Returns the `WolfWave Requests` playlist id, finding it in the user's
    /// library or creating it if it does not exist yet.
    func ensureRequestsPlaylist() async throws -> String {
        if let cached = cachedPlaylistID { return cached }
        if let existing = try await findRequestsPlaylist() {
            cachedPlaylistID = existing
            return existing
        }
        let created = try await createRequestsPlaylist()
        cachedPlaylistID = created
        return created
    }

    // MARK: - Share URL Resolution

    /// Resolves the public Apple Music share link for the `WolfWave Requests`
    /// playlist, or `nil` when the playlist has not been made public yet.
    ///
    /// macOS can't publish a library playlist or set `isPublic` via the API, so
    /// the streamer turns sharing on once in Music ("Show on My Profile and in
    /// Search", or Share Playlist). Once public, the playlist gains a catalog
    /// equivalent whose `attributes.url` is the shareable link. This tries the
    /// library playlist's `catalog` relationship first, then falls back to the
    /// published `globalId` resolved against the user's storefront.
    ///
    /// - Returns: The `music.apple.com` share URL, or `nil` if not yet public.
    func resolveRequestsPlaylistShareURL() async throws -> String? {
        try ensureAuthorized()
        let playlistID = try await ensureRequestsPlaylist()

        // Primary: the catalog relationship returns the public catalog playlist
        // (with attributes.url) directly, no storefront needed.
        if let data = await get("/me/library/playlists/\(playlistID)/catalog"),
           let url = Self.parseShareURL(fromCatalogData: data) {
            return url
        }

        // Fallback: read the published global id, then fetch the catalog playlist
        // for the user's storefront.
        if let libraryData = await get("/me/library/playlists/\(playlistID)"),
           let globalID = Self.parseGlobalID(fromLibraryData: libraryData),
           let storefrontData = await get("/me/storefront"),
           let storefront = Self.parseStorefront(fromData: storefrontData),
           let catalogData = await get("/catalog/\(storefront)/playlists/\(globalID)"),
           let url = Self.parseShareURL(fromCatalogData: catalogData) {
            return url
        }

        return nil
    }

    /// GETs `path` and returns the raw response body, or `nil` on any failure
    /// (network error, non-2xx, missing catalog). Resolution degrades to `nil`
    /// rather than throwing so a not-yet-public playlist reads as "no link".
    private func get(_ path: String) async -> Data? {
        guard let url = try? Self.endpoint(path) else { return nil }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        guard let response = try? await MusicDataRequest(urlRequest: request).response() else { return nil }
        return response.data
    }

    // MARK: - Private Helpers

    /// Looks up the `WolfWave Requests` playlist by name across the user's
    /// library playlists, paging until found or exhausted.
    private func findRequestsPlaylist() async throws -> String? {
        var path = "/me/library/playlists?limit=100"
        // Bound the paging so a huge library (or an unexpected `next` loop) can't
        // spin forever; 20 pages × 100 = 2000 playlists is far past any real case.
        for _ in 0..<20 {
            let url = try Self.endpoint(path)
            var request = URLRequest(url: url)
            request.httpMethod = "GET"
            let response = try await MusicDataRequest(urlRequest: request).response()
            let page = try JSONCoders.default.decode(LibraryPlaylistsPage.self, from: response.data)
            if let match = page.data.first(where: {
                $0.attributes?.name == AppConstants.Music.requestsPlaylistName
            }) {
                return match.id
            }
            guard let next = page.next else { return nil }
            // `next` is an absolute API path that already carries the `/v1`
            // prefix; strip it because `endpoint(_:)` adds the versioned base.
            path = next.hasPrefix("/v1") ? String(next.dropFirst(3)) : next
        }
        return nil
    }

    /// Creates the `WolfWave Requests` library playlist and returns its id.
    private func createRequestsPlaylist() async throws -> String {
        let url = try Self.endpoint("/me/library/playlists")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try Self.createPlaylistBody()
        let response = try await MusicDataRequest(urlRequest: request).response()
        let page = try JSONCoders.default.decode(LibraryPlaylistsPage.self, from: response.data)
        guard let id = page.data.first?.id else {
            throw AppleMusicLibraryError.playlistCreateFailed
        }
        Log.debug(
            "AppleMusicLibraryService: Created \(AppConstants.Music.requestsPlaylistName) playlist (\(id))",
            category: "SongRequest"
        )
        return id
    }

    /// Throws unless MusicKit is authorized, since library writes need the
    /// music-user-token that only exists after the user grants access.
    private func ensureAuthorized() throws {
        guard MusicAuthorization.currentStatus == .authorized else {
            throw AppleMusicLibraryError.notAuthorized
        }
    }

    // MARK: - Request Building (pure, testable)

    /// Builds an Apple Music API URL for `path` (relative to the versioned base).
    static func endpoint(_ path: String) throws -> URL {
        guard let url = URL(string: AppConstants.Music.apiBaseURL + path) else {
            throw AppleMusicLibraryError.invalidURL(path)
        }
        return url
    }

    /// JSON body for adding a catalog song to a library playlist.
    static func addTracksBody(forCatalogSongID id: String) throws -> Data {
        try JSONCoders.defaultEncoder.encode(
            AddTracksRequest(data: [AddTracksRequest.ResourceRef(id: id, type: "songs")])
        )
    }

    /// JSON body for creating the requests playlist.
    static func createPlaylistBody() throws -> Data {
        try JSONCoders.defaultEncoder.encode(
            CreatePlaylistRequest(
                attributes: CreatePlaylistRequest.Attributes(
                    name: AppConstants.Music.requestsPlaylistName,
                    description: AppConstants.Music.requestsPlaylistDescription
                )
            )
        )
    }

    // MARK: - Response Parsing (pure, testable)

    /// Extracts the catalog playlist's public share URL from a catalog response
    /// (`/me/library/playlists/{id}/catalog` or `/catalog/{sf}/playlists/{id}`).
    static func parseShareURL(fromCatalogData data: Data) -> String? {
        let page = try? JSONCoders.default.decode(CatalogPlaylistsPage.self, from: data)
        return page?.data.first?.attributes?.url
    }

    /// Extracts the published `globalId` (the `pl.u-...` catalog id) from a
    /// library playlist response, or `nil` when the playlist isn't public.
    static func parseGlobalID(fromLibraryData data: Data) -> String? {
        let page = try? JSONCoders.default.decode(LibraryPlaylistsPage.self, from: data)
        return page?.data.first?.attributes?.playParams?.globalId
    }

    /// Extracts the user's storefront id (e.g. `us`) from a storefront response.
    static func parseStorefront(fromData data: Data) -> String? {
        let page = try? JSONCoders.default.decode(StorefrontsPage.self, from: data)
        return page?.data.first?.id
    }
}

// MARK: - Codable Payloads

/// A page of the user's library playlists from `GET /me/library/playlists`.
private struct LibraryPlaylistsPage: Decodable {
    let data: [LibraryPlaylistResource]
    let next: String?
}

private struct LibraryPlaylistResource: Decodable {
    let id: String
    let attributes: Attributes?

    struct Attributes: Decodable {
        let name: String?
        let playParams: PlayParams?

        struct PlayParams: Decodable {
            /// Catalog id (e.g. `pl.u-...`), present once the playlist is public.
            let globalId: String?
        }
    }
}

/// A page of catalog playlists from `/me/library/playlists/{id}/catalog` or
/// `/catalog/{storefront}/playlists/{id}`.
private struct CatalogPlaylistsPage: Decodable {
    let data: [CatalogPlaylistResource]
}

private struct CatalogPlaylistResource: Decodable {
    let id: String
    let attributes: Attributes?

    struct Attributes: Decodable {
        /// Public `music.apple.com` share link for the playlist.
        let url: String?
    }
}

/// Response from `GET /me/storefront`.
private struct StorefrontsPage: Decodable {
    let data: [StorefrontResource]
}

private struct StorefrontResource: Decodable {
    let id: String
}

/// Body for `POST /me/library/playlists`.
private struct CreatePlaylistRequest: Encodable {
    let attributes: Attributes

    struct Attributes: Encodable {
        let name: String
        let description: String?
    }
}

/// Body for `POST /me/library/playlists/{id}/tracks`.
private struct AddTracksRequest: Encodable {
    let data: [ResourceRef]

    struct ResourceRef: Encodable {
        let id: String
        let type: String
    }
}
