//
//  ArtworkService.swift
//  WolfWave
//
//  Created by Nathanial Henniges on 2026-02-17.
//  Copyright © 2026 MrDemonWolf, Inc. All rights reserved.
//

import Foundation

// MARK: - Artwork Service

/// Bundled track metadata returned by a single iTunes Search API lookup.
nonisolated struct TrackLinks: Sendable {
    /// Album artwork URL at 512×512 resolution, or nil if not found.
    let artworkURL: String?
    /// Direct Apple Music track URL (e.g. `https://music.apple.com/us/album/…`), or nil.
    let trackViewURL: String?
    /// song.link universal URL for the track (`https://song.link/i/{trackId}`), or nil.
    let songLinkURL: String?
}

/// Shared service for fetching album artwork from the iTunes Search API.
///
/// Provides a single cache and API layer for artwork lookups, replacing
/// duplicate implementations in AppDelegate and DiscordRPCService.
///
/// Thread Safety:
/// - Cache access is serialized on a dedicated queue.
/// - Completion handlers are called on arbitrary URLSession queues.
nonisolated final class ArtworkService: @unchecked Sendable {

    // MARK: - Singleton

    /// Shared instance used across the app.
    static let shared = ArtworkService()

    // MARK: - Properties

    /// In-memory cache of artwork URLs. Key: "artist|track", Value: artwork URL string.
    private var cache: [String: String] = [:]

    /// In-memory cache of Apple Music track view URLs. Key: "artist|track".
    private var trackViewURLCache: [String: String] = [:]

    /// In-memory cache of song.link URLs. Key: "artist|track".
    private var songLinkURLCache: [String: String] = [:]

    /// Timestamp of the last completed lookup per `cacheKey`, success or miss.
    /// A miss caches nothing in the URL maps, so without this a track absent from
    /// iTunes would re-hit the network on every playback tick. An entry here means
    /// "already looked up recently" — callers within `AppConstants.API.artworkLookupTTL`
    /// short-circuit to the (possibly empty) cached value instead of re-querying.
    private var resolvedAt: [String: Date] = [:]

    /// Insertion-ordered keys — used to evict the oldest entry when caches are full.
    private var cacheKeyOrder: [String] = []

    /// Maximum number of entries retained across all three caches.
    private let cacheMaxEntries = 200

    /// Pending completion handlers for in-flight requests, keyed by `cacheKey`.
    /// A non-nil entry means a network request is already running for that key;
    /// additional callers append their completion and wait instead of issuing
    /// a duplicate request. Single-flight dedupes concurrent misses (e.g.
    /// menu bar + Discord both fetching on the same track change).
    private var inFlight: [String: [@Sendable (TrackLinks) -> Void]] = [:]

    /// Serial queue protecting cache mutations.
    private let cacheQueue = DispatchQueue(
        label: "com.mrdemonwolf.wolfwave.artworkCache",
        qos: .utility
    )

    /// Serial queue for disk reads/writes of the persisted cache, kept separate
    /// from `cacheQueue` so file I/O never blocks a lookup decision.
    private let ioQueue = DispatchQueue(
        label: "com.mrdemonwolf.wolfwave.artworkCacheIO",
        qos: .utility
    )

    /// URL session used for iTunes Search API requests. Injectable for testing.
    private let session: URLSession

    /// On-disk location of the persisted links cache, or nil to run memory-only.
    /// nil in tests so they never touch the shared Application Support file.
    private let persistenceURL: URL?

    // MARK: - Init

    /// Creates an artwork service.
    ///
    /// - Parameters:
    ///   - session: URL session for API requests. Defaults to `.shared`.
    ///   - persistenceURL: File backing the links cache. Defaults to the app's
    ///     Application Support directory. Pass nil to disable disk persistence
    ///     (used by tests).
    init(session: URLSession = .shared, persistenceURL: URL? = ArtworkService.defaultPersistenceURL()) {
        self.session = session
        self.persistenceURL = persistenceURL
        loadFromDisk()
    }

    /// Default links-cache file under `Application Support/WolfWave/Cache`.
    /// Returns nil only if the Application Support directory can't be resolved.
    private static func defaultPersistenceURL() -> URL? {
        guard let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask
        ).first else { return nil }
        let cacheDir = appSupport.appending(path: "WolfWave/Cache", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)
        return cacheDir.appending(path: "artwork-links.json")
    }

    // MARK: - Public API

    /// Fetches album artwork URL from the iTunes Search API.
    ///
    /// Delegates to `fetchTrackLinks` so all three fields (artwork, Apple Music URL,
    /// song.link URL) are populated from a single API call and shared cache.
    ///
    /// - Parameters:
    ///   - track: Song title.
    ///   - artist: Artist name.
    ///   - completion: Called with the artwork URL (512×512), or nil if not found or on error.
    ///     Called on an arbitrary URLSession queue.
    func fetchArtworkURL(track: String, artist: String, completion: @escaping @Sendable (String?) -> Void) {
        fetchTrackLinks(track: track, artist: artist) { links in
            completion(links.artworkURL)
        }
    }

    /// Returns the cached artwork URL for a track if available, without making a network request.
    ///
    /// - Parameters:
    ///   - track: Song title.
    ///   - artist: Artist name.
    /// - Returns: The cached artwork URL, or nil if not yet fetched.
    func cachedArtworkURL(track: String, artist: String) -> String? {
        let cacheKey = "\(artist)|\(track)"
        return cacheQueue.sync { cache[cacheKey] }
    }

    // MARK: - Track Links

    /// Fetches artwork URL, Apple Music track URL, and song.link URL in one iTunes API call.
    ///
    /// Returns cached results immediately if available. On cache miss, queries the
    /// iTunes Search API and caches all fields for future calls.
    ///
    /// - Parameters:
    ///   - track: Song title.
    ///   - artist: Artist name.
    ///   - completion: Called with a `TrackLinks` value. Called on an arbitrary URLSession queue.
    func fetchTrackLinks(track: String, artist: String, completion: @escaping @Sendable (TrackLinks) -> Void) {
        let cacheKey = "\(artist)|\(track)"

        // Atomically check cache + register as in-flight waiter under one lock.
        // Returns the cached value if hit, otherwise indicates whether this
        // caller should issue the network request (first miss) or just wait.
        enum Decision { case hit(TrackLinks), leader, waiter }
        let decision: Decision = cacheQueue.sync {
            let cached = TrackLinks(
                artworkURL: cache[cacheKey],
                trackViewURL: trackViewURLCache[cacheKey],
                songLinkURL: songLinkURLCache[cacheKey]
            )
            if cached.artworkURL != nil {
                return .hit(cached)
            }
            // Recently resolved (even to an empty result) — serve the cached value
            // without re-querying. Stops repeat lookups for tracks not on iTunes.
            if let resolved = resolvedAt[cacheKey],
               Date().timeIntervalSince(resolved) < AppConstants.API.artworkLookupTTL {
                return .hit(cached)
            }
            if inFlight[cacheKey] != nil {
                inFlight[cacheKey]?.append(completion)
                return .waiter
            }
            inFlight[cacheKey] = [completion]
            return .leader
        }

        switch decision {
        case .hit(let cached):
            completion(cached)
            return
        case .waiter:
            return
        case .leader:
            break
        }

        // Leader path: issue one network request and fan out the result to all waiters.
        guard var components = URLComponents(string: AppConstants.API.itunesSearch) else {
            finishInFlight(cacheKey: cacheKey, with: TrackLinks(artworkURL: nil, trackViewURL: nil, songLinkURL: nil))
            return
        }
        components.queryItems = [
            URLQueryItem(name: "media", value: "music"),
            URLQueryItem(name: "entity", value: "song"),
            URLQueryItem(name: "limit", value: "1"),
            URLQueryItem(name: "term", value: "\(track) \(artist)"),
        ]
        guard let url = components.url else {
            finishInFlight(cacheKey: cacheKey, with: TrackLinks(artworkURL: nil, trackViewURL: nil, songLinkURL: nil))
            return
        }

        session.dataTask(with: url) { [weak self] data, _, error in
            guard let self else { return }
            guard let data, error == nil,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let results = json["results"] as? [[String: Any]],
                  let first = results.first
            else {
                Log.debug("Artwork: iTunes lookup failed for \"\(track)\" by \(artist)", category: "Artwork")
                self.cacheQueue.sync { self.recordResolution(cacheKey) }
                self.finishInFlight(cacheKey: cacheKey, with: TrackLinks(artworkURL: nil, trackViewURL: nil, songLinkURL: nil))
                return
            }

            let artworkURL = (first["artworkUrl100"] as? String)
                .map { $0.replacingOccurrences(of: "100x100", with: "512x512") }
            let trackViewURL = first["trackViewUrl"] as? String
            let songLinkURL = (first["trackId"] as? Int).map { "\(AppConstants.API.songLinkTrackPrefix)\($0)" }

            let links = TrackLinks(artworkURL: artworkURL, trackViewURL: trackViewURL, songLinkURL: songLinkURL)

            self.cacheQueue.sync {
                if let artworkURL { self.cache[cacheKey] = artworkURL }
                if let trackViewURL { self.trackViewURLCache[cacheKey] = trackViewURL }
                if let songLinkURL { self.songLinkURLCache[cacheKey] = songLinkURL }
                self.recordResolution(cacheKey)
            }

            Log.debug("Artwork: Found track links for \"\(track)\"", category: "Artwork")
            self.finishInFlight(cacheKey: cacheKey, with: links)
        }.resume()
    }

    /// Records that a lookup completed for `cacheKey` (success or miss) and bounds
    /// the caches by evicting the oldest entry once `cacheMaxEntries` is exceeded.
    ///
    /// Must be called while holding `cacheQueue`. Tracking misses here is what stops
    /// not-found tracks from re-querying the network on every playback tick.
    private func recordResolution(_ cacheKey: String) {
        if resolvedAt[cacheKey] == nil {
            cacheKeyOrder.append(cacheKey)
        }
        resolvedAt[cacheKey] = Date()
        while cacheKeyOrder.count > cacheMaxEntries {
            let evicted = cacheKeyOrder.removeFirst()
            cache.removeValue(forKey: evicted)
            trackViewURLCache.removeValue(forKey: evicted)
            songLinkURLCache.removeValue(forKey: evicted)
            resolvedAt.removeValue(forKey: evicted)
        }
        scheduleSave()
    }

    /// Pops all pending waiters for `cacheKey` and invokes them with `links`.
    /// Called outside the cache lock to avoid holding it while running arbitrary
    /// caller code.
    private func finishInFlight(cacheKey: String, with links: TrackLinks) {
        let waiters: [@Sendable (TrackLinks) -> Void] = cacheQueue.sync {
            let pending = inFlight[cacheKey] ?? []
            inFlight.removeValue(forKey: cacheKey)
            return pending
        }
        for waiter in waiters {
            waiter(links)
        }
    }

    /// Returns cached track links for a track without making a network request.
    ///
    /// - Parameters:
    ///   - track: Song title.
    ///   - artist: Artist name.
    /// - Returns: A `TrackLinks` value; fields are nil if not yet fetched.
    func cachedTrackLinks(track: String, artist: String) -> TrackLinks {
        let cacheKey = "\(artist)|\(track)"
        return cacheQueue.sync {
            TrackLinks(
                artworkURL: cache[cacheKey],
                trackViewURL: trackViewURLCache[cacheKey],
                songLinkURL: songLinkURLCache[cacheKey]
            )
        }
    }

    // MARK: - Cache Management

    /// Snapshot of cache size for display in settings.
    struct CacheStats: Sendable {
        /// Number of tracks currently cached (resolved within the TTL window).
        let entryCount: Int
        /// Size of the on-disk cache file in bytes, or 0 when memory-only / absent.
        let diskBytes: Int64
    }

    /// Returns the current cache entry count and on-disk size.
    func cacheStats() -> CacheStats {
        let count = cacheQueue.sync { cacheKeyOrder.count }
        var bytes: Int64 = 0
        if let url = persistenceURL,
           let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
           let size = attrs[.size] as? Int64 {
            bytes = size
        }
        return CacheStats(entryCount: count, diskBytes: bytes)
    }

    /// Clears all cached artwork links from memory and deletes the on-disk file.
    func clearCache() {
        cacheQueue.sync {
            cache.removeAll()
            trackViewURLCache.removeAll()
            songLinkURLCache.removeAll()
            resolvedAt.removeAll()
            cacheKeyOrder.removeAll()
        }
        if let url = persistenceURL {
            ioQueue.async { try? FileManager.default.removeItem(at: url) }
        }
        Log.info("Artwork: cache cleared", category: "Artwork")
    }

    // MARK: - Persistence

    /// One persisted track's links plus its resolution timestamp.
    private struct PersistedEntry: Codable {
        let artworkURL: String?
        let trackViewURL: String?
        let songLinkURL: String?
        let resolvedAt: Date
    }

    /// On-disk shape of the links cache: entries keyed by `cacheKey` plus the
    /// insertion order used for eviction.
    private struct PersistedCache: Codable {
        let entries: [String: PersistedEntry]
        let order: [String]
    }

    /// Loads the persisted cache into memory at init, dropping entries already
    /// past the TTL so the file self-prunes over time. Single-threaded — runs
    /// before the service is shared across queues.
    private func loadFromDisk() {
        guard let url = persistenceURL,
              let data = try? Data(contentsOf: url),
              let snapshot = try? JSONDecoder().decode(PersistedCache.self, from: data)
        else { return }

        let now = Date()
        for key in snapshot.order {
            guard let entry = snapshot.entries[key] else { continue }
            if now.timeIntervalSince(entry.resolvedAt) >= AppConstants.API.artworkLookupTTL { continue }
            if let artworkURL = entry.artworkURL { cache[key] = artworkURL }
            if let trackViewURL = entry.trackViewURL { trackViewURLCache[key] = trackViewURL }
            if let songLinkURL = entry.songLinkURL { songLinkURLCache[key] = songLinkURL }
            resolvedAt[key] = entry.resolvedAt
            cacheKeyOrder.append(key)
        }
        Log.debug("Artwork: loaded \(cacheKeyOrder.count) cached entries from disk", category: "Artwork")
    }

    /// Snapshots the current cache and writes it to disk asynchronously.
    /// Must be called while holding `cacheQueue` (snapshot read is unsynchronized).
    private func scheduleSave() {
        guard let url = persistenceURL else { return }
        var entries: [String: PersistedEntry] = [:]
        for key in cacheKeyOrder {
            guard let timestamp = resolvedAt[key] else { continue }
            entries[key] = PersistedEntry(
                artworkURL: cache[key],
                trackViewURL: trackViewURLCache[key],
                songLinkURL: songLinkURLCache[key],
                resolvedAt: timestamp
            )
        }
        let snapshot = PersistedCache(entries: entries, order: cacheKeyOrder)
        ioQueue.async {
            guard let data = try? JSONEncoder().encode(snapshot) else { return }
            try? data.write(to: url, options: .atomic)
        }
    }
}
