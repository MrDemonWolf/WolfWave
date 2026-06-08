//
//  AppleMusicSource.swift
//  WolfWave
//
//  Created by Nathanial Henniges on 2026-01-08.
//  Copyright © 2026 MrDemonWolf, Inc. All rights reserved.
//

import Foundation
import AppKit
import ScriptingBridge

final class AppleMusicSource: PlaybackSource, @unchecked Sendable {

    // MARK: - Properties

    private nonisolated enum Constants {
        static let musicBundleIdentifier = "com.apple.Music"
        static let notificationName = "com.apple.Music.playerInfo"
        static let queueLabel = "com.mrdemonwolf.wolfwave.musicplaybackmonitor"
        static let checkInterval: TimeInterval = 5.0
        // ASCII Unit Separator (U+001F). Internal-only field delimiter for the
        // packed track string built and parsed in this file. Must be a byte
        // that can never appear in real track metadata: a printable separator
        // like " | " collides with track/artist/album names that contain it
        // (e.g. "Song | Remix"), shifting every field and corrupting the
        // now-playing data sent to Twitch, Discord, and the overlay.
        static let trackSeparator = "\u{1F}"
        static let notificationDedupWindow: TimeInterval = 0.75
        static let idleGraceWindow: TimeInterval = 2.0
        // Music.app FourCharCode player states ('kPSP', 'kPSp', etc.).
        static let playerStatePlaying:     UInt32 = 1800426320  // 'kPSP'
        static let playerStatePaused:      UInt32 = 1800426352  // 'kPSp'
        static let playerStateFastForward: UInt32 = 1800426310  // 'kPSF'
        static let playerStateRewinding:   UInt32 = 1800426322  // 'kPSR'
        static let playerStateStopped:     UInt32 = 1800426323  // 'kPSS'

        // `com.apple.Music.playerInfo` distributed-notification payload keys.
        // Music posts the player state as a plain string here, so we can read
        // "Stopped" (including the final notification it fires while quitting)
        // without round-tripping an Apple event that would relaunch the app.
        static let playerStateUserInfoKey = "Player State"
        static let playerStateStoppedString = "Stopped"

        enum Status {
            static let notRunning = "NOT_RUNNING"
            static let notPlaying = "NOT_PLAYING"
            static let errorPrefix = "ERROR:"
            /// Internal sentinel: SBApplication created but `playerState` read
            /// returned nil while Music was running. Textbook TCC Automation
            /// denial signature. Mapped to the user-facing
            /// "Music access denied" delegate status downstream.
            static let accessDenied = "ACCESS_DENIED"
            /// Internal sentinel: `SBApplication(bundleIdentifier:)` itself
            /// returned nil. Rare; usually means Music.app is mid-launch or
            /// the bundle isn't registered with LaunchServices yet.
            static let scriptBridgeNil = "SB_NIL_APP"
        }

        enum DelegateStatus {
            static let musicNotRunning = "Music not running"
            static let noTrackInfo = "No track info"
            static let noTrackPlaying = "No track playing"
            static let scriptError = "Script error"
            static let accessDenied = "Music access denied"
        }
    }

    weak var delegate: PlaybackSourceDelegate?

    // All mutable scalar state lives behind `stateLock`. Methods are
    // `nonisolated`, so the lock is the only safety guarantee. Every
    // read and write goes through `stateLock.withLock`.
    private let stateLock = NSLock()
    nonisolated(unsafe) private var currentCheckInterval: TimeInterval = Constants.checkInterval
    nonisolated(unsafe) private var timer: DispatchSourceTimer?
    nonisolated(unsafe) private var lastLoggedTrack: String?
    nonisolated(unsafe) private var lastTrackSeenAt: Date = .distantPast
    nonisolated(unsafe) private var lastNotificationAt: Date = .distantPast
    nonisolated(unsafe) private var isTracking = false
    /// Dedup gate for guard-failure logs. Same key won't log twice in a row.
    /// A successful track read resets this so the next failure logs again.
    nonisolated(unsafe) private var lastGuardLogged: String?
    /// Token for the `NSWorkspace` "Music.app terminated" observer. Lets us
    /// flip to NOT_RUNNING the instant the user quits Music, rather than
    /// waiting for the next fallback poll.
    nonisolated(unsafe) private var musicTerminateObserver: NSObjectProtocol?

    private let backgroundQueue = DispatchQueue(label: Constants.queueLabel, qos: .utility)

    /// Whether Music.app is genuinely running. Filters out instances that have
    /// already terminated, so the quit window (still listed, not yet gone)
    /// reads as not-running. Reading this never launches Music.app.
    nonisolated private var musicIsRunning: Bool {
        NSRunningApplication
            .runningApplications(withBundleIdentifier: Constants.musicBundleIdentifier)
            .contains { !$0.isTerminated }
    }

    // MARK: - Protocol Conformance

    func startTracking() {
        let alreadyTracking = stateLock.withLock { () -> Bool in
            guard !isTracking else { return true }
            isTracking = true
            return false
        }
        guard !alreadyTracking else { return }
        subscribeToMusicNotifications()
        performInitialTrackCheck()
        setupFallbackTimer()
    }

    /// Stops playback tracking and drains any in-flight timer work.
    ///
    /// - Important: Must **not** be called from `backgroundQueue`. The trailing
    ///   `backgroundQueue.sync {}` is a drain barrier that waits for the current
    ///   timer event handler to finish; calling this from within a
    ///   `backgroundQueue` block (e.g. the timer handler itself) would deadlock
    ///   the queue against itself. All current callers run on the main actor.
    nonisolated func stopTracking() {
        let wasTracking = stateLock.withLock { () -> Bool in
            guard isTracking else { return false }
            isTracking = false
            return true
        }
        guard wasTracking else { return }
        DistributedNotificationCenter.default().removeObserver(self)
        let workspaceToken = stateLock.withLock { () -> NSObjectProtocol? in
            let existing = musicTerminateObserver
            musicTerminateObserver = nil
            return existing
        }
        if let workspaceToken {
            NSWorkspace.shared.notificationCenter.removeObserver(workspaceToken)
        }
        let pendingTimer = stateLock.withLock { () -> DispatchSourceTimer? in
            let existing = timer
            timer = nil
            return existing
        }
        pendingTimer?.cancel()
        // Drain barrier (see the threading note above). Safe only off `backgroundQueue`.
        backgroundQueue.sync {}
    }

    func updateCheckInterval(_ interval: TimeInterval) {
        guard stateLock.withLock({ isTracking }) else { return }
        let cancelled = stateLock.withLock { () -> DispatchSourceTimer? in
            currentCheckInterval = max(interval, 1.0)
            let existing = timer
            timer = nil
            return existing
        }
        cancelled?.cancel()
        setupFallbackTimer()
    }

    nonisolated func forceRefresh() {
        guard stateLock.withLock({ isTracking }) else { return }
        // Clear the notification dedup gate so a user-initiated refresh
        // immediately after a system notification is not dropped.
        stateLock.withLock { lastNotificationAt = .distantPast }
        scheduleTrackCheck(reason: "force-refresh")
    }

    // MARK: - Playback Monitoring

    @objc nonisolated private func musicPlayerInfoChanged(_ notification: Notification) {
        let now = Date()
        let shouldSchedule = stateLock.withLock { () -> Bool in
            guard now.timeIntervalSince(lastNotificationAt) >= Constants.notificationDedupWindow else {
                return false
            }
            lastNotificationAt = now
            return true
        }
        guard shouldSchedule else { return }

        // Music fires a final "Stopped" `playerInfo` notification as it quits.
        // Round-tripping an Apple event back to a quitting app is exactly what
        // makes ScriptingBridge relaunch Music after the user closes it.
        // Resolve "Stopped" straight from the notification payload instead,
        // no Apple event, no relaunch. A genuine stop while Music stays open
        // resolves to "not playing"; a stop that coincides with quit resolves
        // to "not running" (and the terminate observer confirms it).
        if AppleMusicSource.isStoppedNotification(notification.userInfo) {
            // Cancel any idle-grace recheck: a recheck would send the very
            // Apple event we are avoiding. We already know nothing is playing.
            stateLock.withLock { lastTrackSeenAt = .distantPast }
            handleTrackInfo(musicIsRunning ? Constants.Status.notPlaying : Constants.Status.notRunning)
            return
        }

        Log.debug("AppleMusicSource: Music notification received", category: "Music")
        scheduleTrackCheck(reason: "notification")
    }

    /// `true` when a `com.apple.Music.playerInfo` payload reports the player as
    /// stopped. Music sends this both on an explicit stop and as its last gasp
    /// while quitting, so a stopped payload is the signal to skip the Apple
    /// event round-trip that would otherwise relaunch the app.
    nonisolated static func isStoppedNotification(_ userInfo: [AnyHashable: Any]?) -> Bool {
        (userInfo?[Constants.playerStateUserInfoKey] as? String) == Constants.playerStateStoppedString
    }

    /// Fetches the currently-playing track via ScriptingBridge.
    ///
    /// ScriptingBridge dispatches AppleEvents through the AE bridge, which
    /// requires main-thread access. We hop to `@MainActor` for the SB calls
    /// and back out for the cheap string/delegate work.
    nonisolated private func checkCurrentTrack() async {
        // Bail if tracking was stopped after this Task was scheduled. Keeps
        // in-flight checks from outliving stopTracking() and emitting stale
        // state. Mirrors the guard in forceRefresh and the timer handler.
        guard stateLock.withLock({ isTracking }) else { return }
        guard musicIsRunning else {
            handleTrackInfo(Constants.Status.notRunning)
            return
        }

        let result: (status: String, diagnostic: String?) = await MainActor.run {
            // Re-check on the main actor immediately before the first Apple
            // event. Music may have finished quitting between the guard above
            // and this hop; sending now would relaunch it.
            guard self.musicIsRunning else { return (Constants.Status.notRunning, nil) }
            guard let musicApp = SBApplication(bundleIdentifier: Constants.musicBundleIdentifier) else {
                return (Constants.Status.scriptBridgeNil, nil)
            }
            guard let stateObj = musicApp.value(forKey: "playerState") else {
                // Music is running (checked above) but ScriptingBridge can't
                // read its state. The canonical TCC Automation-denied
                // signature. Surface it as a distinct sentinel so the UI
                // can flip its permission banner without polling.
                return (Constants.Status.accessDenied, nil)
            }

            let stateRaw = AppleMusicSource.extractPlayerState(stateObj)
            let stateTypeDesc = String(describing: type(of: stateObj))
            let stateRawDesc = stateRaw.map(String.init) ?? "unparsed(\(stateObj))"
            let isTrackLoaded = AppleMusicSource.isTrackLoaded(stateRaw)

            let trackObj = musicApp.value(forKey: "currentTrack") as? SBObject
            let trackName = (trackObj?.value(forKey: "name") as? String) ?? ""

            // Primary: state says a track is loaded → emit.
            // Fallback: state parse failed (unknown bridge type) but Music
            // gave us a real track name → trust the track. Caller logs the
            // fallback path via `state-parse-fallback` so unknown bridges
            // surface without spam.
            let fallbackFired = stateRaw == nil && !trackName.isEmpty
            let shouldEmit = isTrackLoaded || fallbackFired
            guard shouldEmit, let track = trackObj, !trackName.isEmpty else {
                let trackPresence = trackObj == nil ? "nil" : "present"
                let probeArtist = (trackObj?.value(forKey: "artist") as? String) ?? ""
                let diag = "playerState=\(stateRawDesc) type=\(stateTypeDesc) currentTrack=\(trackPresence) name=\"\(trackName)\" artist=\"\(probeArtist)\""
                return (Constants.Status.notPlaying, diag)
            }

            let artist = track.value(forKey: "artist") as? String ?? ""
            let album = track.value(forKey: "album") as? String ?? ""
            let duration = (track.value(forKey: "duration") as? Double) ?? 0
            let elapsed = (musicApp.value(forKey: "playerPosition") as? Double) ?? 0
            let playlist = (musicApp.value(forKey: "currentPlaylist") as? SBObject)?
                .value(forKey: "name") as? String ?? ""
            // Paused only when Music.app explicitly reports `kPSp`. ffwd/rewind
            // and the unknown-bridge fallback path both count as "playing".
            let isPaused = stateRaw == Constants.playerStatePaused
            let combined = trackName + Constants.trackSeparator
                + artist + Constants.trackSeparator
                + album + Constants.trackSeparator
                + String(duration) + Constants.trackSeparator
                + String(elapsed) + Constants.trackSeparator
                + playlist + Constants.trackSeparator
                + (isPaused ? "1" : "0")
            let diag: String? = fallbackFired
                ? "raw=\(stateObj) type=\(stateTypeDesc)"
                : nil
            return (combined, diag)
        }

        if result.status == Constants.Status.notPlaying, let diag = result.diagnostic {
            // Diagnostic-only: capture what ScriptingBridge actually returned
            // when Music is running but we resolved to notPlaying. Helps
            // disambiguate genuine pause vs. partial-TCC placeholder reads.
            logGuardOnce(key: "diagnose-not-playing", message: "AppleMusicSource: diagnose-not-playing → \(diag)")
        } else if result.status != Constants.Status.notPlaying, let diag = result.diagnostic {
            // Fallback emit path. State parse failed but currentTrack.name
            // was non-empty so we trusted the track. Surface the unknown
            // bridge type once so we can add it to extractPlayerState natively.
            logGuardOnce(
                key: "state-parse-fallback",
                message: "AppleMusicSource: playerState bridge unknown: trusting currentTrack.name. \(diag)"
            )
        }
        handleTrackInfo(result.status)
    }

    /// Tolerant FourCharCode extractor for Music.app's `playerState`.
    ///
    /// ScriptingBridge has historically bridged this property as `NSNumber`,
    /// but macOS revisions have surfaced `Int`, raw `NSAppleEventDescriptor`
    /// (with the OSType in `typeCodeValue`), and even the FourCharCode as a
    /// 4-byte `String` (e.g. `"kPSP"`). Trying every realistic bridge keeps
    /// the now-playing read working across SDK updates instead of silently
    /// collapsing to `NOT_PLAYING`.
    static func extractPlayerState(_ raw: Any) -> UInt32? {
        if let num = raw as? NSNumber {
            return num.uint32Value
        }
        if let int = raw as? Int {
            return UInt32(truncatingIfNeeded: int)
        }
        if let uint = raw as? UInt32 {
            return uint
        }
        if let desc = raw as? NSAppleEventDescriptor {
            return UInt32(desc.typeCodeValue)
        }
        if let str = raw as? String, str.utf8.count == 4 {
            var packed: UInt32 = 0
            for byte in str.utf8 {
                packed = (packed << 8) | UInt32(byte)
            }
            return packed
        }
        return nil
    }

    /// The `playerState` values that mean a track is loaded and should be
    /// emitted to the now-playing UI, Discord Rich Presence, and the overlay.
    ///
    /// Playing (`kPSP`), paused (`kPSp`), fast-forward (`kPSF`), and rewind
    /// (`kPSR`) all count as "loaded": pausing must NOT blank the UI. Stopped
    /// (`kPSS`) and an unparsed/`nil` state are not track-loaded. This decision
    /// set is a locked invariant covered by `AppleMusicSourceTests`; do not
    /// narrow it (dropping ffwd/rewind, or treating pause as not-loaded, would
    /// silently blank the card while Music is active).
    static func isTrackLoaded(_ state: UInt32?) -> Bool {
        guard let state else { return false }
        return state == Constants.playerStatePlaying
            || state == Constants.playerStatePaused
            || state == Constants.playerStateFastForward
            || state == Constants.playerStateRewinding
    }

    // MARK: - Private Helpers

    nonisolated private func notifyDelegate(status: String) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.delegate?.playbackSource(didUpdateStatus: status)
        }
    }

    nonisolated private func notifyDelegate(track: String, artist: String, album: String, playlist: String, duration: TimeInterval, elapsed: TimeInterval, isPaused: Bool) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.delegate?.playbackSource(didUpdateTrack: track, artist: artist, album: album, playlist: playlist, duration: duration, elapsed: elapsed, isPaused: isPaused)
        }
    }

    nonisolated private func processTrackInfoString(_ trackInfo: String) {
        let components = trackInfo.components(separatedBy: Constants.trackSeparator)
        guard components.count >= 3 else { return }
        let trackName = components[0]
        let artist = components[1]
        let album = components[2]
        let duration = components.count > 3 ? (Double(components[3]) ?? 0) : 0
        let elapsed = components.count > 4 ? (Double(components[4]) ?? 0) : 0
        let playlist = components.count > 5 ? components[5] : ""
        // Component 6 is the paused flag ("1"/"0"). Older callers that
        // don't append it fall back to "playing".
        let isPaused = components.count > 6 ? (components[6] == "1") : false
        stateLock.withLock {
            lastTrackSeenAt = Date()
            // Reset the guard-log dedup gate so a future failure logs again.
            lastGuardLogged = nil
        }
        notifyDelegate(track: trackName, artist: artist, album: album, playlist: playlist, duration: duration, elapsed: elapsed, isPaused: isPaused)
        logTrackIfNew(trackInfo, trackName: trackName, artist: artist, album: album)
    }

    nonisolated private func handleTrackInfo(_ trackInfo: String) {
        if trackInfo.hasPrefix(Constants.Status.errorPrefix) {
            logGuardOnce(key: "script-error", message: "AppleMusicSource: ScriptingBridge returned error: \(trackInfo)")
            notifyDelegate(status: Constants.DelegateStatus.scriptError)
        } else if trackInfo == Constants.Status.notRunning {
            logGuardOnce(key: "not-running", message: "AppleMusicSource: Music.app not running")
            notifyDelegate(status: Constants.DelegateStatus.musicNotRunning)
        } else if trackInfo == Constants.Status.accessDenied {
            // Music IS running but ScriptingBridge can't read state. TCC denied.
            logGuardOnce(key: "access-denied", message: "AppleMusicSource: Music.app running but ScriptingBridge read returned nil: Automation permission likely denied")
            notifyDelegate(status: Constants.DelegateStatus.accessDenied)
        } else if trackInfo == Constants.Status.scriptBridgeNil {
            logGuardOnce(key: "sb-nil", message: "AppleMusicSource: SBApplication(bundleIdentifier:) returned nil")
            notifyDelegate(status: Constants.DelegateStatus.noTrackInfo)
        } else if trackInfo == Constants.Status.notPlaying {
            handleNotPlayingState()
        } else {
            processTrackInfoString(trackInfo)
        }
    }

    /// Deduped warning log for a guard-failure category. The next failure of
    /// the same key is suppressed until either a different key fires or a
    /// successful track read resets the gate (see `processTrackInfoString`).
    nonisolated private func logGuardOnce(key: String, message: String) {
        let shouldLog = stateLock.withLock { () -> Bool in
            guard lastGuardLogged != key else { return false }
            lastGuardLogged = key
            return true
        }
        guard shouldLog else { return }
        Log.warn(message, category: "Music")
    }

    nonisolated private func handleNotPlayingState() {
        let lastSeen = stateLock.withLock { lastTrackSeenAt }
        let idleDuration = Date().timeIntervalSince(lastSeen)
        if idleDuration < Constants.idleGraceWindow {
            scheduleTrackCheck(after: 0.5, reason: "idle-grace-recheck")
            return
        }
        notifyDelegate(status: Constants.DelegateStatus.noTrackPlaying)
    }

    nonisolated private func logTrackIfNew(_ trackInfo: String, trackName: String, artist: String, album: String) {
        let dedupKey = trackName + Constants.trackSeparator + artist + Constants.trackSeparator + album
        let isNew = stateLock.withLock { () -> Bool in
            guard lastLoggedTrack != dedupKey else { return false }
            lastLoggedTrack = dedupKey
            return true
        }
        guard isNew else { return }
        Log.debug("AppleMusicSource: Now Playing → \(trackName) by \(artist) [\(album)]", category: "Music")
    }

    nonisolated private func subscribeToMusicNotifications() {
        DistributedNotificationCenter.default().addObserver(self, selector: #selector(musicPlayerInfoChanged), name: NSNotification.Name(Constants.notificationName), object: nil)

        // Flip to NOT_RUNNING the moment Music.app quits, instead of waiting
        // for the next fallback poll. This is observation only; it never
        // sends an Apple event, so it cannot relaunch the app.
        let token = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didTerminateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] note in
            guard let self else { return }
            let bundleID = (note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.bundleIdentifier
            guard bundleID == Constants.musicBundleIdentifier else { return }
            self.handleMusicTerminated()
        }
        stateLock.withLock { musicTerminateObserver = token }
    }

    nonisolated private func handleMusicTerminated() {
        // Clear the "recently seen a track" gate so the idle-grace path can't
        // hold a stale track on screen after Music is gone.
        stateLock.withLock {
            lastTrackSeenAt = .distantPast
            lastNotificationAt = .distantPast
        }
        handleTrackInfo(Constants.Status.notRunning)
    }

    nonisolated private func performInitialTrackCheck() {
        scheduleTrackCheck(reason: "initial")
    }

    nonisolated private func setupFallbackTimer() {
        let interval = stateLock.withLock { currentCheckInterval }
        let newTimer = DispatchSource.makeTimerSource(queue: backgroundQueue)
        // This is a *fallback* poll. Real-time track changes arrive via the
        // distributed notification. Give the timer generous leeway (20% of the
        // interval) so macOS can coalesce its wakeups with other system timers,
        // cutting idle energy use for an all-day menu bar app. The fallback
        // doesn't need millisecond precision.
        newTimer.schedule(
            deadline: .now() + interval,
            repeating: interval,
            leeway: .milliseconds(Int(interval * 200))
        )
        newTimer.setEventHandler { [weak self] in
            guard let self, self.stateLock.withLock({ self.isTracking }) else { return }
            self.scheduleTrackCheck(reason: "timer")
        }
        // Swap the timer reference and cancel any prior one in a single
        // critical section so a future off-main caller cannot orphan a live
        // DispatchSourceTimer between the read and the assignment.
        let previousTimer = stateLock.withLock { () -> DispatchSourceTimer? in
            let existing = timer
            timer = newTimer
            return existing
        }
        previousTimer?.cancel()
        newTimer.activate()
    }

    nonisolated private func scheduleTrackCheck(reason: String) {
        Task { [weak self] in
            await self?.checkCurrentTrack()
        }
    }

    nonisolated private func scheduleTrackCheck(after delay: TimeInterval, reason: String) {
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            await self?.checkCurrentTrack()
        }
    }
}
