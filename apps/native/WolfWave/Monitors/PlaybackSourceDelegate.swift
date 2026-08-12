//
//  PlaybackSourceDelegate.swift
//  WolfWave
//
//  Created by Nathanial Henniges on 2026-08-11.
//  Copyright © 2026 MrDemonWolf, Inc. All rights reserved.
//

import Foundation

// MARK: - PlaybackSourceDelegate

/// Receives playback updates from any music source.
///
/// Implementations must be safe to call from the main actor. Concrete sources
/// (e.g. `AppleMusicSource`) marshal delegate callbacks onto the main actor
/// before invocation.
protocol PlaybackSourceDelegate: AnyObject {
    /// Called when the current track changes or progress advances.
    ///
    /// - Parameters:
    ///   - track: Track title.
    ///   - artist: Artist name.
    ///   - album: Album title (may be empty when unavailable).
    ///   - playlist: Current playlist name (may be empty when unavailable).
    ///   - duration: Total track duration in seconds.
    ///   - elapsed: Current playhead position in seconds.
    ///   - isPaused: `true` when the source reports the loaded track as paused
    ///     (Music.app `kPSp`). The track stays "loaded": Discord, the widget,
    ///     and the now-playing UI keep showing it but render a paused affordance.
    func playbackSource(
        didUpdateTrack track: String,
        artist: String,
        album: String,
        playlist: String,
        duration: TimeInterval,
        elapsed: TimeInterval,
        isPaused: Bool
    )

    /// Called when only the playback status changes (paused, stopped, no track).
    ///
    /// - Parameter status: User-facing status string (e.g. `"Paused"`, `"Nothing playing"`).
    func playbackSource(didUpdateStatus status: String)
}
