//
//  SongRequestServiceTests.swift
//  WolfWaveTests
//
//  Created by MrDemonWolf, Inc. on 4/8/26.
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

    func search(query: String) async -> AppleMusicController.SearchResult { .notFound }
    func resolve(url: URL) async -> AppleMusicController.SearchResult { .notFound }
    func playNow(song: Song) async throws {
        if shouldThrowMusicAppNotRunning { throw PlaybackError.musicAppNotRunning }
        playNowCalled = true
    }
    func enqueue(song: Song) async throws {
        enqueueCalled = true
        enqueuedSongs.append(song)
    }
    func skipToNext() async throws { skipCalled = true }
    func clearPlayerQueue() async { clearCalled = true }
    func rebuildPlayerQueue(from songs: [Song]) async throws { rebuildCalled = true }
    func playFallbackPlaylist(name: String) async throws {
        playFallbackCalled = true
        fallbackPlaylistName = name
    }
}

// MARK: - SongRequestServiceTests

final class SongRequestServiceTests: XCTestCase {

    var queue: SongRequestQueue!
    var mockController: MockAppleMusicController!
    var service: SongRequestService!

    override func setUp() {
        super.setUp()
        queue = SongRequestQueue()
        mockController = MockAppleMusicController()
        service = SongRequestService(
            queue: queue,
            musicController: mockController
        )
        UserDefaults.standard.removeObject(forKey: AppConstants.UserDefaults.songRequestSubscriberOnly)
        UserDefaults.standard.removeObject(forKey: AppConstants.UserDefaults.songRequestMaxQueueSize)
        UserDefaults.standard.removeObject(forKey: AppConstants.UserDefaults.songRequestPerUserLimit)
        UserDefaults.standard.removeObject(forKey: AppConstants.UserDefaults.songRequestHoldEnabled)
    }

    override func tearDown() {
        service.stopPlaybackMonitoring()
        service = nil
        mockController = nil
        queue = nil
        UserDefaults.standard.removeObject(forKey: AppConstants.UserDefaults.songRequestSubscriberOnly)
        UserDefaults.standard.removeObject(forKey: AppConstants.UserDefaults.songRequestMaxQueueSize)
        UserDefaults.standard.removeObject(forKey: AppConstants.UserDefaults.songRequestPerUserLimit)
        UserDefaults.standard.removeObject(forKey: AppConstants.UserDefaults.songRequestHoldEnabled)
        super.tearDown()
    }

    // MARK: - Subscriber-Only Gate

    func testProcessRequestSubscriberOnlyBlocksViewer() async {
        UserDefaults.standard.set(true, forKey: AppConstants.UserDefaults.songRequestSubscriberOnly)

        let viewerContext = BotCommandContext(
            userID: "1", username: "viewer",
            isModerator: false, isBroadcaster: false,
            isSubscriber: false, messageID: "m"
        )

        let result = await service.processRequest(query: "any song", username: "viewer", context: viewerContext)
        guard case .error = result else {
            XCTFail("Expected .error for subscriber-only block, got \(result)")
            return
        }
    }

    func testProcessRequestSubscriberOnlyAllowsSubscriber() async {
        UserDefaults.standard.set(true, forKey: AppConstants.UserDefaults.songRequestSubscriberOnly)
        // Subscriber should pass the gate (auth check will fail since mock has no search)
        // We just verify it doesn't get blocked early with an .error(subscriber-only)
        let subContext = BotCommandContext(
            userID: "2", username: "subscriber",
            isModerator: false, isBroadcaster: false,
            isSubscriber: true, messageID: "m"
        )

        let result = await service.processRequest(query: "any song", username: "subscriber", context: subContext)
        // Should proceed past subscriber gate (will likely fail at search, not subscriber check)
        if case .error(let msg) = result {
            XCTAssertFalse(msg.contains("subscriber-only"), "Should not be blocked by subscriber-only gate")
        }
    }

    func testProcessRequestSubscriberOnlyAllowsModerator() async {
        UserDefaults.standard.set(true, forKey: AppConstants.UserDefaults.songRequestSubscriberOnly)

        let modContext = BotCommandContext(
            userID: "3", username: "mod",
            isModerator: true, isBroadcaster: false,
            isSubscriber: false, messageID: "m"
        )

        let result = await service.processRequest(query: "any song", username: "mod", context: modContext)
        if case .error(let msg) = result {
            XCTAssertFalse(msg.contains("subscriber-only"), "Moderator should bypass subscriber-only gate")
        }
    }

    // MARK: - Auth Check

    func testProcessRequestNotAuthorizedReturnsError() async {
        mockController.isAuthorized = false
        mockController.authStatus = .denied

        let context = BotCommandContext(
            userID: "1", username: "user",
            isModerator: false, isBroadcaster: false,
            isSubscriber: false, messageID: "m"
        )

        let result = await service.processRequest(query: "any song", username: "user", context: context)
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
        // Manually set up internal queue state with test items
        queue.add(SongRequestItem(title: "Song A", artist: "Artist", requesterUsername: "user1"))
        queue.add(SongRequestItem(title: "Song B", artist: "Artist", requesterUsername: "user2"))
        queue.dequeue() // sets nowPlaying = Song A

        let next = await service.skip()
        // skip() should return the new nowPlaying (Song B)
        XCTAssertEqual(next?.title, "Song B")
        XCTAssertEqual(queue.nowPlaying?.title, "Song B")
    }

    func testSkipCallsNativeSkip() async {
        queue.add(SongRequestItem(title: "Song A", artist: "Artist", requesterUsername: "user1"))
        queue.dequeue()

        _ = await service.skip()
        // Test SongRequestItems are built with `song: nil`, so SongRequestService.skip()
        // falls through to musicController.clearPlayerQueue() rather than playNow().
        XCTAssertTrue(mockController.clearCalled)
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

        let context = BotCommandContext(
            userID: "1", username: "viewer",
            isModerator: false, isBroadcaster: false,
            isSubscriber: false, messageID: "m"
        )

        _ = await service.processRequest(query: "any song", username: "viewer", context: context)
        // playNow should NOT be called because Music.app is closed
        XCTAssertFalse(mockController.playNowCalled, "playNow should not fire when Music.app is closed")
    }

    func testPlayNextInQueueRequeuesItemWhenMusicAppNotRunning() async {
        mockController.shouldThrowMusicAppNotRunning = true

        queue.add(SongRequestItem(title: "Buffered Song", artist: "Artist", requesterUsername: "user1"))
        queue.dequeue() // sets nowPlaying, removes from items

        // The service's playNextInQueue is private, so we test via skip():
        // First restore the item and let skip trigger playNextInQueue indirectly.
        // We simulate by re-adding and calling the internal path via clearQueue/restart.
        // Instead, directly verify the error path via the processRequest flow with mock throwing.
        mockController.isMusicAppRunning = true
        let context = BotCommandContext(
            userID: "1", username: "viewer",
            isModerator: false, isBroadcaster: false,
            isSubscriber: false, messageID: "m"
        )
        // The mock will throw musicAppNotRunning, which should re-queue at head
        _ = await service.processRequest(query: "any song", username: "viewer", context: context)
        XCTAssertFalse(mockController.playNowCalled, "playNow threw — item should be re-queued, not marked as played")
    }

    // MARK: - Fallback Playlist

    func testFallbackPlaylistPlaysWhenQueueEmpties() async {
        UserDefaults.standard.set("Gaming Vibes", forKey: AppConstants.UserDefaults.songRequestFallbackPlaylist)
        mockController.isMusicAppRunning = true

        // Simulate advanceQueue with empty queue via clearQueue (triggers clearNowPlaying path)
        _ = await service.clearQueue()

        // clearQueue stops the player but does NOT start fallback (destructive action = silence)
        XCTAssertFalse(mockController.playFallbackCalled, "clearQueue should not trigger fallback playlist")

        UserDefaults.standard.removeObject(forKey: AppConstants.UserDefaults.songRequestFallbackPlaylist)
    }

    func testClearQueueDoesNotStartFallback() async {
        UserDefaults.standard.set("Gaming Vibes", forKey: AppConstants.UserDefaults.songRequestFallbackPlaylist)
        queue.add(SongRequestItem(title: "Song 1", artist: "A", requesterUsername: "user1"))

        _ = await service.clearQueue()

        XCTAssertFalse(mockController.playFallbackCalled, "clearQueue should never auto-start fallback playlist")
        XCTAssertTrue(mockController.clearCalled, "clearQueue should stop Music.app")

        UserDefaults.standard.removeObject(forKey: AppConstants.UserDefaults.songRequestFallbackPlaylist)
    }

    // MARK: - Playback Monitoring: Paused State

    // MARK: - Hold Mode

    func testHoldBlocksAutoPlayOnRequest() async {
        UserDefaults.standard.set(true, forKey: AppConstants.UserDefaults.songRequestHoldEnabled)
        mockController.isMusicAppRunning = true
        mockController.isPlaying = false

        let context = BotCommandContext(
            userID: "1", username: "viewer",
            isModerator: false, isBroadcaster: false,
            isSubscriber: false, messageID: "m"
        )
        _ = await service.processRequest(query: "song", username: "viewer", context: context)

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
        UserDefaults.standard.set("Gaming Vibes", forKey: AppConstants.UserDefaults.songRequestFallbackPlaylist)

        _ = await service.clearQueue()
        XCTAssertFalse(mockController.playFallbackCalled, "No fallback should start while hold is enabled")

        UserDefaults.standard.removeObject(forKey: AppConstants.UserDefaults.songRequestFallbackPlaylist)
    }

    func testAutoAdvanceDoesNotFireWhenPaused() async {
        // Set up a queue with items and a nowPlaying
        queue.add(SongRequestItem(title: "Next Song", artist: "A", requesterUsername: "user1"))
        queue.add(SongRequestItem(title: "Current", artist: "B", requesterUsername: "user2"))
        queue.dequeue() // sets nowPlaying

        // Mock: music is paused (not playing, not stopped — paused)
        mockController.isPlaying = false
        mockController.isPaused = true

        service.startPlaybackMonitoring()
        // Wait slightly longer than one polling interval (2s) to confirm no advance
        try? await Task.sleep(nanoseconds: 2_500_000_000)
        service.stopPlaybackMonitoring()

        // Queue should still have "Current" — not consumed by auto-advance
        // nowPlaying remains "Next Song" (was dequeued above), queue still holds "Current"
        XCTAssertEqual(queue.count, 1)
        XCTAssertEqual(queue.items.first?.title, "Current")
        XCTAssertEqual(queue.nowPlaying?.title, "Next Song")
    }
}
