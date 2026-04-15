//
//  BlocklistItem.swift
//  wolfwave
//
//  Created by MrDemonWolf, Inc. on 4/8/26.
//

import Foundation

/// A blocked song or artist entry.
///
/// Used to prevent specific songs or artists from being requested via chat commands.
struct BlocklistItem: Identifiable, Codable, Equatable, Hashable {
    /// Unique identifier for this blocklist entry.
    let id: UUID

    /// The blocked value — either a song title or artist name.
    let value: String

    /// Whether this entry blocks a specific song title or an entire artist.
    let type: BlockType

    /// When the entry was added.
    let addedAt: Date

    /// The type of blocklist entry.
    enum BlockType: String, Codable {
        /// Blocks a specific song by title (case-insensitive match).
        case song

        /// Blocks all songs by a specific artist (case-insensitive match).
        case artist
    }

    init(value: String, type: BlockType) {
        self.id = UUID()
        self.value = value
        self.type = type
        self.addedAt = Date()
    }
}
