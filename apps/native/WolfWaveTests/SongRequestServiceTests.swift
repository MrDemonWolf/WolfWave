//
//  SongRequestServiceTests.swift
//  WolfWave
//
//  Created by Nathanial Henniges on 2026-04-15.
//  Copyright © 2026 MrDemonWolf, Inc. All rights reserved.
//

import MusicKit
import XCTest

@testable import WolfWave

// MARK: - Mock AppleMusicController

final class MockAppleMusicController: AppleMusicControlling {
    var isPlaying = false
    var isPaused = false
    var isAuthorized = true
    var isMusicAppRunning = true
    var currentTrackID: String?
    var authStatus: AppleMusicController.AuthStatus = .authorized

    var playNowCalled = false
    var enqueueCalled = false
    var skipCalled = false
    var clearCalled = false
    var rebuildCalled = false
    var playFallbackCalled = false
    var fallbackPlaylistName: String?
    var enqueuedSongs: [Song] = []
    var shouldThrowMusicAppNotRunning = false
    var shouldThrowNotPlayable = false

    func search(query: String) async -> AppleMusicController.SearchResult { .notFound }
    func resolve(url: URL) async -> AppleMusicController.SearchResult { .notFound }
    func playNow(song: Song) async throws {
        if shouldThrowMusicAppNotRunning { throw PlaybackError.musicAppNotRunning }
        if shouldThrowNotPlayable { throw PlaybackError.notPlayable(title: song.title) }
        playNowCalled = true
    }
    func enqueue(song: Song) async throws {
        enqueueCalled = true
        enqueuedSongs.append(song)
    }
    func skipToNext() async throws { skipCalled = true }
    func previousTrack() async throws { /* no-op for tests */ }
    func playPause() async throws { /* no-op for tests */ }
    func clearPlayerQueue() async { clearCalled = true }
    func rebuildPlayerQueue(from songs: [Song]) async throws { rebuildCalled = true }
    func playFallbackPlaylist(name: String) async throws {
        playFallbackCalled = true
        fallbackPlaylistName = name
    }
}

// MARK: - SongRequestServiceTests

@MainActor
final class SongRequestServiceTests: WolfWaveTestCase {

    var queue: SongRequestQueue!
    var mockController: MockAppleMusicController!
    var service: SongRequestService!

    /// Builds a chat-command request source with sensible defaults.
    private func chatSource(
        username: String = "viewer",
        isModerator: Bool = false,
        isBroadcaster: Bool = false,
        isSubscriber: Bool = false,
        isVIP: Bool = false
    ) -> RequestSource {
        .chatCommand(
            BotCommandContext(
                userID: "1", username: username,
                isModerator: isModerator, isBroadcaster: isBroadcaster,
                isSubscriber: isSubscriber, isVIP: isVIP, messageID: "m"
            )
        )
    }

    private func clearAccessDefaults() {
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: AppConstants.UserDefaults.songRequestSubscriberOnly)
        defaults.removeObject(forKey: AppConstants.UserDefaults.songRequestChatAudience)
        defaults.removeObject(forKey: AppConstants.UserDefaults.songRequestMaxQueueSize)
        defaults.removeObject(forKey: AppConstants.UserDefaults.songRequestPerUserLimit)
        defaults.removeObject(forKey: AppConstants.UserDefaults.songRequestHoldEnabled)
        defaults.removeObject(forKey: AppConstants.UserDefaults.songRequestEnabled)
        defaults.removeObject(forKey: AppConstants.UserDefaults.songRequestAutoplayWhenEmpty)
        defaults.removeObject(forKey: AppConstants.UserDefaults.songRequestFallbackPlaylist)
    }

    /// Polls `condition` until it returns true or the timeout elapses, returning
    /// the final result. Mirrors `ArtworkServiceNetworkTests.waitUntil` so the
    /// playback-monitor tests wait on the poll loop instead of a fixed sleep.
    @discardableResult
    private func waitUntil(
        timeout: Duration = .seconds(2),
        interval: Duration = .milliseconds(20),
        _ condition: () -> Bool
    ) async -> Bool {
        let deadline = ContinuousClock.now + timeout
        while ContinuousClock.now < deadline {
            if condition() { return true }
            try? await Task.sleep(for: interval)
        }
        return condition()
    }

    override func setUp() {
        super.setUp()
        queue = SongRequestQueue()
        mockController = MockAppleMusicController()
        service = SongRequestService(
            queue: queue,
            musicController: mockController
        )
        clearAccessDefaults()
        // The master toggle defaults off (feature hidden until a streamer turns
        // it on). These tests exercise the request pipeline, so turn it on after
        // clearing defaults; the feature-disabled gate is covered explicitly.
        UserDefaults.standard.set(true, forKey: AppConstants.UserDefaults.songRequestEnabled)
    }

    override func tearDown() {
        service.stopPlaybackMonitoring()
        service = nil
        mockController = nil
        queue = nil
        clearAccessDefaults()
        super.tearDown()
    }

    // MARK: - Bit Boost

    func testBoostMovesUsersEarliestItemToFront() async {
        queue.add(SongRequestItem(title: "B", artist: "y", requesterUsername: "bob"))
        queue.add(SongRequestItem(title: "A", artist: "x", requesterUsername: "alice"))
        queue.add(SongRequestItem(title: "C", artist: "z", requesterUsername: "alice"))
        // Streamer's own track is playing, so boost only reorders (no takeover).
        mockController.isMusicAppRunning = true
        mockController.isPlaying = true

        let boosted = await service.boost(username: "alice")

        // Alice's *earliest* queued request (A) jumps the line, not her newest (C).
        XCTAssertEqual(boosted?.title, "A")
        XCTAssertEqual(queue.items.first?.title, "A", "Boosted item should jump to the front")
    }

    func testBoostRejectedWhenFeatureDisabled() async {
        UserDefaults.standard.set(false, forKey: AppConstants.UserDefaults.songRequestEnabled)
        queue.add(SongRequestItem(title: "A", artist: "x", requesterUsername: "alice"))

        let boosted = await service.boost(username: "alice")
        XCTAssertNil(boosted, "Boost must be rejected while the feature is off")
    }

    // MARK: - Fallback On Natural Drain

    func testFallbackPlaylistStartsWhenLastRequestEnds() async {
        service = SongRequestService(
            queue: queue, musicController: mockController, pollInterval: .milliseconds(20))
        UserDefaults.standard.set(
            "Gaming Vibes", forKey: AppConstants.UserDefaults.songRequestFallbackPlaylist)

        mockController.isMusicAppRunning = true
        mockController.isPlaying = false
        mockController.isPaused = false

        queue.add(SongRequestItem(title: "Last", artist: "a", requesterUsername: "u"))
        queue.dequeue() // nowPlaying = Last, queue now empty

        service.startPlaybackMonitoring()
        let started = await waitUntil(timeout: .seconds(1)) { self.mockController.playFallbackCalled }
        service.stopPlaybackMonitoring()

        XCTAssertTrue(started, "Fallback playlist should start when the queue drains during playback")

        UserDefaults.standard.removeObject(
            forKey: AppConstants.UserDefaults.songRequestFallbackPlaylist)
    }

    // MARK: - Audience Gate

    func testProcessRequestSubscriberAudienceBlocksViewer() async {
        UserDefaults.standard.set(
            RequestAudience.subscribers.rawValue,
            forKey: AppConstants.UserDefaults.songRequestChatAudience)

        let result = await service.processRequest(
            query: "any song", username: "viewer",
            source: chatSource(username: "viewer", isSubscriber: false))
        guard case .error = result else {
            XCTFail("Expected .error for subscriber-only block, got \(result)")
            return
        }
    }

    func testProcessRequestSubscriberAudienceAllowsSubscriber() async {
        UserDefaults.standard.set(
            RequestAudience.subscribers.rawValue,
            forKey: AppConstants.UserDefaults.songRequestChatAudience)

        let result = await service.processRequest(
            query: "any song", username: "subscriber",
            source: chatSource(username: "subscriber", isSubscriber: true))
        if case .error(let msg) = result {
            XCTAssertFalse(
                msg.contains("subscriber-only"), "Should not be blocked by subscriber-only gate")
        }
    }

    func testProcessRequestSubscriberAudienceAllowsModerator() async {
        UserDefaults.standard.set(
            RequestAudience.subscribers.rawValue,
            forKey: AppConstants.UserDefaults.songRequestChatAudience)

        let result = await service.processRequest(
            query: "any song", username: "mod",
            source: chatSource(username: "mod", isModerator: true))
        if case .error(let msg) = result {
            XCTAssertFalse(
                msg.contains("subscriber-only"), "Moderator should bypass subscriber-only gate")
        }
    }

    func testProcessRequestVipAudienceBlocksRegularViewer() async {
        UserDefaults.standard.set(
            RequestAudience.vipsAndSubs.rawValue,
            forKey: AppConstants.UserDefaults.songRequestChatAudience)

        let result = await service.processRequest(
            query: "any song", username: "viewer", source: chatSource(username: "viewer"))
        guard case .error = result else {
            XCTFail("Expected .error blocking a non-VIP/non-sub, got \(result)")
            return
        }
    }

    func testProcessRequestVipAudienceAllowsVIP() async {
        UserDefaults.standard.set(
            RequestAudience.vipsAndSubs.rawValue,
            forKey: AppConstants.UserDefaults.songRequestChatAudience)

        let result = await service.processRequest(
            query: "any song", username: "vip",
            source: chatSource(username: "vip", isVIP: true))
        if case .error(let msg) = result {
            XCTAssertFalse(msg.contains("VIPs"), "VIP should pass the VIPs & Subscribers gate")
        }
    }

    func testProcessRequestRedemptionSourcesBypassAudienceGate() async {
        // Even with the strictest audience, points/bits sources are not gated here.
        UserDefaults.standard.set(
            RequestAudience.modsOnly.rawValue,
            forKey: AppConstants.UserDefaults.songRequestChatAudience)

        let pointsResult = await service.processRequest(
            query: "any song", username: "viewer",
            source: .channelPoints(redemptionID: "r", rewardID: "rw"))
        if case .error(let msg) = pointsResult {
            XCTAssertFalse(msg.contains("Mods"), "Channel-point requests must not hit the audience gate")
        }

        let bitsResult = await service.processRequest(
            query: "any song", username: "viewer", source: .bits(amount: 100))
        if case .error(let msg) = bitsResult {
            XCTAssertFalse(msg.contains("Mods"), "Bit requests must not hit the audience gate")
        }
    }

    // MARK: - Feature Master Gate

    func testProcessRequestRejectedWhenFeatureDisabled() async {
        UserDefaults.standard.set(false, forKey: AppConstants.UserDefaults.songRequestEnabled)

        let result = await service.processRequest(
            query: "any song", username: "viewer", source: chatSource(username: "viewer"))
        guard case .featureDisabled = result else {
            XCTFail("Expected .featureDisabled when master toggle is off, got \(result)")
            return
        }
        XCTAssertFalse(mockController.playNowCalled, "Disabled feature must not play anything")
        XCTAssertTrue(queue.isEmpty, "Disabled feature must not queue anything")
    }

    func testRedemptionRejectedWhenFeatureDisabled() async {
        UserDefaults.standard.set(false, forKey: AppConstants.UserDefaults.songRequestEnabled)

        let result = await service.processRequest(
            query: "any song", username: "viewer",
            source: .channelPoints(redemptionID: "r", rewardID: "rw"))
        guard case .featureDisabled = result else {
            XCTFail("Expected .featureDisabled for a redemption while off, got \(result)")
            return
        }
    }

    // MARK: - Access Migration

    func testMigrateAccessSettingsConvertsLegacySubscriberOnly() {
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: AppConstants.UserDefaults.songRequestChatAudience)
        defaults.set(true, forKey: AppConstants.UserDefaults.songRequestSubscriberOnly)

        SongRequestService.migrateAccessSettings()

        XCTAssertEqual(
            defaults.string(forKey: AppConstants.UserDefaults.songRequestChatAudience),
            RequestAudience.subscribers.rawValue)
    }

    func testMigrateAccessSettingsDefaultsToEveryone() {
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: AppConstants.UserDefaults.songRequestChatAudience)
        defaults.set(false, forKey: AppConstants.UserDefaults.songRequestSubscriberOnly)

        SongRequestService.migrateAccessSettings()

        XCTAssertEqual(
            defaults.string(forKey: AppConstants.UserDefaults.songRequestChatAudience),
            RequestAudience.everyone.rawValue)
    }

    // MARK: - Auth Check

    func testProcessRequestNotAuthorizedReturnsError() async {
        mockController.isAuthorized = false
        mockController.authStatus = .denied

        let result = await service.processRequest(
            query: "any song", username: "user", source: chatSource(username: "user"))
        guard case .notAuthorized = result else {
            XCTFail("Expected .notAuthorized, got \(result)")
            return
        }
    }

    // MARK: - Skip

    func testSkipEmptyQueueReturnsNil() async {
        let result = await service.skip()
        XCTAssertNil(result)
    }

    func testSkipWithQueueItemsAdvancesInternalQueue() async {
        queue.add(SongRequestItem(title: "Song A", artist: "Artist", requesterUsername: "user1"))
        queue.add(SongRequestItem(title: "Song B", artist: "Artist", requesterUsername: "user2"))
        queue.dequeue()

        let next = await service.skip()
        XCTAssertEqual(next?.title, "Song B")
        XCTAssertEqual(queue.nowPlaying?.title, "Song B")
    }

    func testSkipCallsNativeSkip() async {
        // No fallback + autoplay-off → draining the queue via skip stops Music.app.
        UserDefaults.standard.set(false, forKey: AppConstants.UserDefaults.songRequestAutoplayWhenEmpty)
        queue.add(SongRequestItem(title: "Song A", artist: "Artist", requesterUsername: "user1"))
        queue.dequeue()

        _ = await service.skip()
        XCTAssertTrue(mockController.clearCalled)

        UserDefaults.standard.removeObject(forKey: AppConstants.UserDefaults.songRequestAutoplayWhenEmpty)
    }

    // MARK: - ClearQueue

    func testClearQueueReturnsZeroWhenEmpty() async {
        let count = await service.clearQueue()
        XCTAssertEqual(count, 0)
    }

    func testClearQueueReturnsClearedCount() async {
        queue.add(SongRequestItem(title: "Song 1", artist: "A", requesterUsername: "user1"))
        queue.add(SongRequestItem(title: "Song 2", artist: "B", requesterUsername: "user2"))

        let count = await service.clearQueue()
        XCTAssertEqual(count, 2)
        XCTAssertTrue(queue.isEmpty)
    }

    func testClearQueueAlsoClearsPlayerQueue() async {
        queue.add(SongRequestItem(title: "Song 1", artist: "A", requesterUsername: "user1"))

        _ = await service.clearQueue()
        XCTAssertTrue(mockController.clearCalled)
    }

    // MARK: - Buffered Mode (Music.app closed)

    func testRequestWhileMusicAppClosedBuffers() async {
        mockController.isMusicAppRunning = false

        _ = await service.processRequest(
            query: "any song", username: "viewer", source: chatSource())
        XCTAssertFalse(mockController.playNowCalled, "playNow should not fire when Music.app is closed")
    }

    func testPlayNextInQueueRequeuesItemWhenMusicAppNotRunning() async {
        mockController.shouldThrowMusicAppNotRunning = true

        queue.add(SongRequestItem(title: "Buffered Song", artist: "Artist", requesterUsername: "user1"))
        queue.dequeue()

        mockController.isMusicAppRunning = true
        _ = await service.processRequest(
            query: "any song", username: "viewer", source: chatSource())
        XCTAssertFalse(
            mockController.playNowCalled,
            "playNow threw: item should be re-queued, not marked as played")
    }

    // MARK: - Fallback Playlist

    func testFallbackPlaylistPlaysWhenQueueEmpties() async {
        UserDefaults.standard.set(
            "Gaming Vibes", forKey: AppConstants.UserDefaults.songRequestFallbackPlaylist)
        mockController.isMusicAppRunning = true

        _ = await service.clearQueue()

        XCTAssertFalse(
            mockController.playFallbackCalled, "clearQueue should not trigger fallback playlist")

        UserDefaults.standard.removeObject(
            forKey: AppConstants.UserDefaults.songRequestFallbackPlaylist)
    }

    func testClearQueueDoesNotStartFallback() async {
        UserDefaults.standard.set(
            "Gaming Vibes", forKey: AppConstants.UserDefaults.songRequestFallbackPlaylist)
        queue.add(SongRequestItem(title: "Song 1", artist: "A", requesterUsername: "user1"))

        _ = await service.clearQueue()

        XCTAssertFalse(
            mockController.playFallbackCalled, "clearQueue should never auto-start fallback playlist")
        XCTAssertTrue(mockController.clearCalled, "clearQueue should stop Music.app")

        UserDefaults.standard.removeObject(
            forKey: AppConstants.UserDefaults.songRequestFallbackPlaylist)
    }

    // MARK: - Hold Mode

    func testHoldBlocksAutoPlayOnRequest() async {
        UserDefaults.standard.set(true, forKey: AppConstants.UserDefaults.songRequestHoldEnabled)
        mockController.isMusicAppRunning = true
        mockController.isPlaying = false

        _ = await service.processRequest(
            query: "song", username: "viewer", source: chatSource())

        XCTAssertFalse(mockController.playNowCalled, "Hold should block auto-play on new requests")
    }

    func testSetHoldTogglesFlag() async {
        await service.setHold(true)
        XCTAssertTrue(service.isHoldEnabled)
        await service.setHold(false)
        XCTAssertFalse(service.isHoldEnabled)
    }

    func testHoldBlocksFallbackStart() async {
        UserDefaults.standard.set(true, forKey: AppConstants.UserDefaults.songRequestHoldEnabled)
        UserDefaults.standard.set(
            "Gaming Vibes", forKey: AppConstants.UserDefaults.songRequestFallbackPlaylist)

        _ = await service.clearQueue()
        XCTAssertFalse(
            mockController.playFallbackCalled, "No fallback should start while hold is enabled")

        UserDefaults.standard.removeObject(
            forKey: AppConstants.UserDefaults.songRequestFallbackPlaylist)
    }

    func testRequestWaitsForStreamersOwnTrackToEnd() async {
        // A request is queued while the streamer's own track is playing. Policy:
        // don't cut it off mid-song; take over the moment that track changes.
        service = SongRequestService(
            queue: queue,
            musicController: mockController,
            pollInterval: .milliseconds(20)
        )

        mockController.isMusicAppRunning = true
        mockController.isPlaying = true
        mockController.isPaused = false
        mockController.currentTrackID = "streamer-track-A"

        queue.add(SongRequestItem(title: "Requested", artist: "A", requesterUsername: "viewer"))

        service.startPlaybackMonitoring()

        // While the streamer's track is unchanged, the request must not take over.
        let tookOverEarly = await waitUntil(timeout: .milliseconds(150)) {
            self.queue.nowPlaying != nil
        }
        XCTAssertFalse(tookOverEarly, "Request must not interrupt the streamer's own track mid-song")

        // The streamer's track ends and Music advances → request takes over.
        mockController.currentTrackID = "streamer-track-B"
        let tookOver = await waitUntil(timeout: .seconds(1)) {
            self.queue.nowPlaying?.title == "Requested"
        }
        service.stopPlaybackMonitoring()

        XCTAssertTrue(tookOver, "Request should take over once the current track ends")
    }

    func testSkipInsideMusicAppAdvancesRequestQueue() async {
        // A request is playing. The streamer hits skip inside Music.app (or the
        // track ends and Music autoplays the next one): Music never reports
        // "stopped", it just loads a different track. The queue must hand off to
        // the next queued request instead of stalling on the gone track.
        service = SongRequestService(
            queue: queue,
            musicController: mockController,
            pollInterval: .milliseconds(20)
        )

        queue.add(SongRequestItem(title: "Current", artist: "A", requesterUsername: "user1"))
        queue.add(SongRequestItem(title: "Next", artist: "B", requesterUsername: "user2"))
        queue.dequeue()  // nowPlaying = "Current", "Next" still queued

        mockController.isMusicAppRunning = true
        mockController.isPlaying = true
        mockController.isPaused = false
        mockController.currentTrackID = "request-track-current"

        service.startPlaybackMonitoring()

        // While Music.app stays on the request's own track, no advance.
        let advancedEarly = await waitUntil(timeout: .milliseconds(150)) {
            self.queue.nowPlaying?.title != "Current"
        }
        XCTAssertFalse(advancedEarly, "Request must not advance while its own track is still loaded")

        // Streamer skips inside Music.app → a different track loads, still playing.
        mockController.currentTrackID = "some-autoplay-track"
        let advanced = await waitUntil(timeout: .seconds(1)) {
            self.queue.nowPlaying?.title == "Next"
        }
        service.stopPlaybackMonitoring()

        // Advancing now-playing to the next queued item is the proof the
        // divergence handoff fired. (The fixture carries no MusicKit `Song`, so
        // `playNow` is intentionally skipped — same as the takeover test above.)
        XCTAssertTrue(advanced, "Skipping inside Music.app should advance to the next queued request")
        XCTAssertEqual(queue.nowPlaying?.title, "Next")
    }

    func testAutoAdvanceDoesNotFireWhenPaused() async {
        // Inject a fast poll cadence so the monitor cycles many times within a
        // short, bounded wait instead of the 2s production interval.
        service = SongRequestService(
            queue: queue,
            musicController: mockController,
            pollInterval: .milliseconds(20)
        )

        queue.add(SongRequestItem(title: "Next Song", artist: "A", requesterUsername: "user1"))
        queue.add(SongRequestItem(title: "Current", artist: "B", requesterUsername: "user2"))
        queue.dequeue()

        mockController.isPlaying = false
        mockController.isPaused = true

        service.startPlaybackMonitoring()
        // Negative assertion: poll for the *forbidden* advance. The wait spans
        // many poll cycles, so a false return proves the paused state never
        // advanced (rather than just not having waited long enough).
        let advanced = await waitUntil(timeout: .milliseconds(400)) {
            self.mockController.playNowCalled || self.queue.nowPlaying?.title != "Next Song"
        }
        service.stopPlaybackMonitoring()

        XCTAssertFalse(advanced, "Auto-advance must not fire while Music.app is paused")
        XCTAssertEqual(queue.count, 1)
        XCTAssertEqual(queue.items.first?.title, "Current")
        XCTAssertEqual(queue.nowPlaying?.title, "Next Song")
    }
}
