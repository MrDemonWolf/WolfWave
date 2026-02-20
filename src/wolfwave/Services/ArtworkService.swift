//
//  ArtworkService.swift
//  wolfwave
//
//  Created by MrDemonWolf, Inc. on 2/17/26.
//

import Foundation

// MARK: - Artwork Service

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

    /// Serial queue protecting cache mutations.
    private let cacheQueue = DispatchQueue(
        label: "com.mrdemonwolf.wolfwave.artworkCache",
        qos: .utility
    )

    // MARK: - Public API

    /// Fetches album artwork URL from the iTunes Search API.
    ///
    /// Returns a cached result immediately if available. On cache miss, queries the
    /// iTunes Search API and caches the result for future calls.
    ///
    /// - Parameters:
    ///   - track: Song title.
    ///   - artist: Artist name.
    ///   - completion: Called with the artwork URL (512×512), or nil if not found or on error.
    ///     Called on an arbitrary URLSession queue.
    func fetchArtworkURL(track: String, artist: String, completion: @escaping (String?) -> Void) {
        let cacheKey = "\(artist)|\(track)"

        // Check cache first
        let cached: String? = cacheQueue.sync { cache[cacheKey] }
        if let cached {
            completion(cached)
            return
        }

        // Query iTunes Search API
        let query = "\(track) \(artist)"
        guard let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "https://itunes.apple.com/search?media=music&entity=song&limit=1&term=\(encoded)")
        else {
            completion(nil)
            return
        }

        URLSession.shared.dataTask(with: url) { [weak self] data, _, error in
            guard let data, error == nil,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let results = json["results"] as? [[String: Any]],
                  let first = results.first,
                  let artworkUrl = first["artworkUrl100"] as? String
            else {
                Log.debug("Artwork: iTunes lookup failed for \"\(track)\" by \(artist)", category: "Artwork")
                completion(nil)
                return
            }

            // Upscale from 100×100 to 512×512 for better quality
            let highRes = artworkUrl.replacingOccurrences(of: "100x100", with: "512x512")

            self?.cacheQueue.async {
                self?.cache[cacheKey] = highRes
            }

            Log.debug("Artwork: Found artwork for \"\(track)\"", category: "Artwork")
            completion(highRes)
        }.resume()
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
}
