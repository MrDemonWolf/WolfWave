//
//  SongRequestItem.swift
//  WolfWave
//
//  Created by Nathanial Henniges on 2026-04-15.
//  Copyright © 2026 MrDemonWolf, Inc. All rights reserved.
//

import Foundation
import MusicKit

/// A single song request in the queue.
///
/// Contains the resolved track information, the Twitch viewer who requested it,
/// and the MusicKit `Song` reference used for playback.
struct SongRequestItem: Identifiable, Equatable, Sendable {
    /// Unique identifier for this queue entry.
    let id: UUID

    /// Song title.
    let title: String

    /// Artist name.
    let artist: String

    /// Album name.
    let album: String

    /// Twitch username of the viewer who requested this song.
    let requesterUsername: String

    /// When the request was made.
    let requestedAt: Date

    /// The MusicKit `Song` used for playback. Nil only in test contexts.
    let song: Song?

    /// Whether the requester earned queue priority (subscriber/VIP perk). Drives
    /// the fair-share insert so a priority request jumps ahead of non-priority
    /// requests *within the same round*. Default `false`.
    let isPriority: Bool

    // MARK: - Initializers

    init(song: Song, requesterUsername: String, isPriority: Bool = false) {
        self.id = UUID()
        self.title = song.title
        self.artist = song.artistName
        self.album = song.albumTitle ?? "Unknown Album"
        self.requesterUsername = requesterUsername
        self.requestedAt = Date()
        self.song = song
        self.isPriority = isPriority
    }

    #if DEBUG
    /// Test-only initializer that does not require a MusicKit `Song`.
    init(title: String, artist: String, album: String = "Unknown Album", requesterUsername: String, isPriority: Bool = false) {
        self.id = UUID()
        self.title = title
        self.artist = artist
        self.album = album
        self.requesterUsername = requesterUsername
        self.requestedAt = Date()
        self.song = nil
        self.isPriority = isPriority
    }
    #endif

    // MARK: - Duplicate Detection

    /// True when `other` is the same song by the same requester (case-insensitive
    /// title + artist + username).
    ///
    /// Deliberately distinct from `==`, which compares the entry `id`. Used to
    /// de-duplicate a request against the live queue, the pending pen, and the
    /// now-playing slot.
    func isSameRequest(as other: SongRequestItem) -> Bool {
        title.lowercased() == other.title.lowercased()
            && artist.lowercased() == other.artist.lowercased()
            && requesterUsername.lowercased() == other.requesterUsername.lowercased()
    }

    // MARK: - Equatable

    static func == (lhs: SongRequestItem, rhs: SongRequestItem) -> Bool {
        lhs.id == rhs.id
    }
}
