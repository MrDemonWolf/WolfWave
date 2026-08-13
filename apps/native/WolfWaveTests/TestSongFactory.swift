//
//  TestSongFactory.swift
//  WolfWave
//
//  Created by Nathanial Henniges on 2026-08-13.
//  Copyright © 2026 MrDemonWolf, Inc. All rights reserved.
//

import Foundation
import MusicKit

@testable import WolfWave

/// Catalog ID used when a test does not care which song it gets.
let defaultTestSongID = "1440857781"

/// Derives a stable, distinct catalog ID from arbitrary text.
///
/// Two fixtures built from different titles (or resolved from different search
/// queries) get different song identities, so nothing in a test collides on a
/// shared ID by accident.
func testSongID(for text: String) -> String {
    let slug = text.unicodeScalars
        .filter { CharacterSet.alphanumerics.contains($0) }
        .map(String.init)
        .joined()
    return slug.isEmpty ? defaultTestSongID : slug
}

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
    id: String = defaultTestSongID,
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

/// Builds a queue item backed by a real `Song`, so playback actually reaches
/// `AppleMusicControlling.playNow`.
///
/// Use this for any test whose subject is downstream of playback: takeover at a
/// track boundary, auto-advance, hold release, boost from an idle player. The
/// song-less `SongRequestItem(title:artist:...)` fixture is for pure queue
/// bookkeeping only, where no controller call is expected. `performPlayback`
/// used to return early in DEBUG for song-less items, which let a test assert
/// `playNowCalled == false` about a request that could never have called it.
@MainActor
func makeTestRequestItem(
    title: String,
    artist: String,
    requesterUsername: String,
    isPriority: Bool = false
) -> SongRequestItem {
    SongRequestItem(
        song: makeTestSong(id: testSongID(for: title), title: title, artist: artist),
        requesterUsername: requesterUsername,
        isPriority: isPriority
    )
}
