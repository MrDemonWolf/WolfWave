//
//  ArtworkService.swift
//  wolfwave
//
//  Created by MrDemonWolf, Inc. on 2/17/26.
//

import Foundation

// MARK: - Artwork Service

/// Bundled track metadata returned by a single iTunes Search API lookup.
struct TrackLinks {
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
final class ArtworkService: @unchecked Sendable {

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

    /// Serial queue protecting cache mutations.
    private let cacheQueue = DispatchQueue(
        label: "com.mrdemonwolf.wolfwave.artworkCache",
        qos: .utility
    )

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
    func fetchArtworkURL(track: String, artist: String, completion: @escaping (String?) -> Void) {
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
    func fetchTrackLinks(track: String, artist: String, completion: @escaping (TrackLinks) -> Void) {
        let cacheKey = "\(artist)|\(track)"

        let cached: TrackLinks = cacheQueue.sync {
            TrackLinks(
                artworkURL: cache[cacheKey],
                trackViewURL: trackViewURLCache[cacheKey],
                songLinkURL: songLinkURLCache[cacheKey]
            )
        }

        if cached.artworkURL != nil {
            completion(cached)
            return
        }

        var components = URLComponents(string: "https://itunes.apple.com/search")!
        components.queryItems = [
            URLQueryItem(name: "media", value: "music"),
            URLQueryItem(name: "entity", value: "song"),
            URLQueryItem(name: "limit", value: "1"),
            URLQueryItem(name: "term", value: "\(track) \(artist)"),
        ]
        guard let url = components.url else {
            completion(TrackLinks(artworkURL: nil, trackViewURL: nil, songLinkURL: nil))
            return
        }

        URLSession.shared.dataTask(with: url) { [weak self] data, _, error in
            guard let data, error == nil,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let results = json["results"] as? [[String: Any]],
                  let first = results.first
            else {
                Log.debug("Artwork: iTunes lookup failed for \"\(track)\" by \(artist)", category: "Artwork")
                completion(TrackLinks(artworkURL: nil, trackViewURL: nil, songLinkURL: nil))
                return
            }

            let artworkURL = (first["artworkUrl100"] as? String)
                .map { $0.replacingOccurrences(of: "100x100", with: "512x512") }
            let trackViewURL = first["trackViewUrl"] as? String
            let songLinkURL = (first["trackId"] as? Int).map { "https://song.link/i/\($0)" }

            self?.cacheQueue.sync {
                if let artworkURL { self?.cache[cacheKey] = artworkURL }
                if let trackViewURL { self?.trackViewURLCache[cacheKey] = trackViewURL }
                if let songLinkURL { self?.songLinkURLCache[cacheKey] = songLinkURL }
            }

            Log.debug("Artwork: Found track links for \"\(track)\"", category: "Artwork")
            completion(TrackLinks(artworkURL: artworkURL, trackViewURL: trackViewURL, songLinkURL: songLinkURL))
        }.resume()
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
}
