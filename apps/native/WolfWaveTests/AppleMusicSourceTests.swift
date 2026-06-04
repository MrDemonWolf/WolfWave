//
//  AppleMusicSourceTests.swift
//  WolfWave
//
//  Created by Nathanial Henniges on 2026-02-27.
//  Copyright © 2026 MrDemonWolf, Inc. All rights reserved.
//

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

    func testMonitorInitialization() {
        XCTAssertNotNil(monitor)
    }

    func testDelegateIsNilByDefault() {
        XCTAssertNil(monitor.delegate)
    }

    // MARK: - Start/Stop Tests

    func testStartTrackingDoesNotCrash() {
        monitor.startTracking()
        // If Music.app is not running, we should get a status update
    }

    func testStopTrackingDoesNotCrash() {
        monitor.startTracking()
        monitor.stopTracking()
    }

    func testDoubleStartDoesNotCrash() {
        monitor.startTracking()
        monitor.startTracking()
        monitor.stopTracking()
    }

    func testDoubleStopDoesNotCrash() {
        monitor.startTracking()
        monitor.stopTracking()
        monitor.stopTracking()
    }

    // MARK: - Update Interval Tests

    func testUpdateCheckIntervalBeforeStartDoesNotCrash() {
        monitor.updateCheckInterval(10.0)
    }

    func testUpdateCheckIntervalWhileTrackingDoesNotCrash() {
        monitor.startTracking()
        monitor.updateCheckInterval(10.0)
        monitor.stopTracking()
    }

    // MARK: - Force Refresh Tests

    func testForceRefreshBeforeStartIsNoOp() {
        // Should not crash; no delegate set, no tracking active.
        monitor.forceRefresh()
    }

    func testForceRefreshWhileTrackingDoesNotCrash() {
        monitor.startTracking()
        monitor.forceRefresh()
        monitor.stopTracking()
    }

    func testForceRefreshAfterStopIsNoOp() {
        monitor.startTracking()
        monitor.stopTracking()
        monitor.forceRefresh()
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
    /// the payload instead of round-tripping an Apple event — which is what
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
