//
//  SongSearchResolver.swift
//  wolfwave
//
//  Created by MrDemonWolf, Inc. on 4/8/26.
//

import Foundation
import MusicKit

/// Multi-source song search resolver.
///
/// Handles four search paths:
/// 1. **Plain text** → MusicKit catalog search directly
/// 2. **Spotify link** → oEmbed API → extract title/artist → MusicKit search
/// 3. **YouTube link** → oEmbed API → extract title/artist → MusicKit search
/// 4. **Apple Music link** → MusicKit resolve directly
///
/// Always returns a MusicKit `Song` on success for consistent playback.
final class SongSearchResolver {
    // MARK: - Types

    /// Result of a search resolution.
    enum Result {
        case found(Song)
        case notFound(query: String)
        case linkNotFound
        case error(String)
    }

    // MARK: - Properties

    private let linkResolver: LinkResolverService
    private let musicController: any AppleMusicControlling

    // MARK: - Init

    init(linkResolver: LinkResolverService = LinkResolverService(), musicController: any AppleMusicControlling) {
        self.linkResolver = linkResolver
        self.musicController = musicController
    }

    // MARK: - Public API

    /// Resolve a search query to a MusicKit Song.
    func resolve(query: String) async -> Result {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmed.isEmpty else {
            return .error("No search query provided")
        }

        if LinkResolverService.isMusicLink(trimmed) {
            return await resolveLink(trimmed)
        }

        return await resolveText(trimmed)
    }

    // MARK: - Private Helpers

    private func resolveLink(_ text: String) async -> Result {
        guard let urlString = LinkResolverService.extractURL(from: text) else {
            return await resolveText(text)
        }

        Log.debug("SongSearchResolver: Resolving link: \(urlString)", category: "SongRequest")

        let result = await linkResolver.resolve(url: urlString)

        switch result {
        case .appleMusicURL(let url):
            // Resolve Apple Music URL directly via MusicKit
            let musicResult = await musicController.resolve(url: url)
            switch musicResult {
            case .found(let song):
                return .found(song)
            case .notFound:
                return .linkNotFound
            case .error(let message):
                return .error(message)
            }

        case .found(let title, let artist):
            // oEmbed gave us title/artist — search MusicKit
            let searchQuery = artist != nil ? "\(title) \(artist!)" : title
            Log.debug("SongSearchResolver: oEmbed resolved to: \(searchQuery)", category: "SongRequest")
            return await resolveText(searchQuery)

        case .notFound:
            return .linkNotFound

        case .error(let message):
            return .error(message)
        }
    }

    private func resolveText(_ query: String) async -> Result {
        Log.debug("SongSearchResolver: Searching Apple Music for: \(query)", category: "SongRequest")

        let searchResult = await musicController.search(query: query)

        switch searchResult {
        case .found(let song):
            return .found(song)
        case .notFound:
            return .notFound(query: query)
        case .error(let message):
            return .error(message)
        }
    }
}
