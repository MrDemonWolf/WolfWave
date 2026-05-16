//
//  LinkResolverService.swift
//  wolfwave
//
//  Created by MrDemonWolf, Inc. on 4/8/26.
//

import Foundation

/// Resolves Spotify, YouTube, and Apple Music links to song metadata.
///
/// Uses free oEmbed APIs (no auth, no rate limits) for Spotify and YouTube.
/// Apple Music links are returned directly for MusicKit resolution.
final class LinkResolverService {
    // MARK: - Types

    /// Result of resolving a music link.
    enum ResolveResult {
        /// Extracted song title and artist from the link.
        case found(title: String, artist: String?)

        /// The link is an Apple Music URL — resolve directly via MusicKit.
        case appleMusicURL(URL)

        /// Could not extract metadata from the link.
        case notFound

        /// An error occurred.
        case error(String)
    }

    /// Minimal oEmbed response shape (`title` + optional `author_name`).
    private struct OEmbedResponse: Decodable {
        let title: String?
        let authorName: String?
    }

    // MARK: - Properties

    private let http: HTTPClient

    // MARK: - Init

    init(session: URLSession = .shared) {
        // Use a dedicated HTTPClient configured to decode `author_name` → `authorName`.
        self.http = HTTPClient(session: session, decoder: JSONCoders.snakeCase)
    }

    // MARK: - Link Detection

    /// Detect if a string contains a Spotify track URL.
    static func isSpotifyLink(_ text: String) -> Bool {
        text.contains("open.spotify.com/track/") || text.contains("spotify.link/")
    }

    /// Detect if a string contains a YouTube music URL.
    static func isYouTubeLink(_ text: String) -> Bool {
        text.contains("youtube.com/watch") || text.contains("youtu.be/")
            || text.contains("music.youtube.com/watch")
    }

    /// Detect if a string contains an Apple Music URL.
    static func isAppleMusicLink(_ text: String) -> Bool {
        text.contains("music.apple.com/")
    }

    /// Detect if a string is any supported music service link.
    static func isMusicLink(_ text: String) -> Bool {
        isSpotifyLink(text) || isYouTubeLink(text) || isAppleMusicLink(text)
    }

    /// Extract the URL from a chat message that may contain other text.
    static func extractURL(from text: String) -> String? {
        let words = text.split(separator: " ")
        for word in words {
            let str = String(word)
            if str.hasPrefix("http://") || str.hasPrefix("https://") {
                return str
            }
        }
        return nil
    }

    // MARK: - Resolution

    /// Resolve a music link to song metadata.
    ///
    /// - Parameter url: The music service URL to resolve.
    /// - Returns: The resolution result with title/artist or Apple Music URL.
    func resolve(url: String) async -> ResolveResult {
        // Apple Music links — return directly for MusicKit resolution
        if Self.isAppleMusicLink(url), let musicURL = URL(string: url) {
            return .appleMusicURL(musicURL)
        }

        // Spotify links — use Spotify oEmbed
        if Self.isSpotifyLink(url) {
            return await resolveViaOEmbed(base: AppConstants.API.spotifyOEmbed, sourceURL: url, includeFormat: false)
        }

        // YouTube links — use YouTube oEmbed
        if Self.isYouTubeLink(url) {
            return await resolveViaOEmbed(base: AppConstants.API.youtubeOEmbed, sourceURL: url, includeFormat: true)
        }

        return .notFound
    }

    // MARK: - Private Helpers

    /// Resolve a link via an oEmbed endpoint.
    private func resolveViaOEmbed(base: String, sourceURL: String, includeFormat: Bool) async -> ResolveResult {
        guard var components = URLComponents(string: base) else {
            return .error("Invalid oEmbed URL")
        }
        var items = [URLQueryItem(name: "url", value: sourceURL)]
        if includeFormat {
            items.append(URLQueryItem(name: "format", value: "json"))
        }
        components.queryItems = items
        guard let requestURL = components.url else {
            return .error("Invalid oEmbed URL")
        }

        do {
            let response: OEmbedResponse = try await http.get(url: requestURL)
            if let title = response.title, !title.isEmpty {
                return .found(title: title, artist: response.authorName)
            }
            return .notFound
        } catch HTTPClient.HTTPError.unexpectedStatus(let code, _) where code == 404 {
            return .notFound
        } catch HTTPClient.HTTPError.unexpectedStatus(let code, _) {
            return .error("oEmbed error (HTTP \(code))")
        } catch HTTPClient.HTTPError.decodingFailed {
            return .error("Failed to parse oEmbed response")
        } catch {
            return .error("Network error: \(error.localizedDescription)")
        }
    }
}
