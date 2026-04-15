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

    // MARK: - Properties

    private let session: URLSession

    // MARK: - Init

    init(session: URLSession = .shared) {
        self.session = session
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
            let encoded = url.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? url
            return await resolveViaOEmbed(
                oEmbedURL: "https://open.spotify.com/oembed?url=\(encoded)"
            )
        }

        // YouTube links — use YouTube oEmbed
        if Self.isYouTubeLink(url) {
            let encoded = url.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? url
            return await resolveViaOEmbed(
                oEmbedURL: "https://www.youtube.com/oembed?url=\(encoded)&format=json"
            )
        }

        return .notFound
    }

    // MARK: - Private Helpers

    /// Resolve a link via an oEmbed endpoint.
    private func resolveViaOEmbed(oEmbedURL: String) async -> ResolveResult {
        guard let requestURL = URL(string: oEmbedURL) else {
            return .error("Invalid oEmbed URL")
        }

        do {
            let (data, response) = try await session.data(from: requestURL)

            guard let httpResponse = response as? HTTPURLResponse else {
                return .error("Invalid response")
            }

            guard httpResponse.statusCode == 200 else {
                if httpResponse.statusCode == 404 {
                    return .notFound
                }
                return .error("oEmbed error (HTTP \(httpResponse.statusCode))")
            }

            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                return .error("Failed to parse oEmbed response")
            }

            // oEmbed returns "title" and "author_name"
            let title = json["title"] as? String
            let author = json["author_name"] as? String

            if let title, !title.isEmpty {
                return .found(title: title, artist: author)
            }

            return .notFound
        } catch {
            return .error("Network error: \(error.localizedDescription)")
        }
    }
}
