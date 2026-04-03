import Foundation

// MARK: - PlaybackSourceMode

/// The user's chosen music source mode.
enum PlaybackSourceMode: String {
    case appleMusic = "appleMusic"
}

// MARK: - PlaybackSourceDelegate

/// Delegate protocol for receiving playback updates from any music source.
protocol PlaybackSourceDelegate: AnyObject {
    func playbackSource(
        _ source: any PlaybackSource,
        didUpdateTrack track: String,
        artist: String,
        album: String,
        duration: TimeInterval,
        elapsed: TimeInterval
    )
    func playbackSource(_ source: any PlaybackSource, didUpdateStatus status: String)
}

// MARK: - PlaybackSource

/// Contract that every music source must satisfy.
protocol PlaybackSource: AnyObject {
    var delegate: PlaybackSourceDelegate? { get set }
    func startTracking()
    func stopTracking()
    func updateCheckInterval(_ interval: TimeInterval)
}
