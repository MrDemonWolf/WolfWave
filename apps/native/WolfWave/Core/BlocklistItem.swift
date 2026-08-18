//
//  BlocklistItem.swift
//  WolfWave
//
//  Created by Nathanial Henniges on 2026-04-15.
//  Copyright © 2026 MrDemonWolf, Inc. All rights reserved.
//

import Foundation

/// A blocked song, artist, or requester entry.
///
/// Used to prevent specific songs, artists, or people from being requested via
/// chat commands.
nonisolated struct BlocklistItem: Identifiable, Codable, Equatable, Hashable {
    /// Unique identifier for this blocklist entry.
    let id: UUID

    /// The blocked value: a song title, an artist name, or a Twitch username.
    let value: String

    /// What this entry blocks.
    let type: BlockType

    /// When the entry was added.
    let addedAt: Date

    /// The type of blocklist entry.
    enum BlockType: String, Codable, Hashable {
        /// Blocks a specific song by title (case-insensitive match).
        case song

        /// Blocks all songs by a specific artist (case-insensitive match).
        case artist

        /// Blocks a Twitch username from requesting anything at all
        /// (case-insensitive match). Unlike `song` and `artist`, this is about
        /// the person rather than the music, so it is checked before the
        /// request is even resolved.
        case requester

        /// Label for the picker and the entry list.
        var displayName: String {
            switch self {
            case .song: "Song"
            case .artist: "Artist"
            case .requester: "Requester"
            }
        }
    }

    init(value: String, type: BlockType) {
        self.id = UUID()
        self.value = value
        self.type = type
        self.addedAt = Date()
    }

    /// Full initializer used when retaining persisted identity during import
    /// normalization and by focused model tests.
    init(id identifier: UUID, value: String, type: BlockType, addedAt: Date) {
        self.id = identifier
        self.value = value
        self.type = type
        self.addedAt = addedAt
    }

    /// Validates and trims a decoded blocklist while preserving display case.
    /// Duplicate UUIDs or case-insensitive type/value pairs are ambiguous and
    /// reject the whole collection instead of silently changing user intent.
    static func normalizedForImport(_ items: [BlocklistItem]) -> [BlocklistItem]? {
        struct EntryKey: Hashable {
            let type: BlockType
            let value: String
        }

        var seenIDs: Set<UUID> = []
        var seenEntries: Set<EntryKey> = []
        var normalized: [BlocklistItem] = []
        normalized.reserveCapacity(items.count)

        for item in items {
            let value = item.value.trimmingCharacters(in: .whitespacesAndNewlines)
            let key = EntryKey(type: item.type, value: value.lowercased())
            guard !value.isEmpty,
                  seenIDs.insert(item.id).inserted,
                  seenEntries.insert(key).inserted else {
                return nil
            }
            normalized.append(BlocklistItem(
                id: item.id,
                value: value,
                type: item.type,
                addedAt: item.addedAt
            ))
        }

        return normalized
    }
}
