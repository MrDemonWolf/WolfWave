//
//  PlaybackSource.swift
//  WolfWave
//
//  Created by Nathanial Henniges on 2026-04-02.
//  Copyright © 2026 MrDemonWolf, Inc. All rights reserved.
//

import Foundation

// MARK: - PlaybackSourceMode

/// The user's chosen music source mode.
///
/// Stored verbatim in UserDefaults, so the raw value must remain stable across
/// releases to preserve user settings.
enum PlaybackSourceMode: String {
    /// Apple Music app on macOS, observed via ScriptingBridge + distributed notifications.
    case appleMusic = "appleMusic"
}

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

// MARK: - PlaybackSource

/// Contract that every music source must satisfy.
///
/// Sources push updates through `delegate` rather than exposing pull-based
/// state. This lets the manager subscribe once and remain source-agnostic.
protocol PlaybackSource: AnyObject {
    /// Receives track and status updates. Strongly retained by the source, so
    /// callers must clear the reference (or break the cycle) on teardown.
    var delegate: PlaybackSourceDelegate? { get set }

    /// Begins observing playback. Idempotent; calling twice is a no-op.
    func startTracking()

    /// Stops observing playback. Idempotent; safe to call without a prior
    /// `startTracking()`.
    func stopTracking()

    /// Adjusts the fallback polling interval used when distributed
    /// notifications are unavailable.
    ///
    /// - Parameter interval: New interval in seconds. Sources may clamp to a
    ///   sane range.
    func updateCheckInterval(_ interval: TimeInterval)

    /// Triggers an out-of-band poll of the underlying player, bypassing the
    /// fallback timer and any internal dedup window. No-op when the source
    /// is not currently tracking.
    func forceRefresh()
}
