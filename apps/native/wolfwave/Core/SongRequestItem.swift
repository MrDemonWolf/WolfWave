//
//  SongRequestItem.swift
//  wolfwave
//
//  Created by MrDemonWolf, Inc. on 4/8/26.
//

import Foundation
import MusicKit

/// A single song request in the queue.
///
/// Contains the resolved track information, the Twitch viewer who requested it,
/// and the MusicKit `Song` reference used for playback.
struct SongRequestItem: Identifiable, Equatable {
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

    init(song: Song, requesterUsername: String) {
        self.id = UUID()
        self.title = song.title
        self.artist = song.artistName
        self.album = song.albumTitle ?? "Unknown Album"
        self.requesterUsername = requesterUsername
        self.requestedAt = Date()
        self.song = song
    }

    #if DEBUG
    /// Test-only initializer that does not require a MusicKit `Song`.
    init(title: String, artist: String, album: String = "Unknown Album", requesterUsername: String) {
        self.id = UUID()
        self.title = title
        self.artist = artist
        self.album = album
        self.requesterUsername = requesterUsername
        self.requestedAt = Date()
        self.song = nil
    }
    #endif

    static func == (lhs: SongRequestItem, rhs: SongRequestItem) -> Bool {
        lhs.id == rhs.id
    }
}
