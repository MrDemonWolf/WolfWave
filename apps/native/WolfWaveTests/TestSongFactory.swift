//
//  TestSongFactory.swift
//  WolfWave
//
//  Created by Nathanial Henniges on 2026-08-13.
//  Copyright © 2026 MrDemonWolf, Inc. All rights reserved.
//

import Foundation
import MusicKit

/// Builds a real MusicKit `Song` for tests.
///
/// `Song` has no public initializer, so before this existed no test could make
/// one. That is why `MockAppleMusicController.search` returned `.notFound` in
/// every `SongRequestServiceTests` case: `processRequest` then short-circuited
/// at the `.notFound` branch and never reached the gates the tests were named
/// for. Four tests asserted `playNowCalled == false` against a request that
/// could never have called `playNow` under any conditions, so they passed while
/// the hold gate, the Music-closed buffering gate, and the requeue-on-throw path
/// could all be deleted outright.
///
/// `Song` is `Decodable` from the Apple Music API resource shape, which is the
/// supported way to get one without a network round trip.
func makeTestSong(
    id: String = "1440857781",
    title: String = "Test Song",
    artist: String = "Test Artist",
    album: String = "Test Album",
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
        // A decode failure here means MusicKit changed its resource shape. Trap
        // loudly rather than letting every caller silently fall back to
        // `.notFound`, which is the exact vacuity this factory exists to end.
        preconditionFailure("makeTestSong could not decode a MusicKit Song: \(error)")
    }
}
