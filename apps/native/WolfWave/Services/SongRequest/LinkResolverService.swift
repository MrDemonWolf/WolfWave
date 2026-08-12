//
//  LinkResolverService.swift
//  WolfWave
//
//  Created by Nathanial Henniges on 2026-04-15.
//  Copyright © 2026 MrDemonWolf, Inc. All rights reserved.
//

import Foundation

/// Resolves Spotify, YouTube, and Apple Music links to song metadata.
///
/// Uses free oEmbed APIs (no auth, no rate limits) for Spotify and YouTube.
/// Apple Music links are returned directly for MusicKit resolution.
nonisolated final class LinkResolverService {
    // MARK: - Types

    /// Supported destination identified from a validated URL.
    private enum MusicService: Equatable, Sendable {
        case spotify
        case youtube
        case appleMusic
    }

    /// Result of resolving a music link.
    enum ResolveResult {
        /// Extracted song title and artist from the link.
        case found(title: String, artist: String?)

        /// The link is an Apple Music URL. Resolve directly via MusicKit.
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
        containsService(.spotify, in: text)
    }

    /// Detect if a string contains a YouTube music URL.
    static func isYouTubeLink(_ text: String) -> Bool {
        containsService(.youtube, in: text)
    }

    /// Detect if a string contains an Apple Music URL.
    static func isAppleMusicLink(_ text: String) -> Bool {
        containsService(.appleMusic, in: text)
    }

    /// Detect if a string is any supported music service link.
    static func isMusicLink(_ text: String) -> Bool {
        detectedURLs(in: text).contains { service(for: $0) != nil }
    }

    /// Extract the first supported music URL from a chat message.
    static func extractURL(from text: String) -> String? {
        detectedURLs(in: text)
            .first { service(for: $0) != nil }?
            .absoluteString
    }

    // MARK: - Resolution

    /// Resolve a music link to song metadata.
    ///
    /// - Parameter url: The music service URL to resolve.
    /// - Returns: The resolution result with title/artist or Apple Music URL.
    func resolve(url: String) async -> ResolveResult {
        guard let sourceURL = URL(string: url),
              let service = Self.service(for: sourceURL)
        else { return .notFound }

        switch service {
        case .appleMusic:
            return .appleMusicURL(sourceURL)
        case .spotify:
            return await resolveViaOEmbed(
                base: AppConstants.API.spotifyOEmbed,
                sourceURL: sourceURL.absoluteString,
                includeFormat: false
            )
        case .youtube:
            return await resolveViaOEmbed(
                base: AppConstants.API.youtubeOEmbed,
                sourceURL: sourceURL.absoluteString,
                includeFormat: true
            )
        }
    }

    // MARK: - Private Helpers

    /// Finds URL-shaped content in natural-language chat text using
    /// Foundation's system data detector. URL parsing below remains the
    /// validation boundary, as recommended by Foundation.
    private static func detectedURLs(in text: String) -> [URL] {
        guard let detector = try? NSDataDetector(
            types: NSTextCheckingResult.CheckingType.link.rawValue
        ) else { return [] }

        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return detector.matches(in: text, options: [], range: range)
            .compactMap { $0.url }
    }

    private static func containsService(_ expected: MusicService, in text: String) -> Bool {
        detectedURLs(in: text).contains { service(for: $0) == expected }
    }

    /// Validates transport, exact host, and service-specific path before a URL
    /// can enter either MusicKit or an oEmbed request.
    private static func service(for url: URL) -> MusicService? {
        guard url.scheme?.lowercased() == "https",
              url.user == nil,
              url.password == nil,
              url.port == nil,
              let host = url.host?.lowercased()
        else { return nil }

        let path = url.path.split(separator: "/", omittingEmptySubsequences: true).map(String.init)

        switch host {
        case "open.spotify.com":
            guard isSpotifyTrackPath(path) else { return nil }
            return .spotify
        case "spotify.link":
            guard path.count == 1 else { return nil }
            return .spotify
        case "youtube.com", "www.youtube.com", "m.youtube.com", "music.youtube.com":
            guard
                path == ["watch"],
                let videoID = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                    .queryItems?
                    .first(where: { $0.name == "v" })?
                    .value,
                !videoID.isEmpty
            else { return nil }
            return .youtube
        case "youtu.be":
            guard path.count == 1 else { return nil }
            return .youtube
        case "music.apple.com":
            guard isAppleMusicTrackPath(path) else { return nil }
            return .appleMusic
        default:
            return nil
        }
    }

    /// Spotify emits both canonical track links and locale-prefixed web links.
    private static func isSpotifyTrackPath(_ path: [String]) -> Bool {
        if path.count == 2 {
            return path[0] == "track"
        }
        guard path.count == 3,
              path[0].hasPrefix("intl-"),
              path[0].count > "intl-".count
        else { return false }
        return path[1] == "track"
    }

    /// Apple Music share links use:
    /// /<storefront>/(album|song)/<slug>/<numeric catalog id>
    private static func isAppleMusicTrackPath(_ path: [String]) -> Bool {
        guard path.count == 4,
              path[0].utf8.count == 2,
              path[0].utf8.allSatisfy({ (97...122).contains(Int($0)) }),
              path[1] == "album" || path[1] == "song",
              !path[2].isEmpty
        else { return false }
        return UInt64(path[3]) != nil
    }

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
