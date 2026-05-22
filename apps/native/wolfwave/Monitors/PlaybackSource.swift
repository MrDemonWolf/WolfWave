//
//  PlaybackSource.swift
//  wolfwave
//
//  Created by MrDemonWolf, Inc. on 3/28/26.
//

import Foundation

// MARK: - PlaybackSourceMode

/// The user's chosen music source mode.
///
/// Stored verbatim in UserDefaults — the raw value must remain stable across
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
    func playbackSource(
        didUpdateTrack track: String,
        artist: String,
        album: String,
        playlist: String,
        duration: TimeInterval,
        elapsed: TimeInterval
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
    /// Receives track and status updates. Strongly retained by the source —
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
}
