//
//  AppleMusicSourceTests.swift
//  WolfWave
//
//  Created by Nathanial Henniges on 2026-02-27.
//  Copyright © 2026 MrDemonWolf, Inc. All rights reserved.
//

import Foundation
import XCTest
@testable import WolfWave

@MainActor
final class AppleMusicSourceTests: XCTestCase {
    var monitor: AppleMusicSource!

    override func setUp() {
        super.setUp()
        monitor = AppleMusicSource()
    }

    override func tearDown() {
        monitor.stopTracking()
        monitor = nil
        super.tearDown()
    }

    // MARK: - Initialization Tests

    func testDelegateIsNilByDefault() {
        XCTAssertNil(monitor.delegate)
    }

    // MARK: - ScriptingBridge Failure Handling

    func testBridgeDelegateReturnsAndClearsRecordedError() {
        let delegate = MusicScriptingBridgeErrorDelegate()
        let expected = NSError(
            domain: "AppleMusicSourceTests",
            code: 42,
            userInfo: [NSLocalizedDescriptionKey: "Bridge failed"]
        )

        delegate.record(expected)

        guard let captured = delegate.takeError() else {
            XCTFail("Expected the recorded bridge error")
            return
        }
        XCTAssertEqual((captured as NSError).code, 42)
        XCTAssertEqual(captured.localizedDescription, "Bridge failed")
        XCTAssertNil(delegate.takeError())
    }

    func testBridgeErrorStatusMapsTargetAndPermissionFailures() {
        let domain = "AppleMusicSourceTests"
        let anyStage = "playerState"
        XCTAssertEqual(
            AppleMusicSource.status(forBridgeError: NSError(domain: domain, code: -600), in: anyStage),
            "NOT_RUNNING"
        )
        XCTAssertEqual(
            AppleMusicSource.status(forBridgeError: NSError(domain: domain, code: -609), in: anyStage),
            "NOT_RUNNING"
        )
        XCTAssertEqual(
            AppleMusicSource.status(forBridgeError: NSError(domain: domain, code: -1_743), in: anyStage),
            "ACCESS_DENIED"
        )
    }

    /// macOS 26 answers a refused Automation request with -1728, not the
    /// documented -1743, so the old bare -1743 check reported a denial as a
    /// generic "Script error" and the permission banner never appeared. Reading
    /// -1728 as denial is only sound for `player state`: it is an
    /// application-level property that always resolves while Music is running,
    /// and `isRunning` plus `responds(to:)` have already passed by then.
    func testPlayerStateMinusOneSevenTwoEightIsTreatedAsPermissionDenial() {
        let error = NSError(domain: "AppleMusicSourceTests", code: -1_728)

        XCTAssertEqual(
            AppleMusicSource.status(forBridgeError: error, in: "playerState"),
            "ACCESS_DENIED"
        )
    }

    /// The other direction matters more. On the track stages -1728 genuinely
    /// means "nothing loaded", so mapping it to a denial there would raise a
    /// permission banner every time Music sat idle.
    func testTrackStageMinusOneSevenTwoEightIsNotAPermissionDenial() {
        let error = NSError(domain: "AppleMusicSourceTests", code: -1_728)

        for stage in ["isRunning", "currentTrack", "trackMetadata"] {
            XCTAssertNotEqual(
                AppleMusicSource.status(forBridgeError: error, in: stage),
                "ACCESS_DENIED",
                "stage \(stage) must not report an idle Music as a permission denial"
            )
        }
    }

    func testIntervalElapsedUsesMonotonicInstants() {
        let clock = ContinuousClock()
        let start = clock.now

        XCTAssertTrue(AppleMusicSource.intervalElapsed(
            since: nil,
            now: start,
            minimum: .seconds(1)
        ))
        XCTAssertFalse(AppleMusicSource.intervalElapsed(
            since: start,
            now: start.advanced(by: .milliseconds(500)),
            minimum: .seconds(1)
        ))
        XCTAssertTrue(AppleMusicSource.intervalElapsed(
            since: start,
            now: start.advanced(by: .seconds(1)),
            minimum: .seconds(1)
        ))
    }

    // MARK: - Tracking lifecycle

    func testIntervalUpdatedWhileStoppedIsClampedAndUsedOnNextStart() {
        let scheduledIntervals = ThreadSafeBox<[TimeInterval]>([])
        monitor = AppleMusicSource(
            trackInfoProvider: { "NOT_RUNNING" },
            didScheduleFallbackTimer: { interval in
                scheduledIntervals.mutate { $0.append(interval) }
            }
        )

        monitor.updateCheckInterval(0.25)
        XCTAssertEqual(scheduledIntervals.value, [])

        monitor.startTracking()
        XCTAssertEqual(scheduledIntervals.value, [1.0])

        monitor.updateCheckInterval(12)
        XCTAssertEqual(scheduledIntervals.value, [1.0, 12.0])

        monitor.stopTracking()
        monitor.updateCheckInterval(20)
        XCTAssertEqual(scheduledIntervals.value, [1.0, 12.0])

        monitor.startTracking()
        XCTAssertEqual(scheduledIntervals.value, [1.0, 12.0, 20.0])
    }

    func testProbeFinishingAfterStopCannotPublish() async {
        let probe = SuspendedAppleMusicProbe()
        let completedChecks = ThreadSafeBox(0)
        let capture = AppleMusicSourceCaptureDelegate()
        monitor = AppleMusicSource(
            trackInfoProvider: { await probe.next() },
            didCompleteTrackCheck: {
                completedChecks.mutate { $0 += 1 }
            }
        )
        monitor.delegate = capture

        monitor.startTracking()
        let firstProbeStarted = await waitUntil { await probe.callCount == 1 }
        XCTAssertTrue(firstProbeStarted)
        monitor.stopTracking()
        await probe.releaseFirst(with: "NOT_RUNNING")
        let stoppedProbeCompleted = await waitUntil { completedChecks.value == 1 }
        XCTAssertTrue(stoppedProbeCompleted)
        await Task.yield()

        XCTAssertEqual(capture.statuses, [])
    }

    func testProbeFromPreviousGenerationCannotPublishAfterRestart() async {
        let probe = SuspendedAppleMusicProbe()
        let completedChecks = ThreadSafeBox(0)
        let capture = AppleMusicSourceCaptureDelegate()
        monitor = AppleMusicSource(
            trackInfoProvider: { await probe.next() },
            didCompleteTrackCheck: {
                completedChecks.mutate { $0 += 1 }
            }
        )
        monitor.delegate = capture

        monitor.startTracking()
        let firstGenerationStarted = await waitUntil { await probe.callCount == 1 }
        XCTAssertTrue(firstGenerationStarted)
        monitor.stopTracking()
        monitor.startTracking()

        let restartedProbePublished = await waitUntil {
            let callCount = await probe.callCount
            return callCount == 2 && capture.statuses == ["Music not running"]
        }
        XCTAssertTrue(restartedProbePublished)

        await probe.releaseFirst(with: "NOT_RUNNING")
        let bothProbesCompleted = await waitUntil { completedChecks.value == 2 }
        XCTAssertTrue(bothProbesCompleted)
        await Task.yield()

        XCTAssertEqual(capture.statuses, ["Music not running"])
    }

    // MARK: - extractPlayerState (tolerant FourCharCode parser)

    private static let kPSP: UInt32 = 1800426320  // 'kPSP': playing
    private static let kPSp: UInt32 = 1800426352  // 'kPSp': paused

    func testExtractPlayerStateFromNSNumber() {
        let raw: NSNumber = NSNumber(value: Self.kPSP)
        XCTAssertEqual(AppleMusicSource.extractPlayerState(raw), Self.kPSP)
    }

    func testExtractPlayerStateFromInt() {
        let raw: Int = Int(Self.kPSp)
        XCTAssertEqual(AppleMusicSource.extractPlayerState(raw), Self.kPSp)
    }

    func testExtractPlayerStateFromUInt32() {
        let raw: UInt32 = Self.kPSP
        XCTAssertEqual(AppleMusicSource.extractPlayerState(raw), Self.kPSP)
    }

    func testExtractPlayerStateFromFourCharString() {
        XCTAssertEqual(AppleMusicSource.extractPlayerState("kPSP"), Self.kPSP)
        XCTAssertEqual(AppleMusicSource.extractPlayerState("kPSp"), Self.kPSp)
    }

    func testExtractPlayerStateFromAppleEventDescriptor() {
        let desc = NSAppleEventDescriptor(typeCode: Self.kPSP)
        XCTAssertEqual(AppleMusicSource.extractPlayerState(desc), Self.kPSP)
    }

    func testExtractPlayerStateRejectsWrongLengthString() {
        XCTAssertNil(AppleMusicSource.extractPlayerState("kPS"))
        XCTAssertNil(AppleMusicSource.extractPlayerState("kPSPextra"))
    }

    func testExtractPlayerStateRejectsUnknownType() {
        struct Bogus {}
        XCTAssertNil(AppleMusicSource.extractPlayerState(Bogus()))
        XCTAssertNil(AppleMusicSource.extractPlayerState([1, 2, 3]))
    }

    // MARK: - isTrackLoaded (locked decision set)

    private static let kPSF: UInt32 = 1800426310  // 'kPSF': fast-forward
    private static let kPSR: UInt32 = 1800426322  // 'kPSR': rewind
    private static let kPSS: UInt32 = 1800426323  // 'kPSS': stopped

    /// Playing, paused, fast-forward, and rewind all mean "a track is loaded"
    /// and must emit. Pausing deliberately keeps the UI / Discord / overlay
    /// showing the loaded track. Locked invariant: do not narrow this set.
    func testIsTrackLoadedTrueForPlayingPausedFastForwardRewind() {
        XCTAssertTrue(AppleMusicSource.isTrackLoaded(Self.kPSP))
        XCTAssertTrue(AppleMusicSource.isTrackLoaded(Self.kPSp))
        XCTAssertTrue(AppleMusicSource.isTrackLoaded(Self.kPSF))
        XCTAssertTrue(AppleMusicSource.isTrackLoaded(Self.kPSR))
    }

    /// Stopped (`kPSS`) and an unparsed/`nil` state are the only not-loaded
    /// cases. Dropping a true case or adding `kPSS` here must fail this test.
    func testIsTrackLoadedFalseForStoppedAndNil() {
        XCTAssertFalse(AppleMusicSource.isTrackLoaded(Self.kPSS))
        XCTAssertFalse(AppleMusicSource.isTrackLoaded(nil))
    }

    /// Locks the numeric `kPSS` constant to the actual FourCharCode: the
    /// byte-packed string "kPSS" must decode to the same value. A wrong
    /// constant (e.g. the old 'kPRS' typo) fails here.
    func testStoppedConstantRoundTripsToKPSS() {
        XCTAssertEqual(AppleMusicSource.extractPlayerState("kPSS"), Self.kPSS)
    }

    /// An unknown FourCharCode is not track-loaded; the unknown-bridge fallback
    /// path keys off `currentTrack.name` instead, not this decision.
    func testIsTrackLoadedFalseForUnknownState() {
        XCTAssertFalse(AppleMusicSource.isTrackLoaded(0))
        XCTAssertFalse(AppleMusicSource.isTrackLoaded(42))
    }

    // MARK: - Paused state distinct from playing

    /// `kPSp` (paused) and `kPSP` (playing) MUST decode to different FourCharCode
    /// values. The paused affordance in Discord/widget/UI keys off the
    /// difference. Regression guard for callers that try to collapse them.
    func testPausedAndPlayingDecodeDistinctValues() {
        let playing = AppleMusicSource.extractPlayerState("kPSP")
        let paused = AppleMusicSource.extractPlayerState("kPSp")
        XCTAssertNotNil(playing)
        XCTAssertNotNil(paused)
        XCTAssertNotEqual(playing, paused)
        XCTAssertEqual(paused, Self.kPSp)
    }

    /// Protocol compile-time guard: any conforming delegate must accept
    /// `isPaused`. If a future refactor accidentally drops the param, this
    /// stub won't compile.
    func testPlaybackSourceDelegateProtocolIncludesIsPaused() {
        final class CaptureDelegate: PlaybackSourceDelegate {
            var lastIsPaused: Bool?
            func playbackSource(
                didUpdateTrack track: String,
                artist: String,
                album: String,
                playlist: String,
                duration: TimeInterval,
                elapsed: TimeInterval,
                isPaused: Bool
            ) {
                lastIsPaused = isPaused
            }
            func playbackSource(didUpdateStatus status: String) {}
        }
        let cap = CaptureDelegate()
        cap.playbackSource(
            didUpdateTrack: "T", artist: "A", album: "Al",
            playlist: "P", duration: 100, elapsed: 10, isPaused: true
        )
        XCTAssertEqual(cap.lastIsPaused, true)
    }

    // MARK: - Stopped-notification short-circuit (no Apple event = no relaunch)

    /// Music posts a "Stopped" `playerInfo` payload on an explicit stop and as
    /// its final gasp while quitting. Recognising it lets us resolve state from
    /// the payload instead of round-tripping an Apple event, which is what
    /// relaunched Music.app after the user closed it.
    func testIsStoppedNotificationTrueForStoppedState() {
        XCTAssertTrue(AppleMusicSource.isStoppedNotification(["Player State": "Stopped"]))
    }

    func testIsStoppedNotificationFalseForPlaying() {
        XCTAssertFalse(AppleMusicSource.isStoppedNotification(["Player State": "Playing"]))
    }

    /// Paused must round-trip so the loaded track keeps showing while paused.
    func testIsStoppedNotificationFalseForPaused() {
        XCTAssertFalse(AppleMusicSource.isStoppedNotification(["Player State": "Paused"]))
    }

    func testIsStoppedNotificationFalseForNilUserInfo() {
        XCTAssertFalse(AppleMusicSource.isStoppedNotification(nil))
    }

    func testIsStoppedNotificationFalseWhenStateKeyMissing() {
        XCTAssertFalse(AppleMusicSource.isStoppedNotification(["Name": "Some Song"]))
    }
}

private actor SuspendedAppleMusicProbe {
    private(set) var callCount = 0
    private var firstContinuation: CheckedContinuation<String, Never>?

    func next() async -> String {
        callCount += 1
        guard callCount == 1 else { return "NOT_RUNNING" }
        return await withCheckedContinuation { continuation in
            firstContinuation = continuation
        }
    }

    func releaseFirst(with value: String) {
        firstContinuation?.resume(returning: value)
        firstContinuation = nil
    }
}

@MainActor
private final class AppleMusicSourceCaptureDelegate: PlaybackSourceDelegate {
    private(set) var statuses: [String] = []

    // Protocol conformance intentionally mirrors all playback fields.
    // swiftlint:disable:next function_parameter_count
    func playbackSource(
        didUpdateTrack track: String,
        artist: String,
        album: String,
        playlist: String,
        duration: TimeInterval,
        elapsed: TimeInterval,
        isPaused: Bool
    ) {}

    func playbackSource(didUpdateStatus status: String) {
        statuses.append(status)
    }
}
