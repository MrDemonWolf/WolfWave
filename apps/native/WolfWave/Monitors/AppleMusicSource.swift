//
//  AppleMusicSource.swift
//  WolfWave
//
//  Created by Nathanial Henniges on 2026-01-08.
//  Copyright © 2026 MrDemonWolf, Inc. All rights reserved.
//

import AppKit
import Foundation
import ScriptingBridge

/// Captures ScriptingBridge command failures so the bridge returns nil instead
/// of raising an Objective-C exception that Swift cannot catch.
///
/// SBApplication does not own its delegate's lifetime, so AppleMusicSource owns this
/// instance for its full lifetime. The lock covers callback access even if a
/// future framework version invokes the delegate away from the main thread.
nonisolated final class MusicScriptingBridgeErrorDelegate:
    NSObject, SBApplicationDelegate, @unchecked Sendable {
    private let lock = NSLock()
    private var storedError: (any Error)?

    /// Clears any failure from the preceding ScriptingBridge operation.
    func reset() {
        lock.withLock { storedError = nil }
    }

    /// Returns and clears the latest bridge failure.
    func takeError() -> (any Error)? {
        lock.withLock {
            defer { storedError = nil }
            return storedError
        }
    }

    /// Internal test seam for the same synchronized path used by the callback.
    func record(_ error: any Error) {
        lock.withLock { storedError = error }
    }

    func eventDidFail(
        _ event: UnsafePointer<AppleEvent>,
        withError error: any Error
    ) -> Any? {
        record(error)
        return nil
    }
}

// The monitor keeps one lock-protected lifecycle and its parsing helpers together.
// swiftlint:disable:next type_body_length
final class AppleMusicSource: @unchecked Sendable {

    typealias TrackInfoProvider = @Sendable () async -> String

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
        static let notificationDedupWindow: Duration = .milliseconds(750)
        static let idleGraceWindow: Duration = .seconds(2)
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

        /// Names the ScriptingBridge read a failure came from.
        ///
        /// Two jobs. It rides along in the diagnostic so a logged bridge failure
        /// says *which* Apple Event was refused, and it gates the `-1728`
        /// permission mapping in `status(forBridgeError:in:)` to the one read
        /// where that code cannot also mean "nothing loaded".
        enum BridgeStage {
            static let isRunning = "isRunning"
            static let playerState = "playerState"
            static let currentTrack = "currentTrack"
            static let trackMetadata = "trackMetadata"
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
    nonisolated(unsafe) private var lastTrackSeenAt: ContinuousClock.Instant?
    nonisolated(unsafe) private var lastNotificationAt: ContinuousClock.Instant?
    nonisolated(unsafe) private var isTracking = false
    /// Monotonic identity for one start/stop lifecycle. A plain `isTracking`
    /// check cannot distinguish work from before a stop/start ABA transition.
    nonisolated(unsafe) private var trackingGeneration: UInt64 = 0
    /// Dedup gate for guard-failure logs. Same key won't log twice in a row.
    /// A successful track read resets this so the next failure logs again.
    nonisolated(unsafe) private var lastGuardLogged: String?
    /// Token for the `NSWorkspace` "Music.app terminated" observer. Lets us
    /// flip to NOT_RUNNING the instant the user quits Music, rather than
    /// waiting for the next fallback poll.
    nonisolated(unsafe) private var musicTerminateObserver: NSObjectProtocol?

    private let backgroundQueue = DispatchQueue(label: Constants.queueLabel, qos: .utility)
    private let clock = ContinuousClock()
    private let scriptingBridgeErrorDelegate = MusicScriptingBridgeErrorDelegate()
    private let trackInfoProvider: TrackInfoProvider?
    private let didScheduleFallbackTimer: (@Sendable (TimeInterval) -> Void)?
    private let didCompleteTrackCheck: (@Sendable () -> Void)?

    init(
        trackInfoProvider: TrackInfoProvider? = nil,
        didScheduleFallbackTimer: (@Sendable (TimeInterval) -> Void)? = nil,
        didCompleteTrackCheck: (@Sendable () -> Void)? = nil
    ) {
        self.trackInfoProvider = trackInfoProvider
        self.didScheduleFallbackTimer = didScheduleFallbackTimer
        self.didCompleteTrackCheck = didCompleteTrackCheck
    }

    /// Whether Music.app is genuinely running. Filters out instances that have
    /// already terminated, so the quit window (still listed, not yet gone)
    /// reads as not-running. Reading this never launches Music.app.
    nonisolated private var musicIsRunning: Bool { MusicProcess.isRunning }

    // MARK: - Protocol Conformance

    func startTracking() {
        let generation = stateLock.withLock { () -> UInt64? in
            guard !isTracking else { return nil }
            isTracking = true
            trackingGeneration &+= 1
            return trackingGeneration
        }
        guard let generation else { return }
        subscribeToMusicNotifications(generation: generation)
        performInitialTrackCheck(generation: generation)
        setupFallbackTimer(generation: generation)
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
            trackingGeneration &+= 1
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
        let (cancelled, generation) = stateLock.withLock {
            () -> (DispatchSourceTimer?, UInt64?) in
            currentCheckInterval = max(interval, 1.0)
            guard isTracking else { return (nil, nil) }
            let existing = timer
            timer = nil
            return (existing, trackingGeneration)
        }
        cancelled?.cancel()
        if let generation {
            setupFallbackTimer(generation: generation)
        }
    }

    nonisolated func forceRefresh() {
        let generation = stateLock.withLock { () -> UInt64? in
            guard isTracking else { return nil }
            // Clear the notification dedup gate so a user-initiated refresh
            // immediately after a system notification is not dropped.
            lastNotificationAt = nil
            return trackingGeneration
        }
        guard let generation else { return }
        scheduleTrackCheck(reason: "force-refresh", generation: generation)
    }

    // MARK: - Playback Monitoring

    @objc nonisolated private func musicPlayerInfoChanged(_ notification: Notification) {
        let now = clock.now
        let generation = stateLock.withLock { () -> UInt64? in
            guard isTracking else { return nil }
            guard Self.intervalElapsed(
                since: lastNotificationAt,
                now: now,
                minimum: Constants.notificationDedupWindow
            ) else {
                return nil
            }
            lastNotificationAt = now
            return trackingGeneration
        }
        guard let generation else { return }

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
            let isCurrent = stateLock.withLock { () -> Bool in
                guard isTracking, trackingGeneration == generation else { return false }
                lastTrackSeenAt = nil
                return true
            }
            guard isCurrent else { return }
            handleTrackInfo(
                musicIsRunning ? Constants.Status.notPlaying : Constants.Status.notRunning,
                generation: generation
            )
            return
        }

        Log.debug("AppleMusicSource: Music notification received", category: "Music")
        scheduleTrackCheck(reason: "notification", generation: generation)
    }

    /// `true` when a `com.apple.Music.playerInfo` payload reports the player as
    /// stopped. Music sends this both on an explicit stop and as its last gasp
    /// while quitting, so a stopped payload is the signal to skip the Apple
    /// event round-trip that would otherwise relaunch the app.
    nonisolated static func isStoppedNotification(_ userInfo: [AnyHashable: Any]?) -> Bool {
        (userInfo?[Constants.playerStateUserInfoKey] as? String) == Constants.playerStateStoppedString
    }

    /// Whether at least minimum monotonic time has elapsed. A nil starting
    /// instant represents an open gate.
    nonisolated static func intervalElapsed(
        since start: ContinuousClock.Instant?,
        now: ContinuousClock.Instant,
        minimum: Duration
    ) -> Bool {
        guard let start else { return true }
        return start.duration(to: now) >= minimum
    }

    /// Maps bridge failures that have actionable lifecycle/permission meaning to
    /// their existing sentinels; all other errors retain a diagnostic message.
    ///
    /// - Parameter stage: which ScriptingBridge read failed. See
    ///   `Constants.BridgeStage`. Only `playerState` may treat `-1728` as a
    ///   permission answer.
    nonisolated static func status(forBridgeError error: any Error, in stage: String) -> String {
        let cocoaError = error as NSError
        switch cocoaError.code {
        case -600, -609:
            return Constants.Status.notRunning
        case -1743:
            return Constants.Status.accessDenied
        case -1728 where stage == Constants.BridgeStage.playerState:
            // macOS 26 answers a refused Automation request with -1728
            // (errAENoSuchObject), not the documented -1743. Confirmed on
            // macOS 26: a client without the grant gets
            // "osascript is not allowed assistive access. (-1728)".
            //
            // This is only safe to read as "denied" for `player state`. It is an
            // application-level property that always resolves while Music is
            // running, and both `isRunning` and `responds(to:)` have already
            // passed by the time we ask, so there is no object for it to be
            // legitimately missing. On the `currentTrack` and metadata stages
            // -1728 genuinely means "nothing loaded", so those keep the generic
            // mapping. Getting this wrong in the other direction would show a
            // permission banner every time Music sat idle.
            //
            // Without this, a denied grant surfaced as "Script error" and the
            // permission banner never appeared, so the user had no way to learn
            // that Automation needed granting.
            return Constants.Status.accessDenied
        default:
            return Constants.Status.errorPrefix + cocoaError.localizedDescription
        }
    }

    // swiftlint:disable cyclomatic_complexity function_body_length
    /// Fetches the currently-playing track via ScriptingBridge.
    ///
    /// ScriptingBridge dispatches AppleEvents through the AE bridge, which
    /// requires main-thread access. We hop to `@MainActor` for the SB calls
    /// and back out for the cheap string/delegate work.
    nonisolated private func checkCurrentTrack(generation: UInt64) async {
        guard isCurrentTrackingGeneration(generation) else { return }
        defer { didCompleteTrackCheck?() }
        if let trackInfoProvider {
            let trackInfo = await trackInfoProvider()
            guard isCurrentTrackingGeneration(generation) else { return }
            handleTrackInfo(trackInfo, generation: generation)
            return
        }
        guard musicIsRunning else {
            handleTrackInfo(Constants.Status.notRunning, generation: generation)
            return
        }

        let result: (status: String, diagnostic: String?) = await MainActor.run {
            // Address Music by pid, never by bundle id. A bundle-id-addressed
            // Apple event is auto-launched by LaunchServices, so the previous
            // `SBApplication(bundleIdentifier:)` relaunched Music whenever the
            // user quit it in the window between the running-check and the send.
            // Resolving the pid and targeting that exact process makes the
            // relaunch structurally impossible: a dead pid fails the send instead
            // of starting the app. See `MusicProcess` for the full rationale.
            guard let pid = MusicProcess.pid else {
                return (Constants.Status.notRunning, nil)
            }
            guard let musicApp = SBApplication(processIdentifier: pid) else {
                return (Constants.Status.scriptBridgeNil, nil)
            }
            let bridgeDelegate = scriptingBridgeErrorDelegate
            bridgeDelegate.reset()
            musicApp.delegate = bridgeDelegate
            // `stage` names the read that failed. It rides along in the
            // diagnostic so a future failure says *which* Apple Event was
            // refused instead of only that one was, and it gates the
            // permission-denial mapping to the one read where -1728 cannot mean
            // anything else. See `status(forBridgeError:in:)`.
            func bridgeFailure(_ stage: String) -> (status: String, diagnostic: String?)? {
                guard let error = bridgeDelegate.takeError() else { return nil }
                return (
                    AppleMusicSource.status(forBridgeError: error, in: stage),
                    "stage=\(stage) code=\((error as NSError).code)"
                )
            }
            // `SBApplication(processIdentifier:)` does NOT return nil for a pid it
            // can't resolve, despite what its header says: it hands back a plain
            // `SBApplication` that is not KVC-compliant, and `value(forKey:)` on it
            // raises `NSUnknownKeyException` — an ObjC exception Swift cannot catch,
            // so the app would crash. That happens when the pid dies between the
            // lookup above and this construction. A resolved target reports
            // `isRunning == true` and responds to the accessor; an unresolved one
            // fails both. Verified on macOS 26 with a bogus pid.
            guard musicApp.isRunning else {
                if let failure = bridgeFailure(Constants.BridgeStage.isRunning) { return failure }
                return (Constants.Status.notRunning, nil)
            }
            guard musicApp.responds(to: NSSelectorFromString("playerState")) else {
                return (Constants.Status.notRunning, nil)
            }
            guard let stateObj = musicApp.value(forKey: "playerState") else {
                if let failure = bridgeFailure(Constants.BridgeStage.playerState) { return failure }
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
                if let failure = bridgeFailure(Constants.BridgeStage.currentTrack) { return failure }
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
            if let failure = bridgeFailure(Constants.BridgeStage.trackMetadata) { return failure }
            return (combined, diag)
        }

        guard isCurrentTrackingGeneration(generation) else { return }
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
        handleTrackInfo(result.status, generation: generation)
    }
    // swiftlint:enable cyclomatic_complexity function_body_length

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

    nonisolated private func notifyDelegate(status: String, generation: UInt64) {
        Task { @MainActor [weak self] in
            guard let self, self.isCurrentTrackingGeneration(generation) else { return }
            self.delegate?.playbackSource(didUpdateStatus: status)
        }
    }

    // Mirrors PlaybackSourceDelegate plus the lifecycle generation guard.
    // swiftlint:disable:next function_parameter_count
    nonisolated private func notifyDelegate(
        track: String,
        artist: String,
        album: String,
        playlist: String,
        duration: TimeInterval,
        elapsed: TimeInterval,
        isPaused: Bool,
        generation: UInt64
    ) {
        Task { @MainActor [weak self] in
            guard let self, self.isCurrentTrackingGeneration(generation) else { return }
            self.delegate?.playbackSource(didUpdateTrack: track, artist: artist, album: album, playlist: playlist, duration: duration, elapsed: elapsed, isPaused: isPaused)
        }
    }

    nonisolated private func processTrackInfoString(_ trackInfo: String, generation: UInt64) {
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
        let isCurrent = stateLock.withLock { () -> Bool in
            guard isTracking, trackingGeneration == generation else { return false }
            lastTrackSeenAt = clock.now
            // Reset the guard-log dedup gate so a future failure logs again.
            lastGuardLogged = nil
            return true
        }
        guard isCurrent else { return }
        notifyDelegate(
            track: trackName,
            artist: artist,
            album: album,
            playlist: playlist,
            duration: duration,
            elapsed: elapsed,
            isPaused: isPaused,
            generation: generation
        )
        logTrackIfNew(trackInfo, trackName: trackName, artist: artist, album: album)
    }

    nonisolated private func handleTrackInfo(_ trackInfo: String, generation: UInt64) {
        guard isCurrentTrackingGeneration(generation) else { return }
        if trackInfo.hasPrefix(Constants.Status.errorPrefix) {
            logGuardOnce(key: "script-error", message: "AppleMusicSource: ScriptingBridge returned error: \(trackInfo)")
            notifyDelegate(status: Constants.DelegateStatus.scriptError, generation: generation)
        } else if trackInfo == Constants.Status.notRunning {
            logGuardOnce(key: "not-running", message: "AppleMusicSource: Music.app not running")
            notifyDelegate(status: Constants.DelegateStatus.musicNotRunning, generation: generation)
        } else if trackInfo == Constants.Status.accessDenied {
            // Music IS running but ScriptingBridge can't read state. TCC denied.
            logGuardOnce(key: "access-denied", message: "AppleMusicSource: Music.app running but ScriptingBridge read returned nil: Automation permission likely denied")
            notifyDelegate(status: Constants.DelegateStatus.accessDenied, generation: generation)
        } else if trackInfo == Constants.Status.scriptBridgeNil {
            logGuardOnce(key: "sb-nil", message: "AppleMusicSource: SBApplication(processIdentifier:) returned nil")
            notifyDelegate(status: Constants.DelegateStatus.noTrackInfo, generation: generation)
        } else if trackInfo == Constants.Status.notPlaying {
            handleNotPlayingState(generation: generation)
        } else {
            processTrackInfoString(trackInfo, generation: generation)
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

    nonisolated private func handleNotPlayingState(generation: UInt64) {
        let lastSeen = stateLock.withLock { lastTrackSeenAt }
        guard let lastSeen else {
            notifyDelegate(status: Constants.DelegateStatus.noTrackPlaying, generation: generation)
            return
        }
        if lastSeen.duration(to: clock.now) < Constants.idleGraceWindow {
            scheduleTrackCheck(
                after: 0.5,
                reason: "idle-grace-recheck",
                generation: generation
            )
            return
        }
        notifyDelegate(status: Constants.DelegateStatus.noTrackPlaying, generation: generation)
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

    nonisolated private func subscribeToMusicNotifications(generation: UInt64) {
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
            self.handleMusicTerminated(generation: generation)
        }
        stateLock.withLock { musicTerminateObserver = token }
    }

    nonisolated private func handleMusicTerminated(generation: UInt64) {
        // Clear the "recently seen a track" gate so the idle-grace path can't
        // hold a stale track on screen after Music is gone.
        let isCurrent = stateLock.withLock { () -> Bool in
            guard isTracking, trackingGeneration == generation else { return false }
            lastTrackSeenAt = nil
            lastNotificationAt = nil
            return true
        }
        guard isCurrent else { return }
        handleTrackInfo(Constants.Status.notRunning, generation: generation)
    }

    nonisolated private func performInitialTrackCheck(generation: UInt64) {
        scheduleTrackCheck(reason: "initial", generation: generation)
    }

    nonisolated private func setupFallbackTimer(generation: UInt64) {
        let interval = stateLock.withLock { () -> TimeInterval? in
            guard isTracking, trackingGeneration == generation else { return nil }
            return currentCheckInterval
        }
        guard let interval else { return }
        didScheduleFallbackTimer?(interval)
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
            guard let self, self.isCurrentTrackingGeneration(generation) else { return }
            self.scheduleTrackCheck(reason: "timer", generation: generation)
        }
        // Swap the timer reference and cancel any prior one in a single
        // critical section so a future off-main caller cannot orphan a live
        // DispatchSourceTimer between the read and the assignment.
        let (previousTimer, installed) = stateLock.withLock {
            () -> (DispatchSourceTimer?, Bool) in
            guard isTracking, trackingGeneration == generation else { return (nil, false) }
            let existing = timer
            timer = newTimer
            return (existing, true)
        }
        guard installed else {
            newTimer.activate()
            newTimer.cancel()
            return
        }
        previousTimer?.cancel()
        newTimer.activate()
    }

    nonisolated private func scheduleTrackCheck(reason: String, generation: UInt64) {
        guard isCurrentTrackingGeneration(generation) else { return }
        Task { [weak self] in
            Log.debug("AppleMusicSource: track check scheduled (\(reason))", category: "Music")
            await self?.checkCurrentTrack(generation: generation)
        }
    }

    nonisolated private func scheduleTrackCheck(
        after delay: TimeInterval,
        reason: String,
        generation: UInt64
    ) {
        guard isCurrentTrackingGeneration(generation) else { return }
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            Log.debug("AppleMusicSource: delayed track check fired (\(reason))", category: "Music")
            await self?.checkCurrentTrack(generation: generation)
        }
    }

    nonisolated private func isCurrentTrackingGeneration(_ generation: UInt64) -> Bool {
        stateLock.withLock { isTracking && trackingGeneration == generation }
    }
}
