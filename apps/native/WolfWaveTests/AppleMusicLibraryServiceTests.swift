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

/// Covers request building, playlist ownership matching, persisted-id recovery,
/// and the concurrency around first-use playlist creation. Transport seams keep
/// these tests deterministic without a live MusicKit user token.
@MainActor
@Suite("Apple Music Library Service", .serialized)
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
        #expect(attributes?["authorDisplayName"] == nil)
    }

    @Test("API base and playlist name constants are stable")
    func constantsAreStable() {
        #expect(AppConstants.Music.requestsPlaylistName == "WolfWave Requests")
        #expect(AppConstants.Music.apiBaseURL == "https://api.music.apple.com/v1")
    }

    // MARK: - Playlist identity and ensure lifecycle

    @Test("ownership matching requires the exact WolfWave description marker")
    func ownershipMatchingRequiresMarker() throws {
        let data = try libraryData([
            (
                id: "p.user",
                name: AppConstants.Music.requestsPlaylistName,
                description: "My personal playlist"
            ),
            (
                id: "p.owned",
                name: AppConstants.Music.requestsPlaylistName,
                description: AppConstants.Music.requestsPlaylistDescription
            ),
        ])

        #expect(AppleMusicLibraryService.parseOwnedPlaylistID(fromLibraryData: data) == "p.owned")
    }

    @Test("same-name user playlist without marker is ignored")
    func sameNameWithoutMarkerIsIgnored() throws {
        let data = try libraryData([
            (
                id: "p.user",
                name: AppConstants.Music.requestsPlaylistName,
                description: nil
            ),
        ])

        #expect(AppleMusicLibraryService.parseOwnedPlaylistID(fromLibraryData: data) == nil)
    }

    @Test("persisted playlist id survives a user-edited description")
    func persistedPlaylistIDAllowsEditedDescription() async throws {
        let (defaults, suiteName) = try isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let playlistID = "p.persisted"
        defaults.set(playlistID, forKey: AppConstants.UserDefaults.songRequestPlaylistID)
        let ownedData = try libraryData([
            (
                id: playlistID,
                name: AppConstants.Music.requestsPlaylistName,
                description: "Streamer edited this description"
            ),
        ])
        let service = AppleMusicLibraryService(
            defaults: defaults,
            getOverride: { path in
                guard path == "/me/library/playlists/\(playlistID)" else {
                    throw AppleMusicLibraryTestError.unexpectedPath(path)
                }
                return ownedData
            },
            postOverride: { path, _ in
                throw AppleMusicLibraryTestError.unexpectedPath(path)
            })

        #expect(try await service.ensureRequestsPlaylist() == playlistID)
        #expect(defaults.string(forKey: AppConstants.UserDefaults.songRequestPlaylistID) == playlistID)
    }

    @Test("stale persisted id falls back to owned playlist scan")
    func stalePersistedIDRecoversFromScan() async throws {
        let (defaults, suiteName) = try isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set("p.deleted", forKey: AppConstants.UserDefaults.songRequestPlaylistID)
        let recoveredID = "p.recovered"
        let recoveredData = try libraryData([
            (
                id: recoveredID,
                name: AppConstants.Music.requestsPlaylistName,
                description: AppConstants.Music.requestsPlaylistDescription
            ),
        ])
        let service = AppleMusicLibraryService(
            defaults: defaults,
            getOverride: { path in
                switch path {
                case "/me/library/playlists/p.deleted":
                    return nil
                case "/me/library/playlists?limit=100":
                    return recoveredData
                default:
                    throw AppleMusicLibraryTestError.unexpectedPath(path)
                }
            },
            postOverride: { path, _ in
                throw AppleMusicLibraryTestError.unexpectedPath(path)
            })

        #expect(try await service.ensureRequestsPlaylist() == recoveredID)
        #expect(defaults.string(forKey: AppConstants.UserDefaults.songRequestPlaylistID) == recoveredID)
    }

    @Test("a stale cached playlist 404 re-resolves once and persists the new id")
    func staleCachedPlaylistRecoversOnce() async throws {
        let (defaults, suiteName) = try isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let oldID = "p.deleted"
        let newID = "p.recovered"
        defaults.set(oldID, forKey: AppConstants.UserDefaults.songRequestPlaylistID)
        let oldData = try libraryData([
            (
                id: oldID,
                name: AppConstants.Music.requestsPlaylistName,
                description: "An edited description is still the persisted resource"
            ),
        ])
        let newData = try libraryData([
            (
                id: newID,
                name: AppConstants.Music.requestsPlaylistName,
                description: AppConstants.Music.requestsPlaylistDescription
            ),
        ])
        let transport = PlaylistRecoveryTransport(
            oldID: oldID,
            newID: newID,
            oldData: oldData,
            newData: newData,
            outcomes: [.missing, .success])
        let service = AppleMusicLibraryService(
            defaults: defaults,
            getOverride: { path in try await transport.get(path) },
            postOverride: { path, body in try await transport.post(path, body: body) })

        try await service.addCatalogSongIDToRequestsPlaylist("catalog-song")

        let calls = await transport.calls()
        #expect(calls.get == [
            "/me/library/playlists/\(oldID)",
            "/me/library/playlists?limit=100",
        ])
        #expect(calls.post == [
            "/me/library/playlists/\(oldID)/tracks",
            "/me/library/playlists/\(newID)/tracks",
        ])
        #expect(defaults.string(forKey: AppConstants.UserDefaults.songRequestPlaylistID) == newID)
    }

    @Test("concurrent stale 404s share one recovery and both retry the new id")
    func concurrentMissingPlaylistFailuresShareRecovery() async throws {
        let (defaults, suiteName) = try isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let oldID = "p.deleted"
        let newID = "p.recovered"
        defaults.set(oldID, forKey: AppConstants.UserDefaults.songRequestPlaylistID)
        let oldData = try libraryData([
            (
                id: oldID,
                name: AppConstants.Music.requestsPlaylistName,
                description: "Edited after ownership was established"
            ),
        ])
        let newData = try libraryData([
            (
                id: newID,
                name: AppConstants.Music.requestsPlaylistName,
                description: AppConstants.Music.requestsPlaylistDescription
            ),
        ])
        let transport = ConcurrentPlaylistRecoveryTransport(
            oldID: oldID,
            newID: newID,
            oldData: oldData,
            newData: newData)
        let service = AppleMusicLibraryService(
            defaults: defaults,
            getOverride: { path in try await transport.get(path) },
            postOverride: { path, body in try await transport.post(path, body: body) })

        async let first: Void = service.addCatalogSongIDToRequestsPlaylist("song-one")
        async let second: Void = service.addCatalogSongIDToRequestsPlaylist("song-two")
        await transport.waitUntilRecoveryLookupStarted()

        await transport.releaseRecoveryLookup()
        _ = try await first
        _ = try await second

        let counts = await transport.callCounts()
        #expect(counts.oldTrackPosts == 2)
        #expect(counts.recoveryGets == 1)
        #expect(counts.newTrackPosts == 2)
        #expect(defaults.string(forKey: AppConstants.UserDefaults.songRequestPlaylistID) == newID)
    }

    @Test("a non-404 track failure never resets or retries the playlist")
    func nonMissingTrackFailureDoesNotRetry() async throws {
        let (defaults, suiteName) = try isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let playlistID = "p.current"
        defaults.set(playlistID, forKey: AppConstants.UserDefaults.songRequestPlaylistID)
        let data = try libraryData([
            (
                id: playlistID,
                name: AppConstants.Music.requestsPlaylistName,
                description: "User edited"
            ),
        ])
        let transport = PlaylistRecoveryTransport(
            oldID: playlistID,
            newID: "p.unused",
            oldData: data,
            newData: data,
            outcomes: [.transient])
        let service = AppleMusicLibraryService(
            defaults: defaults,
            getOverride: { path in try await transport.get(path) },
            postOverride: { path, body in try await transport.post(path, body: body) })

        var sawTransientFailure = false
        do {
            try await service.addCatalogSongIDToRequestsPlaylist("catalog-song")
        } catch AppleMusicLibraryTestError.transient {
            sawTransientFailure = true
        }

        #expect(sawTransientFailure)
        let calls = await transport.calls()
        #expect(calls.get == ["/me/library/playlists/\(playlistID)"])
        #expect(calls.post == ["/me/library/playlists/\(playlistID)/tracks"])
        #expect(defaults.string(forKey: AppConstants.UserDefaults.songRequestPlaylistID) == playlistID)
    }

    @Test("a second missing-playlist failure propagates without a retry loop")
    func secondMissingPlaylistFailureDoesNotLoop() async throws {
        let (defaults, suiteName) = try isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let oldID = "p.deleted"
        let newID = "p.also-deleted"
        defaults.set(oldID, forKey: AppConstants.UserDefaults.songRequestPlaylistID)
        let oldData = try libraryData([
            (
                id: oldID,
                name: AppConstants.Music.requestsPlaylistName,
                description: nil
            ),
        ])
        let newData = try libraryData([
            (
                id: newID,
                name: AppConstants.Music.requestsPlaylistName,
                description: AppConstants.Music.requestsPlaylistDescription
            ),
        ])
        let transport = PlaylistRecoveryTransport(
            oldID: oldID,
            newID: newID,
            oldData: oldData,
            newData: newData,
            outcomes: [.missing, .missing])
        let service = AppleMusicLibraryService(
            defaults: defaults,
            getOverride: { path in try await transport.get(path) },
            postOverride: { path, body in try await transport.post(path, body: body) })

        var sawMissingFailure = false
        do {
            try await service.addCatalogSongIDToRequestsPlaylist("catalog-song")
        } catch AppleMusicLibraryError.playlistMissing {
            sawMissingFailure = true
        }

        #expect(sawMissingFailure)
        let calls = await transport.calls()
        #expect(calls.post == [
            "/me/library/playlists/\(oldID)/tracks",
            "/me/library/playlists/\(newID)/tracks",
        ])
        #expect(defaults.string(forKey: AppConstants.UserDefaults.songRequestPlaylistID) == newID)
    }

    @Test("playlist discovery follows pagination beyond twenty pages")
    func discoveryHasNoFixedPageCap() async throws {
        let (defaults, suiteName) = try isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let targetPage = 21
        let targetID = "p.page-21"
        var responses: [String: Data] = [:]
        for page in 0...targetPage {
            let path = page == 0
                ? "/me/library/playlists?limit=100"
                : "/me/library/playlists?offset=\(page)"
            let next = page < targetPage
                ? "/v1/me/library/playlists?offset=\(page + 1)"
                : nil
            let resources: [(id: String, name: String, description: String?)] = page == targetPage
                ? [(
                    id: targetID,
                    name: AppConstants.Music.requestsPlaylistName,
                    description: AppConstants.Music.requestsPlaylistDescription
                )]
                : []
            responses[path] = try libraryData(resources, next: next)
        }
        let transport = PagingPlaylistTransport(responses: responses)
        let service = AppleMusicLibraryService(
            defaults: defaults,
            getOverride: { path in try await transport.get(path) },
            postOverride: { path, body in try await transport.post(path, body: body) })

        #expect(try await service.ensureRequestsPlaylist() == targetID)
        #expect(await transport.callCounts() == (get: targetPage + 1, post: 0))
    }

    @Test("a repeated pagination next path terminates and creates once")
    func repeatedNextPathCannotLoop() async throws {
        let (defaults, suiteName) = try isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let path = "/me/library/playlists?limit=100"
        let response = try libraryData([], next: "/v1\(path)")
        let transport = PagingPlaylistTransport(responses: [path: response])
        let service = AppleMusicLibraryService(
            defaults: defaults,
            getOverride: { path in try await transport.get(path) },
            postOverride: { path, body in try await transport.post(path, body: body) })

        #expect(try await service.ensureRequestsPlaylist() == "p.created")
        #expect(await transport.callCounts() == (get: 1, post: 1))
    }

    @Test("concurrent first ensures share one lookup and creation")
    func concurrentEnsuresAreCoalesced() async throws {
        let (defaults, suiteName) = try isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let transport = CoalescingPlaylistTransport()
        let service = AppleMusicLibraryService(
            defaults: defaults,
            getOverride: { path in try await transport.get(path) },
            postOverride: { path, body in try await transport.post(path, body: body) })

        async let firstID = service.ensureRequestsPlaylist()
        async let secondID = service.ensureRequestsPlaylist()
        await transport.waitUntilLookupStarted()
        await transport.releaseLookup()

        let ids = try await (firstID, secondID)
        #expect(ids.0 == "p.created")
        #expect(ids.1 == "p.created")
        let counts = await transport.callCounts()
        #expect(counts.get == 1)
        #expect(counts.post == 1)
    }

    @Test("failed ensure clears the shared task so a later call can retry")
    func failedEnsureCanRetry() async throws {
        let (defaults, suiteName) = try isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let recoveredData = try libraryData([
            (
                id: "p.retry",
                name: AppConstants.Music.requestsPlaylistName,
                description: AppConstants.Music.requestsPlaylistDescription
            ),
        ])
        let transport = RetryPlaylistTransport(recoveredData: recoveredData)
        let service = AppleMusicLibraryService(
            defaults: defaults,
            getOverride: { path in try await transport.get(path) },
            postOverride: { path, body in try await transport.post(path, body: body) })

        var firstCallFailed = false
        do {
            _ = try await service.ensureRequestsPlaylist()
        } catch {
            firstCallFailed = true
        }
        #expect(firstCallFailed)
        #expect(try await service.ensureRequestsPlaylist() == "p.retry")
        #expect(await transport.getCallCount() == 2)
    }

    @Test("reset cancels an old ensure without clearing a newer result")
    func resetInvalidatesInFlightEnsure() async throws {
        let (defaults, suiteName) = try isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set("p.old", forKey: AppConstants.UserDefaults.songRequestPlaylistID)
        let newData = try libraryData([
            (
                id: "p.new",
                name: AppConstants.Music.requestsPlaylistName,
                description: AppConstants.Music.requestsPlaylistDescription
            ),
        ])
        let transport = ResetRacePlaylistTransport(newData: newData)
        let service = AppleMusicLibraryService(
            defaults: defaults,
            getOverride: { path in try await transport.get(path) },
            postOverride: { path, body in try await transport.post(path, body: body) })

        let staleEnsure = Task { try await service.ensureRequestsPlaylist() }
        await transport.waitUntilFirstLookupStarted()
        service.resetCachedPlaylistID()
        #expect(defaults.string(forKey: AppConstants.UserDefaults.songRequestPlaylistID) == nil)

        let currentEnsure = Task { try await service.ensureRequestsPlaylist() }
        #expect(try await currentEnsure.value == "p.new")
        await transport.releaseFirstLookup()

        var staleWasCancelled = false
        do {
            _ = try await staleEnsure.value
        } catch is CancellationError {
            staleWasCancelled = true
        } catch {}
        #expect(staleWasCancelled)
        #expect(defaults.string(forKey: AppConstants.UserDefaults.songRequestPlaylistID) == "p.new")
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

    // MARK: - Fixtures

    private func isolatedDefaults() throws -> (UserDefaults, String) {
        let suiteName = "AppleMusicLibraryServiceTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        return (defaults, suiteName)
    }

    private func libraryData(
        _ resources: [(id: String, name: String, description: String?)],
        next: String? = nil
    ) throws -> Data {
        let jsonResources: [[String: Any]] = resources.map { resource in
            var attributes: [String: Any] = ["name": resource.name]
            if let description = resource.description {
                attributes["description"] = ["standard": description]
            }
            return [
                "id": resource.id,
                "type": "library-playlists",
                "attributes": attributes,
            ]
        }
        var page: [String: Any] = ["data": jsonResources]
        if let next {
            page["next"] = next
        }
        return try JSONSerialization.data(withJSONObject: page)
    }
}

private enum AppleMusicLibraryTestError: Error {
    case transient
    case unexpectedPath(String)
}

private actor CoalescingPlaylistTransport {
    private var getCalls = 0
    private var postCalls = 0
    private var lookupStarted = false
    private var lookupReleased = false
    private var startWaiters: [CheckedContinuation<Void, Never>] = []
    private var releaseWaiters: [CheckedContinuation<Void, Never>] = []

    func get(_ path: String) async throws -> Data? {
        guard path == "/me/library/playlists?limit=100" else {
            throw AppleMusicLibraryTestError.unexpectedPath(path)
        }
        getCalls += 1
        lookupStarted = true
        let waiters = startWaiters
        startWaiters.removeAll()
        waiters.forEach { $0.resume() }
        if !lookupReleased {
            await withCheckedContinuation { continuation in
                releaseWaiters.append(continuation)
            }
        }
        return Data("{\"data\":[]}".utf8)
    }

    func post(_ path: String, body _: Data) throws -> Data {
        guard path == "/me/library/playlists" else {
            throw AppleMusicLibraryTestError.unexpectedPath(path)
        }
        postCalls += 1
        return Data("{\"data\":[{\"id\":\"p.created\",\"type\":\"library-playlists\"}]}".utf8)
    }

    func waitUntilLookupStarted() async {
        guard !lookupStarted else { return }
        await withCheckedContinuation { continuation in
            startWaiters.append(continuation)
        }
    }

    func releaseLookup() {
        lookupReleased = true
        let waiters = releaseWaiters
        releaseWaiters.removeAll()
        waiters.forEach { $0.resume() }
    }

    func callCounts() -> (get: Int, post: Int) {
        (getCalls, postCalls)
    }
}

private actor RetryPlaylistTransport {
    private let recoveredData: Data
    private var getCalls = 0

    init(recoveredData: Data) {
        self.recoveredData = recoveredData
    }

    func get(_ path: String) throws -> Data? {
        guard path == "/me/library/playlists?limit=100" else {
            throw AppleMusicLibraryTestError.unexpectedPath(path)
        }
        getCalls += 1
        if getCalls == 1 {
            throw AppleMusicLibraryTestError.transient
        }
        return recoveredData
    }

    func post(_ path: String, body _: Data) throws -> Data {
        throw AppleMusicLibraryTestError.unexpectedPath(path)
    }

    func getCallCount() -> Int {
        getCalls
    }
}

private actor ResetRacePlaylistTransport {
    private let newData: Data
    private var getCalls = 0
    private var firstLookupStarted = false
    private var firstLookupReleased = false
    private var startWaiters: [CheckedContinuation<Void, Never>] = []
    private var releaseWaiters: [CheckedContinuation<Void, Never>] = []

    init(newData: Data) {
        self.newData = newData
    }

    func get(_ path: String) async throws -> Data? {
        getCalls += 1
        if getCalls == 1 {
            guard path == "/me/library/playlists/p.old" else {
                throw AppleMusicLibraryTestError.unexpectedPath(path)
            }
            firstLookupStarted = true
            let waiters = startWaiters
            startWaiters.removeAll()
            waiters.forEach { $0.resume() }
            if !firstLookupReleased {
                await withCheckedContinuation { continuation in
                    releaseWaiters.append(continuation)
                }
            }
            try Task.checkCancellation()
            return nil
        }
        guard path == "/me/library/playlists?limit=100" else {
            throw AppleMusicLibraryTestError.unexpectedPath(path)
        }
        return newData
    }

    func post(_ path: String, body _: Data) throws -> Data {
        throw AppleMusicLibraryTestError.unexpectedPath(path)
    }

    func waitUntilFirstLookupStarted() async {
        guard !firstLookupStarted else { return }
        await withCheckedContinuation { continuation in
            startWaiters.append(continuation)
        }
    }

    func releaseFirstLookup() {
        firstLookupReleased = true
        let waiters = releaseWaiters
        releaseWaiters.removeAll()
        waiters.forEach { $0.resume() }
    }
}

private enum TrackPostOutcome: Sendable {
    case success
    case missing
    case transient
}

private actor PlaylistRecoveryTransport {
    private let oldID: String
    private let newID: String
    private let oldData: Data
    private let newData: Data
    private var outcomes: [TrackPostOutcome]
    private var getPaths: [String] = []
    private var postPaths: [String] = []

    init(
        oldID: String,
        newID: String,
        oldData: Data,
        newData: Data,
        outcomes: [TrackPostOutcome]
    ) {
        self.oldID = oldID
        self.newID = newID
        self.oldData = oldData
        self.newData = newData
        self.outcomes = outcomes
    }

    func get(_ path: String) throws -> Data? {
        getPaths.append(path)
        switch path {
        case "/me/library/playlists/\(oldID)":
            return oldData
        case "/me/library/playlists?limit=100":
            return newData
        default:
            throw AppleMusicLibraryTestError.unexpectedPath(path)
        }
    }

    func post(_ path: String, body _: Data) throws -> Data {
        postPaths.append(path)
        guard path == "/me/library/playlists/\(oldID)/tracks"
            || path == "/me/library/playlists/\(newID)/tracks",
            !outcomes.isEmpty
        else {
            throw AppleMusicLibraryTestError.unexpectedPath(path)
        }
        switch outcomes.removeFirst() {
        case .success:
            return Data()
        case .missing:
            throw AppleMusicLibraryError.playlistMissing
        case .transient:
            throw AppleMusicLibraryTestError.transient
        }
    }

    func calls() -> (get: [String], post: [String]) {
        (getPaths, postPaths)
    }
}

private actor ConcurrentPlaylistRecoveryTransport {
    private let oldID: String
    private let newID: String
    private let oldData: Data
    private let newData: Data
    private var oldTrackPosts = 0
    private var newTrackPosts = 0
    private var recoveryGets = 0
    private var firstOldPostWaiter: CheckedContinuation<Void, Never>?
    private var recoveryStarted = false
    private var recoveryReleased = false
    private var recoveryStartWaiters: [CheckedContinuation<Void, Never>] = []
    private var recoveryReleaseWaiters: [CheckedContinuation<Void, Never>] = []

    init(oldID: String, newID: String, oldData: Data, newData: Data) {
        self.oldID = oldID
        self.newID = newID
        self.oldData = oldData
        self.newData = newData
    }

    func get(_ path: String) async throws -> Data? {
        switch path {
        case "/me/library/playlists/\(oldID)":
            return oldData
        case "/me/library/playlists?limit=100":
            recoveryGets += 1
            recoveryStarted = true
            let waiters = recoveryStartWaiters
            recoveryStartWaiters.removeAll()
            waiters.forEach { $0.resume() }
            if !recoveryReleased {
                await withCheckedContinuation { continuation in
                    recoveryReleaseWaiters.append(continuation)
                }
            }
            return newData
        default:
            throw AppleMusicLibraryTestError.unexpectedPath(path)
        }
    }

    func post(_ path: String, body _: Data) async throws -> Data {
        switch path {
        case "/me/library/playlists/\(oldID)/tracks":
            oldTrackPosts += 1
            if oldTrackPosts == 1 {
                await withCheckedContinuation { continuation in
                    firstOldPostWaiter = continuation
                }
            } else {
                firstOldPostWaiter?.resume()
                firstOldPostWaiter = nil
            }
            throw AppleMusicLibraryError.playlistMissing
        case "/me/library/playlists/\(newID)/tracks":
            newTrackPosts += 1
            return Data()
        default:
            throw AppleMusicLibraryTestError.unexpectedPath(path)
        }
    }

    func waitUntilRecoveryLookupStarted() async {
        guard !recoveryStarted else { return }
        await withCheckedContinuation { continuation in
            recoveryStartWaiters.append(continuation)
        }
    }

    func releaseRecoveryLookup() {
        recoveryReleased = true
        let waiters = recoveryReleaseWaiters
        recoveryReleaseWaiters.removeAll()
        waiters.forEach { $0.resume() }
    }

    func recoveryLookupCount() -> Int {
        recoveryGets
    }

    func callCounts() -> (
        oldTrackPosts: Int,
        recoveryGets: Int,
        newTrackPosts: Int
    ) {
        (oldTrackPosts, recoveryGets, newTrackPosts)
    }
}

private actor PagingPlaylistTransport {
    private let responses: [String: Data]

    private var getCalls = 0
    private var postCalls = 0

    init(responses: [String: Data]) {
        self.responses = responses
    }

    func get(_ path: String) throws -> Data? {
        getCalls += 1
        guard let response = responses[path] else {
            throw AppleMusicLibraryTestError.unexpectedPath(path)
        }
        return response
    }

    func post(_ path: String, body _: Data) throws -> Data {
        guard path == "/me/library/playlists" else {
            throw AppleMusicLibraryTestError.unexpectedPath(path)
        }
        postCalls += 1
        return Data("{\"data\":[{\"id\":\"p.created\",\"type\":\"library-playlists\"}]}".utf8)
    }

    func callCounts() -> (get: Int, post: Int) {
        (getCalls, postCalls)
    }
}
