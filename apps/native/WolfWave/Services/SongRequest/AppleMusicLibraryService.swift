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
nonisolated enum AppleMusicLibraryError: LocalizedError {
    /// MusicKit has not been authorized, so no music-user-token is available.
    case notAuthorized
    /// A constructed Apple Music API URL was malformed.
    case invalidURL(String)
    /// The create-playlist call returned no resource id.
    case playlistCreateFailed
    /// A track add proved that the previously-resolved playlist was deleted.
    case playlistMissing

    var errorDescription: String? {
        switch self {
        case .notAuthorized:
            return "Apple Music access isn't authorized."
        case .invalidURL(let path):
            return "Invalid Apple Music API path: \(path)"
        case .playlistCreateFailed:
            return "Couldn't create the \(AppConstants.Music.requestsPlaylistName) playlist."
        case .playlistMissing:
            return "The \(AppConstants.Music.requestsPlaylistName) playlist no longer exists."
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
    /// the first add and reused for the rest of the session. The same id is also
    /// persisted so launch-time discovery probes one exact resource before
    /// falling back to a paged scan.
    private var cachedPlaylistID: String?
    /// Shared ensure operation so concurrent first adds cannot create duplicates.
    private var ensureTask: (generation: Int, task: Task<String, Error>)?
    private var ensureGeneration = 0

    private let defaults: Foundation.UserDefaults
    private let getOverride: (@Sendable (String) async throws -> Data?)?
    private let postOverride: (@Sendable (String, Data) async throws -> Data)?

    // MARK: - Init

    /// Creates the library service. Network overrides are narrow test seams;
    /// production uses MusicDataRequest for both.
    init(
        defaults: Foundation.UserDefaults = DefaultsStore.store,
        getOverride: (@Sendable (String) async throws -> Data?)? = nil,
        postOverride: (@Sendable (String, Data) async throws -> Data)? = nil
    ) {
        self.defaults = defaults
        self.getOverride = getOverride
        self.postOverride = postOverride
    }

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
        try await addCatalogSongIDToRequestsPlaylist(song.id.rawValue)
        Log.debug(
            "AppleMusicLibraryService: Added \"\(song.title)\" to \(AppConstants.Music.requestsPlaylistName)",
            category: .songRequest
        )
    }

    /// Adds one raw catalog song ID to the resolved requests playlist. Kept
    /// internal as a narrow deterministic test seam; production callers enter
    /// through the MusicKit `Song` API above after authorization.
    ///
    /// A tracks POST 404 is definitive evidence that the cached playlist was
    /// deleted. In that one case, invalidate identity, resolve once, and retry
    /// exactly once. Every other failure propagates without creating duplicates.
    func addCatalogSongIDToRequestsPlaylist(_ catalogSongID: String) async throws {
        let playlistID = try await ensureRequestsPlaylist()
        do {
            try await addCatalogSongID(catalogSongID, toPlaylistID: playlistID)
        } catch AppleMusicLibraryError.playlistMissing {
            resetCachedPlaylistID(ifCurrent: playlistID)
            let recoveredID = try await ensureRequestsPlaylist()
            try await addCatalogSongID(catalogSongID, toPlaylistID: recoveredID)
        }
    }

    /// Returns the `WolfWave Requests` playlist id, finding it in the user's
    /// library or creating it if it does not exist yet. Concurrent callers share
    /// one lookup/create task so first-use song bursts cannot create duplicates.
    func ensureRequestsPlaylist() async throws -> String {
        if let cached = cachedPlaylistID { return cached }
        if let inFlight = ensureTask {
            return try await finishEnsure(
                task: inFlight.task, generation: inFlight.generation)
        }

        ensureGeneration &+= 1
        let generation = ensureGeneration
        let task = Task { try await self.resolveRequestsPlaylist() }
        ensureTask = (generation, task)
        return try await finishEnsure(task: task, generation: generation)
    }

    /// Publishes one shared ensure result and clears only the matching in-flight
    /// slot. The generation guard prevents a late waiter from clearing a newer
    /// retry after the original task failed.
    private func finishEnsure(
        task: Task<String, Error>,
        generation: Int
    ) async throws -> String {
        do {
            let id = try await task.value
            guard generation == ensureGeneration else {
                throw CancellationError()
            }
            cachedPlaylistID = id
            defaults.set(id, forKey: AppConstants.UserDefaults.songRequestPlaylistID)
            ensureTask = nil
            return id
        } catch {
            if generation == ensureGeneration {
                ensureTask = nil
            }
            throw error
        }
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
    /// - Throws: A transport or server error when the Apple Music API could not
    ///   be reached, so the caller never mistakes a network blip for "not public".
    func resolveRequestsPlaylistShareURL() async throws -> String? {
        try ensureAuthorized()
        let playlistID = try await ensureRequestsPlaylist()
        return try await resolveShareURL(forPlaylistID: playlistID)
    }

    // MARK: - Health Probe

    /// The current state of the WolfWave Requests playlist, used by the setup
    /// health check to decide whether the song-request feature is healthy, the
    /// `!playlist` link has gone dead, or the playlist needs rebuilding.
    enum PlaylistProbe: Equatable {
        /// Playlist exists. `shareURL` is non-nil when it is public.
        case ok(shareURL: String?)
        /// Playlist is no longer in the library (deleted by the user).
        case missing
        /// Playlist exists but is not public, so it has no shareable link.
        case notPublic
        /// The Apple Music API could not be reached, so health is unknown. The
        /// caller must treat this as "no change" and never flip a banner on it.
        case unreachable
    }

    /// The outcome of a share-URL resolution attempt, kept separate from the
    /// network calls so `classifyProbe(foundPlaylistID:shareURL:)` stays pure
    /// and unit-testable.
    enum ShareURLOutcome: Equatable {
        /// The API answered definitively. `nil` means the playlist has no
        /// public share link (it has not been shared yet).
        case resolved(String?)
        /// A transport or server error prevented an answer, so the share state
        /// is unknown. Must classify as `.unreachable`, never `.notPublic`.
        case failed
    }

    /// Probes the WolfWave Requests playlist **without creating it**, so the setup
    /// health check can tell a deleted/un-shared playlist apart from a transient
    /// network failure.
    ///
    /// Unlike `resolveRequestsPlaylistShareURL()`, this never calls
    /// `ensureRequestsPlaylist()` (which would silently recreate a deleted
    /// playlist and mask the very state we are trying to detect). A throwing
    /// library read maps to `.unreachable`; a successful read with no match maps
    /// to `.missing`. A share-URL resolution that fails in transit also maps to
    /// `.unreachable` (`.notPublic` requires a definitive "no link" answer), so
    /// a timeout or 5xx never reads as "the streamer un-shared the playlist".
    /// Assumes MusicKit is already authorized (the service checks auth first and
    /// reports `.musicAccessLost` before probing).
    func probeRequestsPlaylist() async -> PlaylistProbe {
        let playlistID: String?
        do {
            playlistID = try await findRequestsPlaylist()
        } catch {
            return .unreachable
        }
        guard let playlistID else { return .missing }
        let shareURL: ShareURLOutcome
        do {
            shareURL = .resolved(try await resolveShareURL(forPlaylistID: playlistID))
        } catch {
            shareURL = .failed
        }
        return Self.classifyProbe(foundPlaylistID: playlistID, shareURL: shareURL)
    }

    /// Resolves the public share URL for an already-known library playlist id.
    /// Returns `nil` only when the API answered and the playlist has no public
    /// catalog equivalent (not shared yet). Shared by
    /// `resolveRequestsPlaylistShareURL()` and the health probe; takes the id
    /// directly so the probe never creates a playlist.
    ///
    /// Tries the library playlist's `catalog` relationship first, then falls
    /// back to the published `globalId` resolved against the user's storefront.
    ///
    /// - Throws: A transport or server error when the Apple Music API could not
    ///   be reached (the share state is unknown, not "no link").
    private func resolveShareURL(forPlaylistID playlistID: String) async throws -> String? {
        if let data = try await get("/me/library/playlists/\(playlistID)/catalog"),
           let url = Self.parseShareURL(fromCatalogData: data) {
            return url
        }
        if let libraryData = try await get("/me/library/playlists/\(playlistID)"),
           let globalID = Self.parseGlobalID(fromLibraryData: libraryData),
           let storefrontData = try await get("/me/storefront"),
           let storefront = Self.parseStorefront(fromData: storefrontData),
           let catalogData = try await get("/catalog/\(storefront)/playlists/\(globalID)"),
           let url = Self.parseShareURL(fromCatalogData: catalogData) {
            return url
        }
        return nil
    }

    /// Pure classification of a probe from the library-list outcome and the
    /// share-URL resolution outcome. Separated from the network calls so the
    /// missing / notPublic / ok / unreachable decision is unit-testable.
    /// (`.unreachable` from a failed library *list* is still the
    /// `probeRequestsPlaylist()` catch path; this covers the share-URL half.)
    static func classifyProbe(foundPlaylistID: String?, shareURL: ShareURLOutcome) -> PlaylistProbe {
        guard foundPlaylistID != nil else { return .missing }
        switch shareURL {
        case .failed:
            return .unreachable
        case .resolved(let url?):
            return .ok(shareURL: url)
        case .resolved(nil):
            return .notPublic
        }
    }

    /// Clears the cached playlist id so the next `ensureRequestsPlaylist()` call
    /// re-finds or recreates it. Used by the health check after it detects the
    /// playlist was deleted.
    func resetCachedPlaylistID() {
        ensureGeneration &+= 1
        ensureTask?.task.cancel()
        ensureTask = nil
        cachedPlaylistID = nil
        defaults.removeObject(forKey: AppConstants.UserDefaults.songRequestPlaylistID)
    }

    /// Invalidates a failed playlist identity only while it is still current.
    /// Two concurrent track adds can both observe the old playlist's 404. The
    /// first starts shared recovery; the second must join that ensure instead of
    /// cancelling it or erasing the replacement the first caller just cached.
    private func resetCachedPlaylistID(ifCurrent failedID: String) {
        let persistedID = defaults.string(
            forKey: AppConstants.UserDefaults.songRequestPlaylistID)
        guard cachedPlaylistID == failedID
            || (cachedPlaylistID == nil && ensureTask == nil && persistedID == failedID)
        else {
            return
        }
        resetCachedPlaylistID()
    }

    /// GETs `path` and returns the raw response body. Returns `nil` only on a
    /// definitive HTTP 404, i.e. the API answered and the resource does not
    /// exist (a library playlist with no public catalog equivalent 404s its
    /// `catalog` relationship), so a not-yet-public playlist reads as "no link".
    ///
    /// Everything else (timeouts, 429, 5xx, transport errors) throws so callers
    /// can classify the failure as `.unreachable` instead of "not public".
    private func get(_ path: String) async throws -> Data? {
        if let getOverride {
            return try await getOverride(path)
        }
        let url = try Self.endpoint(path)
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        do {
            return try await MusicDataRequest(urlRequest: request).response().data
        } catch let error as MusicDataRequest.Error where error.status == 404 {
            return nil
        }
    }

    /// Sends a JSON `POST` to the given library API path and returns the raw
    /// response data. The write-path sibling of ``get(_:)`` (add-track, create-
    /// playlist). Unlike `get(_:)` it does not map 404 to `nil` — a POST caller
    /// treats any non-2xx as a genuine failure.
    private func post(_ path: String, body: Data) async throws -> Data {
        if let postOverride {
            return try await postOverride(path, body)
        }
        let url = try Self.endpoint(path)
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = body
        return try await MusicDataRequest(urlRequest: request).response().data
    }

    // MARK: - Private Helpers

    /// Resolves an existing owned requests playlist. A persisted id is validated
    /// first; if it is gone or renamed, the method falls back to a complete,
    /// loop-guarded paged scan. A same-name user playlist is never adopted by
    /// discovery.
    private func findRequestsPlaylist() async throws -> String? {
        let defaultsKey = AppConstants.UserDefaults.songRequestPlaylistID
        if let persistedID = defaults.string(forKey: defaultsKey),
           !persistedID.isEmpty {
            if let data = try await get("/me/library/playlists/\(persistedID)"),
               Self.parsePersistedPlaylistID(
                   fromLibraryData: data,
                   expectedID: persistedID) == persistedID {
                return persistedID
            }
            defaults.removeObject(forKey: defaultsKey)
        }

        var path = "/me/library/playlists?limit=100"
        var visitedPaths: Set<String> = []
        while visitedPaths.insert(path).inserted {
            guard let data = try await get(path) else { return nil }
            let page = try JSONCoders.default.decode(LibraryPlaylistsPage.self, from: data)
            if let match = page.data.first(where: Self.isOwnedRequestsPlaylist) {
                defaults.set(match.id, forKey: defaultsKey)
                return match.id
            }
            guard let next = page.next, !next.isEmpty else { return nil }
            // `next` is an absolute API path that already carries the `/v1`
            // prefix; strip it because `endpoint(_:)` adds the versioned base.
            path = next.hasPrefix("/v1") ? String(next.dropFirst(3)) : next
        }
        return nil
    }

    /// Posts one catalog track to one concrete library playlist. Only a 404 from
    /// this tracks endpoint becomes `playlistMissing`; create/list/share 404s
    /// retain their existing meanings.
    private func addCatalogSongID(
        _ catalogSongID: String,
        toPlaylistID playlistID: String
    ) async throws {
        do {
            _ = try await post(
                "/me/library/playlists/\(playlistID)/tracks",
                body: Self.addTracksBody(forCatalogSongID: catalogSongID))
        } catch let error as MusicDataRequest.Error where error.status == 404 {
            throw AppleMusicLibraryError.playlistMissing
        }
    }

    /// Finds the owned playlist or creates one when discovery definitively
    /// reports none. Transport and decoding failures propagate, preventing a
    /// transient lookup error from creating a duplicate.
    private func resolveRequestsPlaylist() async throws -> String {
        if let existingID = try await findRequestsPlaylist() {
            return existingID
        }
        return try await createRequestsPlaylist()
    }

    /// Creates the `WolfWave Requests` library playlist and returns its id.
    private func createRequestsPlaylist() async throws -> String {
        let data = try await post("/me/library/playlists", body: Self.createPlaylistBody())
        let page = try JSONCoders.default.decode(LibraryPlaylistsPage.self, from: data)
        guard let id = page.data.first?.id else {
            throw AppleMusicLibraryError.playlistCreateFailed
        }
        Log.debug(
            "AppleMusicLibraryService: Created \(AppConstants.Music.requestsPlaylistName) playlist (\(id))",
            category: .songRequest
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

    /// JSON body for creating the requests playlist. Apple's create-library-
    /// playlist endpoint supports `name` and optional `description`; the exact
    /// description doubles as WolfWave's ownership marker during discovery.
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

    /// Validates a previously-owned resource by exact id and expected name.
    /// Description edits are allowed here because the persisted id was already
    /// verified when discovered or created; scans still require the exact marker.
    static func parsePersistedPlaylistID(
        fromLibraryData data: Data,
        expectedID: String
    ) -> String? {
        let page = try? JSONCoders.default.decode(LibraryPlaylistsPage.self, from: data)
        return page?.data.first {
            $0.id == expectedID
                && $0.attributes?.name == AppConstants.Music.requestsPlaylistName
        }?.id
    }

    /// Extracts the published `globalId` (the `pl.u-...` catalog id) from a
    /// library playlist response, or `nil` when the playlist isn't public.
    static func parseGlobalID(fromLibraryData data: Data) -> String? {
        let page = try? JSONCoders.default.decode(LibraryPlaylistsPage.self, from: data)
        return page?.data.first?.attributes?.playParams?.globalId
    }

    /// Returns the first playlist whose name and description exactly match
    /// WolfWave's ownership marker. Name alone is intentionally insufficient:
    /// users are free to create their own `WolfWave Requests` playlist.
    static func parseOwnedPlaylistID(fromLibraryData data: Data) -> String? {
        let page = try? JSONCoders.default.decode(LibraryPlaylistsPage.self, from: data)
        return page?.data.first(where: Self.isOwnedRequestsPlaylist)?.id
    }

    /// Extracts the user's storefront id (e.g. `us`) from a storefront response.
    static func parseStorefront(fromData data: Data) -> String? {
        let page = try? JSONCoders.default.decode(StorefrontsPage.self, from: data)
        return page?.data.first?.id
    }

    private static func isOwnedRequestsPlaylist(_ resource: LibraryPlaylistResource) -> Bool {
        resource.attributes?.name == AppConstants.Music.requestsPlaylistName
            && resource.attributes?.description?.standard
                == AppConstants.Music.requestsPlaylistDescription
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
        let description: Description?
        let playParams: PlayParams?

        struct Description: Decodable {
            let standard: String?
        }

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
