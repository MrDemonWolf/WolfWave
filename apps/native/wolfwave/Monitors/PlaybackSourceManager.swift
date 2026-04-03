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

    private lazy var appleMusicSource = AppleMusicSource()
    private var activeSource: (any PlaybackSource)?
    private var isTracking = false

    // MARK: - Init

    init() {
        currentMode = .appleMusic
    }

    // MARK: - Public Methods

    /// Starts tracking with the current mode's source.
    func startTracking() {
        stopTracking()
        appleMusicSource.delegate = self
        activeSource = appleMusicSource
        isTracking = true
        appleMusicSource.startTracking()
    }

    /// Stops the active source.
    func stopTracking() {
        activeSource?.stopTracking()
        appleMusicSource.delegate = nil
        activeSource = nil
        isTracking = false
    }

    /// Updates the fallback polling interval on the active source.
    func updateCheckInterval(_ interval: TimeInterval) {
        activeSource?.updateCheckInterval(interval)
    }

    // MARK: - PlaybackSourceDelegate (forwarding)

    func playbackSource(_ source: any PlaybackSource, didUpdateTrack track: String, artist: String, album: String, duration: TimeInterval, elapsed: TimeInterval) {
        delegate?.playbackSource(source, didUpdateTrack: track, artist: artist, album: album, duration: duration, elapsed: elapsed)
    }

    func playbackSource(_ source: any PlaybackSource, didUpdateStatus status: String) {
        delegate?.playbackSource(source, didUpdateStatus: status)
    }
}
