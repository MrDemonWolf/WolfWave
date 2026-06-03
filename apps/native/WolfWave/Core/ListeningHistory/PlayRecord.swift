//
//  PlayRecord.swift
//  WolfWave
//
//  Created by Nathanial Henniges on 2026-05-22.
//  Copyright © 2026 MrDemonWolf, Inc. All rights reserved.
//

import Foundation

/// A single recorded play in the listening history.
///
/// One `PlayRecord` is persisted per *completed* play (a track that crossed the
/// scrobble threshold). It is serialized as one compact JSON object per line in
/// the append-only NDJSON play log. Short keys keep each line near 120 bytes.
nonisolated struct PlayRecord: Codable, Equatable, Hashable, Sendable {

    // MARK: - Properties

    /// When the play was recorded (the moment the track changed away).
    let timestamp: Date

    /// Track title.
    let track: String

    /// Artist name.
    let artist: String

    /// Album title (may be empty when unavailable).
    let album: String

    /// Total track length in seconds (0 when unknown).
    let duration: TimeInterval

    /// How long the track actually played in seconds.
    let playedSeconds: TimeInterval

    // MARK: - Init

    /// Creates a play record.
    ///
    /// - Parameters:
    ///   - timestamp: When the play was recorded. Defaults to now.
    ///   - track: Track title.
    ///   - artist: Artist name.
    ///   - album: Album title.
    ///   - duration: Total track length in seconds.
    ///   - playedSeconds: How long the track actually played in seconds.
    init(
        timestamp: Date = Date(),
        track: String,
        artist: String,
        album: String,
        duration: TimeInterval,
        playedSeconds: TimeInterval
    ) {
        self.timestamp = timestamp
        self.track = track
        self.artist = artist
        self.album = album
        self.duration = duration
        self.playedSeconds = playedSeconds
    }

    // MARK: - Codable

    /// Compact NDJSON keys: `timestamp` and the durations are stored as plain
    /// epoch / second numbers rather than ISO-8601 strings to keep lines small.
    private enum CodingKeys: String, CodingKey {
        case timestamp = "t"
        case track
        case artist
        case album
        case duration = "dur"
        case playedSeconds = "played"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let epoch = try container.decode(Double.self, forKey: .timestamp)
        timestamp = Date(timeIntervalSince1970: epoch)
        track = try container.decode(String.self, forKey: .track)
        artist = try container.decode(String.self, forKey: .artist)
        album = (try? container.decode(String.self, forKey: .album)) ?? ""
        duration = (try? container.decode(Double.self, forKey: .duration)) ?? 0
        playedSeconds = (try? container.decode(Double.self, forKey: .playedSeconds)) ?? 0
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(timestamp.timeIntervalSince1970.rounded(), forKey: .timestamp)
        try container.encode(track, forKey: .track)
        try container.encode(artist, forKey: .artist)
        try container.encode(album, forKey: .album)
        try container.encode(duration.rounded(), forKey: .duration)
        try container.encode(playedSeconds.rounded(), forKey: .playedSeconds)
    }

    // MARK: - Grouping Keys

    /// Case-insensitive key identifying a unique artist.
    var artistKey: String { artist.lowercased() }

    /// Case-insensitive key identifying a unique track (title + artist).
    var trackKey: String { "\(track.lowercased())|\(artist.lowercased())" }

    /// Case-insensitive key identifying a unique album (album + artist).
    var albumKey: String { "\(album.lowercased())|\(artist.lowercased())" }
}
