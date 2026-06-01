//
//  RecentTrack.swift
//  WolfWave
//
//  Created by Nathanial Henniges on 2026-05-22.
//  Copyright © 2026 MrDemonWolf, Inc. All rights reserved.
//

import Foundation

/// A single entry in the tray menu's "Recently Played" submenu.
///
/// Captured at the moment a track change is observed by the playback source.
struct RecentTrack: Equatable, Hashable {
    /// Song title.
    let title: String

    /// Primary artist name.
    let artist: String

    /// When the track became the now-playing track.
    let playedAt: Date

    /// Display string used for the menu item title: `"Title · Artist"`.
    var displayLabel: String {
        artist.isEmpty ? title : "\(title) · \(artist)"
    }

    /// Equality and hashing intentionally ignore `playedAt` so two entries for
    /// the same track collapse during de-dup regardless of when they played.
    static func == (lhs: RecentTrack, rhs: RecentTrack) -> Bool {
        lhs.title == rhs.title && lhs.artist == rhs.artist
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(title)
        hasher.combine(artist)
    }
}

/// Fixed-capacity ring buffer of the most recently played tracks.
///
/// Newest entry first. Pushes that match the head are dropped so Apple Music's
/// re-broadcast on resume doesn't poison the list. Pushes that match an older
/// entry move that entry to the front rather than duplicating it.
struct RecentTracksBuffer: Equatable {
    /// Maximum number of entries retained. Older entries fall off the end.
    let maxEntries: Int

    /// Entries in newest-first order.
    private(set) var entries: [RecentTrack] = []

    init(maxEntries: Int = AppConstants.RecentlyPlayed.maxEntries) {
        precondition(maxEntries > 0, "RecentTracksBuffer requires maxEntries > 0")
        self.maxEntries = maxEntries
    }

    /// Pushes a track onto the front.
    ///
    /// - If `track` equals the head, the call is a no-op (de-dups Apple
    ///   Music's resume re-broadcasts).
    /// - If `track` matches a non-head entry, that entry is removed before
    ///   the new one is inserted at the front (recency wins over duplicates).
    /// - Entries past `maxEntries` are trimmed from the tail.
    mutating func push(_ track: RecentTrack) {
        if entries.first == track { return }

        entries.removeAll { $0 == track }
        entries.insert(track, at: 0)

        if entries.count > maxEntries {
            entries.removeLast(entries.count - maxEntries)
        }
    }

    /// Whether the buffer currently has no entries.
    var isEmpty: Bool { entries.isEmpty }

    /// Convenience accessor for the number of stored entries.
    var count: Int { entries.count }
}
