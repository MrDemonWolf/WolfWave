//
//  PlaybackSourceManager.swift
//  wolfwave
//
//  Created by MrDemonWolf, Inc. on 3/28/26.
//

import Foundation

/// Manages the active music playback source and switches between them based on user preference.
///
/// AppDelegate owns a single PlaybackSourceManager and interacts with it instead of
/// individual sources directly. The manager persists the chosen mode to UserDefaults
/// and handles clean start/stop transitions when switching.
class PlaybackSourceManager: PlaybackSourceDelegate {

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

    // MARK: - PlaybackSourceDelegate (forwarding)

    func playbackSource(didUpdateTrack track: String, artist: String, album: String, duration: TimeInterval, elapsed: TimeInterval) {
        delegate?.playbackSource(didUpdateTrack: track, artist: artist, album: album, duration: duration, elapsed: elapsed)
    }

    func playbackSource(didUpdateStatus status: String) {
        delegate?.playbackSource(didUpdateStatus: status)
    }
}
