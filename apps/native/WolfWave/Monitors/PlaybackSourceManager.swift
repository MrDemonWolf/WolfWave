//
//  PlaybackSourceManager.swift
//  WolfWave
//
//  Created by Nathanial Henniges on 2026-04-02.
//  Copyright © 2026 MrDemonWolf, Inc. All rights reserved.
//

import Foundation

/// Manages the music playback source and forwards its delegate callbacks.
///
/// AppDelegate owns a single PlaybackSourceManager and interacts with it instead of
/// individual sources directly. Apple Music is currently the only source, so the
/// manager wraps the `AppleMusicSource` and relays its `PlaybackSourceDelegate`
/// callbacks up to AppDelegate.
/// Runs MainActor-isolated (the app's default actor isolation). All callers already
/// hop to the main actor before invoking it.
final class PlaybackSourceManager: PlaybackSourceDelegate {

    // MARK: - Properties

    /// The delegate that receives forwarded playback callbacks.
    weak var delegate: PlaybackSourceDelegate?

    /// The currently active playback mode.
    private(set) var currentMode: PlaybackSourceMode

    private let appleMusicSource = AppleMusicSource()
    private var isStarted = false

    // MARK: - Init

    init() {
        currentMode = .appleMusic
    }

    // MARK: - Public Methods

    /// Starts tracking with the current mode's source.
    func startTracking() {
        guard !isStarted else { return }
        isStarted = true
        appleMusicSource.delegate = self
        appleMusicSource.startTracking()
    }

    /// Stops the active source.
    func stopTracking() {
        guard isStarted else { return }
        isStarted = false
        appleMusicSource.stopTracking()
        appleMusicSource.delegate = nil
    }

    /// Updates the fallback polling interval on the active source.
    func updateCheckInterval(_ interval: TimeInterval) {
        guard isStarted else { return }
        appleMusicSource.updateCheckInterval(interval)
    }

    /// Pokes the active source for an immediate now-playing read.
    /// No-op when tracking is not running.
    func forceRefresh() {
        guard isStarted else { return }
        appleMusicSource.forceRefresh()
    }

    // MARK: - PlaybackSourceDelegate (forwarding)

    func playbackSource(didUpdateTrack track: String, artist: String, album: String, playlist: String, duration: TimeInterval, elapsed: TimeInterval, isPaused: Bool) {
        delegate?.playbackSource(didUpdateTrack: track, artist: artist, album: album, playlist: playlist, duration: duration, elapsed: elapsed, isPaused: isPaused)
    }

    func playbackSource(didUpdateStatus status: String) {
        delegate?.playbackSource(didUpdateStatus: status)
    }
}
