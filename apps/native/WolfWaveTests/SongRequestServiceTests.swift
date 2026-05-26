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
final class SongRequestServiceTests: XCTestCase {

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
    }

    override func tearDown() {
        service.stopPlaybackMonitoring()
        service = nil
        mockController = nil
        queue = nil
        clearAccessDefaults()
        super.tearDown()
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
        queue.add(SongRequestItem(title: "Song A", artist: "Artist", requesterUsername: "user1"))
        queue.dequeue()

        _ = await service.skip()
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
            "playNow threw — item should be re-queued, not marked as played")
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

    func testAutoAdvanceDoesNotFireWhenPaused() async {
        queue.add(SongRequestItem(title: "Next Song", artist: "A", requesterUsername: "user1"))
        queue.add(SongRequestItem(title: "Current", artist: "B", requesterUsername: "user2"))
        queue.dequeue()

        mockController.isPlaying = false
        mockController.isPaused = true

        service.startPlaybackMonitoring()
        try? await Task.sleep(nanoseconds: 2_500_000_000)
        service.stopPlaybackMonitoring()

        XCTAssertEqual(queue.count, 1)
        XCTAssertEqual(queue.items.first?.title, "Current")
        XCTAssertEqual(queue.nowPlaying?.title, "Next Song")
    }
}
