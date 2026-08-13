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

    /// The MusicKit `Song` used for playback.
    ///
    /// Non-optional on purpose. This was once `Song?` so tests could build an
    /// item without one, which made "a queue item that cannot be played" a
    /// representable state that only test fixtures ever produced. Playback then
    /// needed a nil branch, and a `#if DEBUG` escape hatch in that branch let
    /// song-less fixtures fake a successful start. Tests build items through
    /// `makeTestRequestItem`, so the state is gone rather than guarded.
    let song: Song

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

#if DEBUG
extension Song {
    /// Decodes a placeholder catalog `Song` for developer tooling and tests.
    ///
    /// `Song` has no public initializer, but it is `Decodable` from the Apple
    /// Music API resource shape, which is the supported way to build one without
    /// a network round trip. This lives in the app target so the Debug tab's
    /// fake-request injector and the test fixtures share one copy of that shape;
    /// if MusicKit changes it, both fail together instead of drifting.
    ///
    /// The result is a genuine `Song`, so nothing downstream needs a "no song"
    /// branch. The catalog ID is not a real track, so actually playing one will
    /// fail at Music.app, which is the honest outcome for a fake request.
    static func debugPlaceholder(
        id: String,
        title: String,
        artist: String,
        album: String,
        durationInMillis: Int = 180_000
    ) -> Song {
        let json = """
        {
          "id": "\(id)",
          "type": "songs",
          "href": "/v1/catalog/us/songs/\(id)",
          "attributes": {
            "name": "\(title)",
            "artistName": "\(artist)",
            "albumName": "\(album)",
            "durationInMillis": \(durationInMillis),
            "genreNames": ["Rock"],
            "trackNumber": 1,
            "discNumber": 1,
            "hasLyrics": false,
            "playParams": { "id": "\(id)", "kind": "song" },
            "url": "https:/\("/")music.apple.com/us/album/test/1?i=\(id)"
          }
        }
        """
        do {
            return try JSONDecoder().decode(Song.self, from: Data(json.utf8))
        } catch {
            // A decode failure means MusicKit changed its resource shape. Trap
            // loudly rather than letting callers silently fall back to a state
            // that no longer exists.
            preconditionFailure("Song.debugPlaceholder could not decode a Song: \(error)")
        }
    }
}
#endif
