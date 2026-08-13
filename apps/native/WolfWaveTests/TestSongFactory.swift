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
/// Decoding lives in `Song.debugPlaceholder` in the app target, shared with the
/// Debug tab's fake-request injector, so the Apple Music resource shape has one
/// copy rather than one per target.
func makeTestSong(
    id: String = defaultTestSongID,
    title: String = "Test Song",
    artist: String = "Test Artist",
    album: String = "Test Album",
    durationInMillis: Int = 180_000
) -> Song {
    .debugPlaceholder(
        id: id,
        title: title,
        artist: artist,
        album: album,
        durationInMillis: durationInMillis
    )
}

/// Builds a queue item for tests.
///
/// The only way to make a `SongRequestItem` in a test, since `song` is
/// non-optional. There used to be a song-less test initializer, which made "a
/// queue item that cannot be played" representable and forced a nil branch into
/// playback; a `#if DEBUG` hatch in that branch then let song-less fixtures fake
/// a successful start, so a test could assert `playNowCalled == false` about a
/// request that could never have called it. Both are gone.
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
