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

    /// Optional override for `playbackSnapshot()`. When set, it is invoked for
    /// every snapshot read, so a test can script a flaky read sequence (e.g. a
    /// `nil` track key on some ticks). When `nil`, the snapshot is derived from
    /// `isPlaying` / `isPaused` / `currentTrackID` so existing tests keep working.
    var snapshotProvider: (() -> PlaybackSnapshot?)?
    var playbackSnapshotCallCount = 0

    var playNowCalled = false
    var playNowCallCount = 0
    var enqueueCalled = false
    var skipCalled = false
    var clearCalled = false
    var clearCallCount = 0
    var rebuildCalled = false
    var playFallbackCalled = false
    var fallbackPlaylistName: String?
    var enqueuedSongs: [Song] = []
    var shouldThrowMusicAppNotRunning = false
    var shouldThrowNotPlayable = false
    var searchProvider: ((String) async -> AppleMusicController.SearchResult)?
    /// When > 0, `playNow` throws `notPlayable` and decrements; once 0 it succeeds.
    var notPlayableThrowsRemaining = 0
    /// Optional suspension seam for deterministic native-clear races.
    var clearPlayerQueueHandler: (() async -> Void)?
    /// Optional same-event target mutation seam for vote-skip race tests.
    var targetedPlaybackHandler:
        ((TargetedPlaybackAction, String) async throws -> Bool)?

    func search(query: String) async -> AppleMusicController.SearchResult {
        if let searchProvider { return await searchProvider(query) }
        return .notFound
    }

    /// Makes `search` resolve, so `processRequest` gets past its `.notFound`
    /// branch and actually reaches the queue-add and auto-play gates.
    ///
    /// Without this every request short-circuits, and any test that asserts
    /// `playNowCalled == false` afterwards passes no matter what the gate under
    /// test does. Call it in any test whose subject is downstream of the search.
    ///
    /// Each distinct query resolves to a distinct song, so two different
    /// requests in one test do not collide on the queue's duplicate check.
    /// Pass `title` only when a test needs one fixed title.
    func stubSearchSuccess(title: String? = nil, artist: String = "Test Artist") {
        searchProvider = { query in
            .found(makeTestSong(
                id: testSongID(for: query),
                title: title ?? query,
                artist: artist
            ))
        }
    }
    func resolve(url: URL) async -> AppleMusicController.SearchResult { .notFound }
    func playbackSnapshot() async -> PlaybackSnapshot? {
        playbackSnapshotCallCount += 1
        if let snapshotProvider { return snapshotProvider() }
        let state: PlaybackSnapshot.State = isPlaying ? .playing : (isPaused ? .paused : .stopped)
        return PlaybackSnapshot(state: state, trackKey: currentTrackID)
    }
    func playNow(song: Song) async throws {
        playNowCallCount += 1
        if shouldThrowMusicAppNotRunning { throw PlaybackError.musicAppNotRunning }
        if notPlayableThrowsRemaining > 0 {
            notPlayableThrowsRemaining -= 1
            throw PlaybackError.notPlayable(title: song.title)
        }
        if shouldThrowNotPlayable { throw PlaybackError.notPlayable(title: song.title) }
        playNowCalled = true
    }
    func enqueue(song: Song) async throws {
        enqueueCalled = true
        enqueuedSongs.append(song)
    }
    func skipToNext() async throws { skipCalled = true }
    func performTargetedPlayback(
        _ action: TargetedPlaybackAction,
        ifCurrentTrackKeyEquals targetTrackKey: String
    ) async throws -> Bool {
        if let targetedPlaybackHandler {
            return try await targetedPlaybackHandler(action, targetTrackKey)
        }
        guard currentTrackID == targetTrackKey else { return false }
        switch action {
        case .nextTrack:
            skipCalled = true
        case .request:
            playNowCalled = true
            playNowCallCount += 1
        case .fallbackPlaylist(let name):
            playFallbackCalled = true
            fallbackPlaylistName = name
        case .stop:
            clearCalled = true
            clearCallCount += 1
        }
        return true
    }
    func previousTrack() async throws { /* no-op for tests */ }
    func playPause() async throws { /* no-op for tests */ }
    func clearPlayerQueue() async {
        clearCalled = true
        clearCallCount += 1
        await clearPlayerQueueHandler?()
    }
    func rebuildPlayerQueue(from songs: [Song]) async throws { rebuildCalled = true }
    func playFallbackPlaylist(name: String) async throws {
        playFallbackCalled = true
        fallbackPlaylistName = name
    }
}

/// Deterministically suspends an injected playback operation until a test has
/// performed the queue mutation it wants to race against the eventual result.
private actor PlaybackGate {
    private var hasStarted = false
    private var wasReleased = false
    private var startWaiters: [CheckedContinuation<Void, Never>] = []
    private var releaseWaiter: CheckedContinuation<Void, Never>?

    func suspend() async {
        hasStarted = true
        let waiters = startWaiters
        startWaiters.removeAll()
        waiters.forEach { $0.resume() }

        await withCheckedContinuation { continuation in
            if wasReleased {
                continuation.resume()
            } else {
                releaseWaiter = continuation
            }
        }
    }

    func waitUntilStarted() async {
        guard !hasStarted else { return }
        await withCheckedContinuation { continuation in
            startWaiters.append(continuation)
        }
    }

    func release() {
        wasReleased = true
        releaseWaiter?.resume()
        releaseWaiter = nil
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
        let defaults = DefaultsStore.store
        defaults.removeObject(forKey: AppConstants.UserDefaults.songRequestSubscriberOnly)
        defaults.removeObject(forKey: AppConstants.UserDefaults.songRequestChatAudience)
        defaults.removeObject(forKey: AppConstants.UserDefaults.songRequestMaxQueueSize)
        defaults.removeObject(forKey: AppConstants.UserDefaults.songRequestPerUserLimit)
        defaults.removeObject(forKey: AppConstants.UserDefaults.songRequestHoldEnabled)
        defaults.removeObject(forKey: AppConstants.UserDefaults.songRequestEnabled)
        defaults.removeObject(forKey: AppConstants.UserDefaults.songRequestAutoAdvance)
        defaults.removeObject(forKey: AppConstants.UserDefaults.songRequestAutoplayWhenEmpty)
        defaults.removeObject(forKey: AppConstants.UserDefaults.songRequestFallbackPlaylist)
    }

    private func makeServiceWithLiveRequest(
        pollInterval: Duration
    ) -> SongRequestService {
        _ = queue.add(makeTestRequestItem(
            title: "Later", artist: "Artist", requesterUsername: "viewer"))
        mockController.isPlaying = true
        mockController.currentTrackID = "streamer-track"
        return SongRequestService(
            queue: queue,
            musicController: mockController,
            pollInterval: pollInterval
        )
    }

    override func setUp() async throws {
        try await super.setUp()
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
        DefaultsStore.store.set(true, forKey: AppConstants.UserDefaults.songRequestEnabled)
    }

    override func tearDown() async throws {
        service.stopPlaybackMonitoring()
        service = nil
        mockController = nil
        queue = nil
        clearAccessDefaults()
        try await super.tearDown()
    }

    // MARK: - Bit Boost

    func testBoostMovesUsersEarliestItemToFront() async {
        _ = queue.add(makeTestRequestItem(title: "B", artist: "y", requesterUsername: "bob"))
        _ = queue.add(makeTestRequestItem(title: "A", artist: "x", requesterUsername: "alice"))
        _ = queue.add(makeTestRequestItem(title: "C", artist: "z", requesterUsername: "alice"))
        // Streamer's own track is playing, so boost only reorders (no takeover).
        mockController.isMusicAppRunning = true
        mockController.isPlaying = true

        let boosted = await service.boost(username: "alice")

        // Alice's *earliest* queued request (A) jumps the line, not her newest (C).
        XCTAssertEqual(boosted?.title, "A")
        XCTAssertEqual(queue.items.first?.title, "A", "Boosted item should jump to the front")
    }

    func testBoostRejectedWhenFeatureDisabled() async {
        DefaultsStore.store.set(false, forKey: AppConstants.UserDefaults.songRequestEnabled)
        _ = queue.add(makeTestRequestItem(title: "A", artist: "x", requesterUsername: "alice"))

        let boosted = await service.boost(username: "alice")
        XCTAssertNil(boosted, "Boost must be rejected while the feature is off")
    }

    // MARK: - Fallback On Natural Drain

    func testFallbackPlaylistStartsWhenLastRequestEnds() async {
        service = SongRequestService(
            queue: queue, musicController: mockController, pollInterval: .milliseconds(20))
        DefaultsStore.store.set(
            "Gaming Vibes", forKey: AppConstants.UserDefaults.songRequestFallbackPlaylist)

        mockController.isMusicAppRunning = true
        mockController.isPlaying = false
        mockController.isPaused = false

        _ = queue.add(makeTestRequestItem(title: "Last", artist: "a", requesterUsername: "u"))
        queue.dequeue() // nowPlaying = Last, queue now empty

        service.startPlaybackMonitoring()
        let started = await waitUntil(timeout: .seconds(1)) { self.mockController.playFallbackCalled }
        service.stopPlaybackMonitoring()

        XCTAssertTrue(started, "Fallback playlist should start when the queue drains during playback")

        DefaultsStore.store.removeObject(
            forKey: AppConstants.UserDefaults.songRequestFallbackPlaylist)
    }

    // MARK: - Audience Gate

    func testProcessRequestSubscriberAudienceBlocksViewer() async {
        DefaultsStore.store.set(
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
        DefaultsStore.store.set(
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
        DefaultsStore.store.set(
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
        DefaultsStore.store.set(
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
        DefaultsStore.store.set(
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
        //
        // This test used to prove nothing twice over. Its assertions sat inside
        // `if case .error`, which never matched because search resolved to
        // `.notFound` long before any audience decision; and the substring it
        // looked for ("Mods") does not appear in the real denial text
        // ("Only mods can request songs right now."). Moving the audience check
        // to cover every source would have rejected every channel-point and bit
        // request on a mods-only channel with this test still green.
        mockController.stubSearchSuccess()
        DefaultsStore.store.set(
            RequestAudience.modsOnly.rawValue,
            forKey: AppConstants.UserDefaults.songRequestChatAudience)

        // Distinct queries so the second request is not rejected as a duplicate
        // of the first, which would hide the audience answer behind a queue answer.
        let pointsResult = await service.processRequest(
            query: "points song", username: "viewer",
            source: .channelPoints(redemptionID: "r", rewardID: "rw"))
        guard case .added = pointsResult else {
            return XCTFail("channel-point request must bypass the audience gate, got \(pointsResult)")
        }

        let bitsResult = await service.processRequest(
            query: "bits song", username: "viewer", source: .bits(amount: 100))
        guard case .added = bitsResult else {
            return XCTFail("bit request must bypass the audience gate, got \(bitsResult)")
        }

        // The gate really is closed for chat on this channel, so the two passes
        // above are a bypass and not an audience setting that never applied.
        let chatResult = await service.processRequest(
            query: "chat song", username: "viewer", source: chatSource(username: "viewer"))
        if case .error = chatResult {
            // expected: a plain viewer is blocked on a mods-only channel
        } else {
            XCTFail("mods-only audience should block a plain chat viewer, got \(chatResult)")
        }
    }

    // MARK: - Feature Master Gate

    func testProcessRequestRejectedWhenFeatureDisabled() async {
        DefaultsStore.store.set(false, forKey: AppConstants.UserDefaults.songRequestEnabled)

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
        DefaultsStore.store.set(false, forKey: AppConstants.UserDefaults.songRequestEnabled)

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
        let defaults = DefaultsStore.store
        defaults.removeObject(forKey: AppConstants.UserDefaults.songRequestChatAudience)
        defaults.set(true, forKey: AppConstants.UserDefaults.songRequestSubscriberOnly)

        SongRequestService.migrateAccessSettings()

        XCTAssertEqual(
            defaults.string(forKey: AppConstants.UserDefaults.songRequestChatAudience),
            RequestAudience.subscribers.rawValue)
    }

    func testMigrateAccessSettingsDefaultsToEveryone() {
        let defaults = DefaultsStore.store
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
        _ = queue.add(makeTestRequestItem(title: "Song A", artist: "Artist", requesterUsername: "user1"))
        _ = queue.add(makeTestRequestItem(title: "Song B", artist: "Artist", requesterUsername: "user2"))
        queue.dequeue()

        let next = await service.skip()
        XCTAssertEqual(next?.title, "Song B")
        XCTAssertEqual(queue.nowPlaying?.title, "Song B")
    }

    func testSkipCallsNativeSkip() async {
        // No fallback + autoplay-off → draining the queue via skip stops Music.app.
        DefaultsStore.store.set(false, forKey: AppConstants.UserDefaults.songRequestAutoplayWhenEmpty)
        _ = queue.add(makeTestRequestItem(title: "Song A", artist: "Artist", requesterUsername: "user1"))
        queue.dequeue()

        _ = await service.skip()
        XCTAssertTrue(mockController.clearCalled)

        DefaultsStore.store.removeObject(forKey: AppConstants.UserDefaults.songRequestAutoplayWhenEmpty)
    }

    // MARK: - ClearQueue

    func testClearQueueReturnsZeroWhenEmpty() async {
        let count = await service.clearQueue()
        XCTAssertEqual(count, 0)
    }

    func testClearQueueReturnsClearedCount() async {
        _ = queue.add(makeTestRequestItem(title: "Song 1", artist: "A", requesterUsername: "user1"))
        _ = queue.add(makeTestRequestItem(title: "Song 2", artist: "B", requesterUsername: "user2"))

        let count = await service.clearQueue()
        XCTAssertEqual(count, 2)
        XCTAssertTrue(queue.isEmpty)
    }

    func testClearQueueAlsoClearsPlayerQueue() async {
        _ = queue.add(makeTestRequestItem(title: "Song 1", artist: "A", requesterUsername: "user1"))

        _ = await service.clearQueue()
        XCTAssertTrue(mockController.clearCalled)
    }

    func testRequestAddedDuringSuspendedClearStartsOnlyAfterClearCompletes() async {
        let clearGate = PlaybackGate()
        let startedIDs = ThreadSafeBox<[UUID]>([])
        mockController.clearPlayerQueueHandler = {
            await clearGate.suspend()
        }
        service = SongRequestService(
            queue: queue,
            musicController: mockController,
            playbackOverride: { item in
                startedIDs.mutate { $0.append(item.id) }
            }
        )
        let removed = makeTestRequestItem(
            title: "Removed", artist: "Artist", requesterUsername: "old")
        _ = queue.add(removed)

        let clearing = Task { await self.service.clearQueue() }
        await clearGate.waitUntilStarted()
        let fresh = makeTestRequestItem(
            title: "Fresh", artist: "Artist", requesterUsername: "new")
        _ = queue.add(fresh)

        let startWhileClearing = await service.playNextInQueue()

        XCTAssertNil(startWhileClearing)
        XCTAssertTrue(startedIDs.value.isEmpty)
        XCTAssertEqual(queue.items.map(\.id), [fresh.id])

        await clearGate.release()
        let clearedCount = await clearing.value
        XCTAssertEqual(clearedCount, 1)
        XCTAssertEqual(startedIDs.value, [fresh.id])
        XCTAssertEqual(queue.nowPlaying?.id, fresh.id)
        XCTAssertTrue(queue.isEmpty)
        XCTAssertEqual(mockController.clearCallCount, 1)
    }

    func testOverlappingClearsCoalesceAndOnlyNewestGenerationReconciles() async {
        let clearGate = PlaybackGate()
        let startedIDs = ThreadSafeBox<[UUID]>([])
        mockController.clearPlayerQueueHandler = {
            await clearGate.suspend()
        }
        service = SongRequestService(
            queue: queue,
            musicController: mockController,
            playbackOverride: { item in
                startedIDs.mutate { $0.append(item.id) }
            }
        )
        let firstRemoved = makeTestRequestItem(
            title: "First removed", artist: "Artist", requesterUsername: "old")
        _ = queue.add(firstRemoved)

        let firstClear = Task { await self.service.clearQueue() }
        await clearGate.waitUntilStarted()

        let secondRemoved = makeTestRequestItem(
            title: "Second removed", artist: "Artist", requesterUsername: "middle")
        _ = queue.add(secondRemoved)
        let secondClear = Task { await self.service.clearQueue() }
        let secondClearStarted = await waitUntil {
            self.queue.isEmpty
        }
        XCTAssertTrue(secondClearStarted)

        let latest = makeTestRequestItem(
            title: "Latest", artist: "Artist", requesterUsername: "new")
        _ = queue.add(latest)
        let startWhileClearing = await service.playNextInQueue()
        XCTAssertNil(startWhileClearing)
        XCTAssertTrue(startedIDs.value.isEmpty)

        await clearGate.release()
        let firstCount = await firstClear.value
        let secondCount = await secondClear.value

        XCTAssertEqual(firstCount, 1)
        XCTAssertEqual(secondCount, 1)
        XCTAssertEqual(mockController.clearCallCount, 1)
        XCTAssertEqual(startedIDs.value, [latest.id])
        XCTAssertEqual(queue.nowPlaying?.id, latest.id)
        XCTAssertTrue(queue.isEmpty)
    }
    func testPlaybackFailureLeavesReservedHeadAndCurrentItemUntouched() async {
        let current = makeTestRequestItem(
            title: "Current", artist: "Artist", requesterUsername: "first")
        let reserved = makeTestRequestItem(
            title: "Reserved", artist: "Artist", requesterUsername: "second")
        _ = queue.add(current)
        _ = queue.add(reserved)
        queue.dequeue()
        service = SongRequestService(
            queue: queue,
            musicController: mockController,
            playbackOverride: { _ in
                throw PlaybackError.commandFailed(command: "playNow", message: "timed out")
            }
        )

        let result = await service.playNextInQueue()

        XCTAssertNil(result)
        XCTAssertEqual(queue.nowPlaying?.id, current.id)
        XCTAssertEqual(queue.items.map(\.id), [reserved.id])
    }

    func testCancelledPlaybackRetainsQueueHead() async {
        let current = makeTestRequestItem(
            title: "Current", artist: "Artist", requesterUsername: "first")
        let reserved = makeTestRequestItem(
            title: "Reserved", artist: "Artist", requesterUsername: "second")
        _ = queue.add(current)
        _ = queue.add(reserved)
        queue.dequeue()
        service = SongRequestService(
            queue: queue,
            musicController: mockController,
            playbackOverride: { _ in throw CancellationError() }
        )

        let result = await service.playNextInQueue()

        XCTAssertNil(result)
        XCTAssertEqual(queue.nowPlaying?.id, current.id)
        XCTAssertEqual(queue.items.map(\.id), [reserved.id])
    }

    func testClearDuringSuspendedPlaybackCannotResurrectRequest() async {
        let gate = PlaybackGate()
        let reserved = makeTestRequestItem(
            title: "Reserved", artist: "Artist", requesterUsername: "viewer")
        _ = queue.add(reserved)
        service = SongRequestService(
            queue: queue,
            musicController: mockController,
            playbackOverride: { _ in await gate.suspend() }
        )

        let playback = Task { await service.playNextInQueue() }
        await gate.waitUntilStarted()
        let cleared = await service.clearQueue()
        await gate.release()
        let result = await playback.value

        XCTAssertEqual(cleared, 1)
        XCTAssertNil(result)
        XCTAssertTrue(queue.isEmpty)
        XCTAssertNil(queue.nowPlaying)
        XCTAssertEqual(
            mockController.clearCallCount, 2,
            "clearQueue stops once immediately and the stale successful start stops again")
    }

    func testReorderDuringSuspendedPlaybackRetriesNewHead() async {
        let gate = PlaybackGate()
        let first = makeTestRequestItem(
            title: "First", artist: "Artist", requesterUsername: "first")
        let second = makeTestRequestItem(
            title: "Second", artist: "Artist", requesterUsername: "second")
        _ = queue.add(first)
        _ = queue.add(second)
        service = SongRequestService(
            queue: queue,
            musicController: mockController,
            playbackOverride: { _ in await gate.suspend() }
        )

        let playback = Task { await service.playNextInQueue() }
        await gate.waitUntilStarted()
        queue.move(from: IndexSet(integer: 0), to: 2)
        await gate.release()
        let result = await playback.value

        XCTAssertEqual(result?.id, second.id)
        XCTAssertEqual(queue.nowPlaying?.id, second.id)
        XCTAssertEqual(queue.items.map(\.id), [first.id])
        XCTAssertEqual(mockController.clearCallCount, 1)
    }

    // MARK: - Buffered Mode (Music.app closed)

    func testRequestWhileMusicAppClosedBuffers() async {
        mockController.stubSearchSuccess()
        mockController.isMusicAppRunning = false

        let result = await service.processRequest(
            query: "any song", username: "viewer", source: chatSource())

        // Assert the request actually reached the gate. Without this the test
        // passes on a `.notFound` that never touched the Music-closed branch.
        guard case .added = result else {
            return XCTFail("request did not queue, so the Music-closed gate was never reached: \(result)")
        }
        XCTAssertEqual(queue.items.count, 1, "a request arriving with Music closed must stay buffered")
        XCTAssertFalse(mockController.playNowCalled, "playNow should not fire when Music.app is closed")
    }

    func testPlayNextInQueueRequeuesItemWhenMusicAppNotRunning() async {
        mockController.shouldThrowMusicAppNotRunning = true

        _ = queue.add(makeTestRequestItem(
            title: "Buffered Song", artist: "Artist", requesterUsername: "user1"))

        // Actually exercise playNextInQueue. The old version called
        // processRequest instead, which resolved to .notFound, so playNow was
        // never invoked and the requeue-on-throw path could be deleted whole
        // while the test stayed green.
        let started = await service.playNextInQueue()

        XCTAssertTrue(
            mockController.playNowCallCount > 0,
            "guard against vacuity: playNow must actually have been attempted")
        XCTAssertNil(started, "playNow threw musicAppNotRunning, so nothing should be playing")
        XCTAssertNil(queue.nowPlaying, "a throwing start must not leave the item marked as playing")
        XCTAssertEqual(
            queue.items.map(\.title), ["Buffered Song"],
            "the item must be re-queued for the launch flush, not dropped")
    }

    // MARK: - Fallback Playlist

    func testFallbackPlaylistPlaysWhenQueueEmpties() async {
        DefaultsStore.store.set(
            "Gaming Vibes", forKey: AppConstants.UserDefaults.songRequestFallbackPlaylist)
        mockController.isMusicAppRunning = true

        _ = await service.clearQueue()

        XCTAssertFalse(
            mockController.playFallbackCalled, "clearQueue should not trigger fallback playlist")

        DefaultsStore.store.removeObject(
            forKey: AppConstants.UserDefaults.songRequestFallbackPlaylist)
    }

    func testSkippingLastRequestStartsConfiguredFallback() async {
        DefaultsStore.store.set(
            "Gaming Vibes",
            forKey: AppConstants.UserDefaults.songRequestFallbackPlaylist)
        mockController.isMusicAppRunning = true
        let current = makeTestRequestItem(
            title: "Last request", artist: "Artist", requesterUsername: "viewer")
        _ = queue.add(current)
        queue.dequeue()

        let replacement = await service.skip()

        XCTAssertNil(replacement)
        XCTAssertNil(queue.nowPlaying)
        XCTAssertTrue(mockController.playFallbackCalled)
        XCTAssertEqual(mockController.fallbackPlaylistName, "Gaming Vibes")

        DefaultsStore.store.removeObject(
            forKey: AppConstants.UserDefaults.songRequestFallbackPlaylist)
    }

    func testClearQueueDoesNotStartFallback() async {
        DefaultsStore.store.set(
            "Gaming Vibes", forKey: AppConstants.UserDefaults.songRequestFallbackPlaylist)
        _ = queue.add(makeTestRequestItem(title: "Song 1", artist: "A", requesterUsername: "user1"))

        _ = await service.clearQueue()

        XCTAssertFalse(
            mockController.playFallbackCalled, "clearQueue should never auto-start fallback playlist")
        XCTAssertTrue(mockController.clearCalled, "clearQueue should stop Music.app")

        DefaultsStore.store.removeObject(
            forKey: AppConstants.UserDefaults.songRequestFallbackPlaylist)
    }

    // MARK: - Hold Mode

    func testHoldBlocksAutoPlayOnRequest() async {
        DefaultsStore.store.set(true, forKey: AppConstants.UserDefaults.songRequestHoldEnabled)
        mockController.stubSearchSuccess()
        mockController.isMusicAppRunning = true
        mockController.isPlaying = false

        let result = await service.processRequest(
            query: "song", username: "viewer", source: chatSource())

        // Every other condition in the auto-play gate is deliberately satisfied
        // above (Music running, nothing playing, request queued), so hold is the
        // only thing left that can stop playback. Without the `.added` check the
        // request resolved to `.notFound` and this asserted nothing at all.
        guard case .added = result else {
            return XCTFail("request did not queue, so the hold gate was never reached: \(result)")
        }
        XCTAssertFalse(mockController.playNowCalled, "Hold should block auto-play on new requests")
    }

    func testAutoPlayFiresWhenHoldIsOff() async {
        // The control for `testHoldBlocksAutoPlayOnRequest`. Identical setup with
        // hold off must reach playNow, which is what proves the assertion above
        // is about hold and not about some unrelated short-circuit.
        DefaultsStore.store.removeObject(forKey: AppConstants.UserDefaults.songRequestHoldEnabled)
        mockController.stubSearchSuccess()
        mockController.isMusicAppRunning = true
        mockController.isPlaying = false

        let result = await service.processRequest(
            query: "song", username: "viewer", source: chatSource())

        guard case .added = result else {
            return XCTFail("request did not queue: \(result)")
        }
        XCTAssertTrue(mockController.playNowCalled, "with hold off an idle Music should start the request")
    }

    func testSetHoldTogglesFlag() async {
        await service.setHold(true)
        XCTAssertTrue(service.isHoldEnabled)
        await service.setHold(false)
        XCTAssertFalse(service.isHoldEnabled)
    }

    func testHoldBlocksFallbackStart() async {
        DefaultsStore.store.set(true, forKey: AppConstants.UserDefaults.songRequestHoldEnabled)
        DefaultsStore.store.set(
            "Gaming Vibes", forKey: AppConstants.UserDefaults.songRequestFallbackPlaylist)

        _ = await service.clearQueue()
        XCTAssertFalse(
            mockController.playFallbackCalled, "No fallback should start while hold is enabled")

        DefaultsStore.store.removeObject(
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

        _ = queue.add(makeTestRequestItem(title: "Requested", artist: "A", requesterUsername: "viewer"))

        service.startPlaybackMonitoring()

        // While the streamer's track is unchanged, the request must not take over.
        let tookOverEarly = await waitUntil(timeout: .milliseconds(300)) {
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

    func testFlakyTrackReadDoesNotInterruptStreamerSong() async {
        // Regression for the "request cut my song off mid-play" bug. On macOS 26,
        // Apple Events to Music.app time out intermittently, so a mid-song read can
        // come back with no loaded-track identity even though the streamer's song
        // is still playing. The old takeover logic treated that empty/nil read as
        // "the song changed" and started the request immediately. It must not.
        service = SongRequestService(
            queue: queue,
            musicController: mockController,
            pollInterval: .milliseconds(20)
        )
        mockController.isMusicAppRunning = true

        // "streamer-A" plays the whole time, but every third read flakes: a nil
        // whole-snapshot (timed-out script) or a nil track key (track loaded,
        // metadata unread). Neither is a real track boundary.
        var reads = 0
        mockController.snapshotProvider = {
            reads += 1
            switch reads % 3 {
            case 0: return nil  // whole AppleScript read failed this tick
            case 1: return PlaybackSnapshot(state: .playing, trackKey: nil)  // key unread
            default: return PlaybackSnapshot(state: .playing, trackKey: "streamer-A")
            }
        }

        _ = queue.add(makeTestRequestItem(title: "Requested", artist: "A", requesterUsername: "viewer"))
        service.startPlaybackMonitoring()

        // Across many poll ticks of flaky reads, the request must never take over.
        let tookOver = await waitUntil(timeout: .milliseconds(400)) {
            self.queue.nowPlaying != nil || self.mockController.playNowCalled
        }
        service.stopPlaybackMonitoring()

        XCTAssertFalse(tookOver, "A flaky or empty track read must not be mistaken for a song change")
        XCTAssertNil(queue.nowPlaying, "The streamer's song must keep playing until it actually ends")
    }

    func testSingleTransientTrackChangeDoesNotTakeOver() async {
        // A genuine boundary is two confirming reads of a new track. A single stray
        // different-track read that immediately reverts to the streamer's track is
        // noise, not a boundary, and must not trigger a takeover.
        service = SongRequestService(
            queue: queue,
            musicController: mockController,
            pollInterval: .milliseconds(20)
        )
        mockController.isMusicAppRunning = true

        // Pattern A, A, B (one stray), A, A, A... never two B's in a row.
        var reads = 0
        mockController.snapshotProvider = {
            reads += 1
            let key = (reads == 3) ? "streamer-B" : "streamer-A"
            return PlaybackSnapshot(state: .playing, trackKey: key)
        }

        _ = queue.add(makeTestRequestItem(title: "Requested", artist: "A", requesterUsername: "viewer"))
        service.startPlaybackMonitoring()

        let tookOver = await waitUntil(timeout: .milliseconds(400)) {
            self.queue.nowPlaying != nil
        }
        service.stopPlaybackMonitoring()

        XCTAssertFalse(tookOver, "A single transient track-id blip must not trigger a takeover")
        XCTAssertFalse(mockController.playNowCalled, "No blip may reach the controller")
    }

    func testBoostDoesNotInterruptStreamersPlayingTrack() async {
        // Boost routes through the same idle-only fast path as a new request
        // (`startImmediatelyIfIdle`): it reorders the queue but must NOT cut off the
        // streamer's actively-playing track. A takeover, if any, happens later at
        // the boundary via the poll, never as an immediate interrupt on the add.
        service = SongRequestService(
            queue: queue,
            musicController: mockController,
            pollInterval: .seconds(10)  // isolate the boost fast path from the poll
        )
        mockController.isMusicAppRunning = true
        mockController.isPlaying = true
        mockController.currentTrackID = "streamer-A"
        _ = queue.add(makeTestRequestItem(title: "A", artist: "x", requesterUsername: "alice"))

        let boosted = await service.boost(username: "alice")

        XCTAssertEqual(boosted?.title, "A")
        XCTAssertFalse(mockController.playNowCalled, "Boost must not interrupt the streamer's playing track")
        XCTAssertNil(queue.nowPlaying, "Boosted request must wait, not take over immediately")
    }

    func testBoostStartsImmediatelyWhenPlayerIsIdle() async {
        // The flip side: when nothing is actively playing, the boost fast path does
        // start the request right away (no song to wait for).
        service = SongRequestService(
            queue: queue,
            musicController: mockController,
            pollInterval: .seconds(10)
        )
        mockController.isMusicAppRunning = true
        mockController.isPlaying = false  // idle / stopped
        mockController.isPaused = false
        _ = queue.add(makeTestRequestItem(title: "A", artist: "x", requesterUsername: "alice"))

        let boosted = await service.boost(username: "alice")

        XCTAssertEqual(boosted?.title, "A")
        // Idle → the request is pulled into the now-playing slot immediately.
        XCTAssertEqual(queue.nowPlaying?.title, "A", "Boost should start the request from an idle player")
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

        _ = queue.add(makeTestRequestItem(title: "Current", artist: "A", requesterUsername: "user1"))
        _ = queue.add(makeTestRequestItem(title: "Next", artist: "B", requesterUsername: "user2"))
        queue.dequeue()  // nowPlaying = "Current", "Next" still queued

        mockController.isMusicAppRunning = true
        mockController.isPlaying = true
        mockController.isPaused = false
        mockController.currentTrackID = "request-track-current"

        service.startPlaybackMonitoring()

        // While Music.app stays on the request's own track, no advance.
        let advancedEarly = await waitUntil(timeout: .milliseconds(300)) {
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
        // divergence handoff fired, and the item only commits after the
        // controller accepts its song.
        XCTAssertTrue(advanced, "Skipping inside Music.app should advance to the next queued request")
        XCTAssertEqual(queue.nowPlaying?.title, "Next")
        XCTAssertTrue(mockController.playNowCalled, "The handoff must actually start the next request")
    }

    func testAutoAdvanceDoesNotFireWhenPaused() async {
        // Inject a fast poll cadence so the monitor cycles many times within a
        // short, bounded wait instead of the 2s production interval.
        service = SongRequestService(
            queue: queue,
            musicController: mockController,
            pollInterval: .milliseconds(20)
        )

        _ = queue.add(makeTestRequestItem(title: "Next Song", artist: "A", requesterUsername: "user1"))
        _ = queue.add(makeTestRequestItem(title: "Current", artist: "B", requesterUsername: "user2"))
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

    func testPlaybackMonitorSleepsCompletelyWhileQueueIsIdle() async {
        service = SongRequestService(
            queue: queue,
            musicController: mockController,
            pollInterval: .milliseconds(20)
        )
        mockController.isPlaying = true
        mockController.currentTrackID = "streamer-track"

        service.startPlaybackMonitoring()
        try? await Task.sleep(for: .milliseconds(120))
        XCTAssertEqual(
            mockController.playbackSnapshotCallCount,
            0,
            "An empty queue should not own a periodic playback task")

        _ = queue.add(makeTestRequestItem(
            title: "Later", artist: "Artist", requesterUsername: "viewer"))
        let beganPolling = await waitUntil(timeout: .seconds(1)) {
            self.mockController.playbackSnapshotCallCount > 0
        }
        service.stopPlaybackMonitoring()

        XCTAssertTrue(beganPolling, "A queue-change notification should activate polling")
    }

    func testUnrelatedQueueChangeDoesNotActivatePlaybackPolling() async {
        service = SongRequestService(
            queue: queue,
            musicController: mockController,
            pollInterval: .milliseconds(20)
        )
        service.startPlaybackMonitoring()

        let unrelatedQueue = SongRequestQueue()
        _ = unrelatedQueue.add(makeTestRequestItem(
            title: "Other", artist: "Artist", requesterUsername: "viewer"))
        try? await Task.sleep(for: .milliseconds(80))

        XCTAssertEqual(
            mockController.playbackSnapshotCallCount,
            0,
            "A different queue's notification must not wake this service")
    }

    func testStoppingPlaybackMonitorDoesNotPerformFinalPoll() async {
        service = makeServiceWithLiveRequest(pollInterval: .milliseconds(500))

        service.startPlaybackMonitoring()
        // Let the task enter its long sleep, then cancel well before a natural tick.
        try? await Task.sleep(for: .milliseconds(50))
        service.stopPlaybackMonitoring()
        try? await Task.sleep(for: .milliseconds(50))

        XCTAssertEqual(
            mockController.playbackSnapshotCallCount,
            0,
            "Cancelling the sleep must return instead of executing one final poll")
    }

    func testReconcileDoesNotRestartStoppedPlaybackMonitor() async {
        service = makeServiceWithLiveRequest(pollInterval: .milliseconds(500))

        service.startPlaybackMonitoring()
        service.stopPlaybackMonitoring()
        service.reconcilePlaybackMonitoring()
        try? await Task.sleep(for: .milliseconds(80))

        XCTAssertEqual(
            mockController.playbackSnapshotCallCount,
            0,
            "Reconciliation must not resurrect an explicitly stopped monitor")
    }

    func testAutoAdvanceToggleReconcilesPlaybackPolling() async {
        service = makeServiceWithLiveRequest(pollInterval: .milliseconds(20))
        DefaultsStore.store.set(
            false, forKey: AppConstants.UserDefaults.songRequestAutoAdvance)

        service.startPlaybackMonitoring()
        try? await Task.sleep(for: .milliseconds(80))
        XCTAssertEqual(
            mockController.playbackSnapshotCallCount,
            0,
            "Disabled auto-advance should not own a periodic playback task")

        DefaultsStore.store.set(
            true, forKey: AppConstants.UserDefaults.songRequestAutoAdvance)
        service.reconcilePlaybackMonitoring()
        let beganPolling = await waitUntil(timeout: .seconds(1)) {
            self.mockController.playbackSnapshotCallCount > 0
        }
        XCTAssertTrue(beganPolling, "Enabling auto-advance should start polling")

        DefaultsStore.store.set(
            false, forKey: AppConstants.UserDefaults.songRequestAutoAdvance)
        service.reconcilePlaybackMonitoring()
        let callsAfterDisable = mockController.playbackSnapshotCallCount
        try? await Task.sleep(for: .milliseconds(80))

        XCTAssertEqual(
            mockController.playbackSnapshotCallCount,
            callsAfterDisable,
            "Disabling auto-advance should cancel polling immediately")
    }

    func testHoldToggleReconcilesPlaybackPolling() async {
        service = makeServiceWithLiveRequest(pollInterval: .milliseconds(20))

        service.startPlaybackMonitoring()
        let beganPolling = await waitUntil(timeout: .seconds(1)) {
            self.mockController.playbackSnapshotCallCount > 0
        }
        XCTAssertTrue(beganPolling)

        await service.setHold(true)
        let callsWhileHolding = mockController.playbackSnapshotCallCount
        try? await Task.sleep(for: .milliseconds(80))
        XCTAssertEqual(
            mockController.playbackSnapshotCallCount,
            callsWhileHolding,
            "Hold should cancel playback polling immediately")

        await service.setHold(false)
        let resumedPolling = await waitUntil(timeout: .seconds(1)) {
            self.mockController.playbackSnapshotCallCount > callsWhileHolding
        }
        XCTAssertTrue(resumedPolling, "Releasing hold should restore polling")
    }

    // MARK: - VoteSkip

    func testVoteSkipIdleCallsSkipToNext() async {
        // With nothing in nowPlaying, voteSkip() should forward straight to
        // Apple Music's own skip (so vote-skip works during normal streaming).
        mockController.isMusicAppRunning = true
        mockController.isPlaying = true
        mockController.currentTrackID = "Playing\tArtist"

        await service.voteSkip()

        XCTAssertTrue(mockController.skipCalled, "voteSkip with empty nowPlaying must call skipToNext()")
    }

    func testVoteSkipLastRequestWithAutoplayAdvancesMusic() async {
        // Natural queue drain leaves Music autoplay alone, but a passed vote
        // against the last request must actively advance off the voted track.
        _ = queue.add(makeTestRequestItem(title: "Playing", artist: "A", requesterUsername: "user1"))
        queue.dequeue()  // nowPlaying = "Playing"
        XCTAssertNotNil(queue.nowPlaying, "Precondition: a request must be in nowPlaying")
        mockController.currentTrackID = "Playing\tA"

        await service.voteSkip()

        XCTAssertTrue(mockController.skipCalled)
        XCTAssertNil(queue.nowPlaying)
    }

    func testVoteSkipLastRequestUsesTargetedFallback() async {
        DefaultsStore.store.set(
            "Gaming Vibes",
            forKey: AppConstants.UserDefaults.songRequestFallbackPlaylist)
        let current = makeTestRequestItem(
            title: "Playing", artist: "A", requesterUsername: "viewer")
        _ = queue.add(current)
        queue.dequeue()
        mockController.currentTrackID = "Playing\tA"

        await service.voteSkip()

        XCTAssertTrue(mockController.playFallbackCalled)
        XCTAssertEqual(mockController.fallbackPlaylistName, "Gaming Vibes")
        XCTAssertNil(queue.nowPlaying)
    }

    func testVoteSkipLastRequestStopsWhenAutoplayIsDisabled() async {
        DefaultsStore.store.set(
            false,
            forKey: AppConstants.UserDefaults.songRequestAutoplayWhenEmpty)
        let current = makeTestRequestItem(
            title: "Playing", artist: "A", requesterUsername: "viewer")
        _ = queue.add(current)
        queue.dequeue()
        mockController.currentTrackID = "Playing\tA"

        await service.voteSkip()

        XCTAssertTrue(mockController.clearCalled)
        XCTAssertNil(queue.nowPlaying)
    }

    func testTargetedVoteSkipDoesNotReplaceTrackOrCommitQueueAfterTargetChanges() async {
        let gate = PlaybackGate()
        let current = makeTestRequestItem(
            title: "Current", artist: "Artist", requesterUsername: "first")
        let queued = makeTestRequestItem(
            title: "Queued", artist: "Artist", requesterUsername: "second")
        _ = queue.add(current)
        _ = queue.add(queued)
        queue.dequeue()
        mockController.currentTrackID = "Current\tArtist"
        guard let target = await service.capturePlaybackTarget() else {
            return XCTFail("Expected a playback target")
        }
        XCTAssertEqual(target, PlaybackTarget(trackKey: "Current\tArtist", revision: 0))

        mockController.targetedPlaybackHandler = { [weak mockController] action, targetKey in
            await gate.suspend()
            guard mockController?.currentTrackID == targetKey else { return false }
            if case .request = action {
                mockController?.playNowCalled = true
            }
            return true
        }

        let skipping = Task {
            await self.service.voteSkip(target: target)
        }
        await gate.waitUntilStarted()
        mockController.currentTrackID = "Replacement\tArtist"
        service.notePlaybackTrackChanged()
        await gate.release()

        let didSkip = await skipping.value
        XCTAssertFalse(didSkip)
        XCTAssertEqual(mockController.currentTrackID, "Replacement\tArtist")
        XCTAssertFalse(mockController.playNowCalled)
        XCTAssertEqual(queue.nowPlaying?.id, current.id)
        XCTAssertEqual(queue.items.map(\.id), [queued.id])
    }

    func testSuccessfulTargetedVoteCommitsReservedHeadAfterOwnTrackCallback() async {
        let gate = PlaybackGate()
        let current = makeTestRequestItem(
            title: "Current", artist: "Artist", requesterUsername: "first")
        let queued = makeTestRequestItem(
            title: "Queued", artist: "Artist", requesterUsername: "second")
        _ = queue.add(current)
        _ = queue.add(queued)
        queue.dequeue()
        mockController.currentTrackID = "Current\tArtist"
        guard let target = await service.capturePlaybackTarget() else {
            return XCTFail("Expected a playback target")
        }

        mockController.targetedPlaybackHandler = { action, targetKey in
            await gate.suspend()
            guard targetKey == "Current\tArtist" else { return false }
            guard case .request(let item) = action else { return false }
            return item.id == queued.id
        }

        let skipping = Task {
            await self.service.voteSkip(target: target)
        }
        await gate.waitUntilStarted()
        // The successful Music command can make the playback monitor observe
        // its own replacement before this task resumes.
        service.notePlaybackTrackChanged()
        await gate.release()

        let didSkip = await skipping.value
        XCTAssertTrue(didSkip)
        XCTAssertEqual(queue.nowPlaying?.id, queued.id)
        XCTAssertTrue(queue.isEmpty)
    }

    // MARK: - NotPlayable Retry-to-Drop

    func testNotPlayableRetryDropsSendsChatMessage() async {
        var badSongAttempts = 0
        service = SongRequestService(
            queue: queue,
            musicController: mockController,
            playbackOverride: { item in
                guard item.title == "Unavailable" else { return }
                badSongAttempts += 1
                throw PlaybackError.notPlayable(title: item.title)
            }
        )
        var capturedMessages: [String] = []
        service.sendChatMessage = { capturedMessages.append($0) }

        let unavailable = makeTestRequestItem(
            title: "Unavailable", artist: "A", requesterUsername: "u1")
        let playable = makeTestRequestItem(
            title: "Playable", artist: "B", requesterUsername: "u2")
        _ = queue.add(unavailable)
        _ = queue.add(playable)

        let firstAttempt = await service.playNextInQueue()
        let secondAttempt = await service.playNextInQueue()
        XCTAssertNil(firstAttempt)
        XCTAssertNil(secondAttempt)
        let result = await service.playNextInQueue()

        XCTAssertEqual(badSongAttempts, 3)
        XCTAssertEqual(result?.id, playable.id)
        XCTAssertEqual(queue.nowPlaying?.id, playable.id)
        XCTAssertTrue(queue.isEmpty)
        XCTAssertEqual(capturedMessages.count, 1)
        let message = capturedMessages.first ?? ""
        XCTAssertTrue(message.contains("Unavailable"))
        XCTAssertTrue(message.contains("not available on Apple Music"))
    }

    func testNoAdvanceChatMessageWhenQueueDrainsOnStop() async {
        // When the last request finishes and the queue empties, advanceQueue is
        // not called (handleQueueEmptied is called instead), so no "Now playing:" message.
        service = SongRequestService(
            queue: queue,
            musicController: mockController,
            pollInterval: .milliseconds(20)
        )
        var capturedMessages: [String] = []
        service.sendChatMessage = { capturedMessages.append($0) }

        mockController.isMusicAppRunning = true
        mockController.isPlaying = true

        _ = queue.add(makeTestRequestItem(title: "Last", artist: "A", requesterUsername: "u1"))
        queue.dequeue()  // nowPlaying = "Last", queue now empty

        service.startPlaybackMonitoring()

        // Two confirmed-stopped ticks → handleQueueEmptied, no advance message.
        mockController.isPlaying = false
        mockController.isPaused = false
        mockController.snapshotProvider = { PlaybackSnapshot(state: .stopped, trackKey: nil) }

        let gotUnexpectedMessage = await waitUntil(timeout: .seconds(1)) {
            capturedMessages.contains { $0.hasPrefix("Now playing:") }
        }
        service.stopPlaybackMonitoring()

        XCTAssertFalse(
            gotUnexpectedMessage,
            "No 'Now playing:' message should be sent when the queue drains to empty")
    }

    // MARK: - Fallback Yields to Request

    func testFallbackYieldsToIncomingRequest() async {
        // Once isPlayingFallback is true, a request added to the queue takes over
        // on the very next poll tick (the fallback explicitly yields to real requests).
        // Seeding isPlayingFallback requires a prior request to finish: add an item,
        // dequeue it into nowPlaying, then stop playback so handleQueueEmptied fires
        // and starts the fallback. Then add a new request and confirm it takes over.
        //
        // Drives pollTick() directly instead of startPlaybackMonitoring(): the
        // wall-clock poll Task is MainActor-bound and gets starved under parallel
        // CI load, so even a 3s waitUntil flaked (PR #341, run 27247125149).
        // Direct ticks make the debounce counts exact and remove all timing.
        DefaultsStore.store.set(
            "Gaming Vibes", forKey: AppConstants.UserDefaults.songRequestFallbackPlaylist)

        mockController.isMusicAppRunning = true
        mockController.isPlaying = true
        mockController.currentTrackID = "req-track"

        // Seed nowPlaying with an item so the poll is in the "request playing" branch.
        _ = queue.add(makeTestRequestItem(title: "Finishing", artist: "A", requesterUsername: "u1"))
        queue.dequeue()

        // One playing tick establishes the request baseline, then stop playback.
        await service.pollTick()
        mockController.snapshotProvider = { PlaybackSnapshot(state: .stopped, trackKey: nil) }

        // Two confirmed stopped ticks → handleQueueEmptied → startFallbackIfConfigured.
        await service.pollTick()
        await service.pollTick()
        guard mockController.playFallbackCalled else {
            XCTFail("Precondition: fallback should start once the last request finishes")
            DefaultsStore.store.removeObject(forKey: AppConstants.UserDefaults.songRequestFallbackPlaylist)
            return
        }

        // isPlayingFallback is now true. Add a request and verify the very next
        // poll tick dequeues it (fallback yields to a real request immediately).
        _ = queue.add(makeTestRequestItem(title: "RequestedSong", artist: "B", requesterUsername: "viewer"))
        await service.pollTick()

        XCTAssertEqual(
            queue.nowPlaying?.title, "RequestedSong",
            "A request added while the fallback is playing should take over on the next poll tick (fallback yields)")

        DefaultsStore.store.removeObject(forKey: AppConstants.UserDefaults.songRequestFallbackPlaylist)
    }

    func testFallbackYieldsViaIsPlayingFallbackFlag() async {
        // Mirror of testFallbackYieldsToIncomingRequest using a different playlist
        // name, to confirm the dequeue is driven by the isPlayingFallback flag
        // (not just a stopped-state coincidence). Same deterministic pollTick()
        // driving; see the sibling test for the CI-flake rationale.
        DefaultsStore.store.set(
            "Chill Mix", forKey: AppConstants.UserDefaults.songRequestFallbackPlaylist)

        mockController.isMusicAppRunning = true
        mockController.isPlaying = true
        mockController.currentTrackID = "req-track"

        _ = queue.add(makeTestRequestItem(title: "LastReq", artist: "A", requesterUsername: "u1"))
        queue.dequeue()

        // Baseline playing tick, then two confirmed stopped ticks start the fallback.
        await service.pollTick()
        mockController.snapshotProvider = { PlaybackSnapshot(state: .stopped, trackKey: nil) }
        await service.pollTick()
        await service.pollTick()
        guard mockController.playFallbackCalled else {
            XCTFail("Precondition: fallback must activate before the request is added")
            DefaultsStore.store.removeObject(forKey: AppConstants.UserDefaults.songRequestFallbackPlaylist)
            return
        }

        // isPlayingFallback = true. Switch the snapshot back to *playing* so the
        // stopped-debounce can't be what dequeues; only the isPlayingFallback
        // branch can take over on the next tick.
        mockController.snapshotProvider = { PlaybackSnapshot(state: .playing, trackKey: "fallback-track") }
        _ = queue.add(makeTestRequestItem(title: "LiveRequest", artist: "B", requesterUsername: "fan"))
        await service.pollTick()

        XCTAssertEqual(
            queue.nowPlaying?.title, "LiveRequest",
            "A request added while isPlayingFallback is true should dequeue on the next tick even if music is playing")

        DefaultsStore.store.removeObject(forKey: AppConstants.UserDefaults.songRequestFallbackPlaylist)
    }

    // MARK: - SendChatMessage on Queue Advance

    func testSendChatMessageFiresOnAdvanceWithNowPlayingInfo() async {
        // advanceQueue() sends "Now playing: <title> by <artist> (requested by <user>)".
        // Verify the message contains all three pieces of info.
        service = SongRequestService(
            queue: queue,
            musicController: mockController,
            pollInterval: .milliseconds(20)
        )
        var capturedMessages: [String] = []
        service.sendChatMessage = { capturedMessages.append($0) }

        mockController.isMusicAppRunning = true
        mockController.isPlaying = true
        mockController.currentTrackID = "playing-A"

        _ = queue.add(makeTestRequestItem(title: "Howl at the Moon", artist: "Wolf Pack", requesterUsername: "fanviewer"))
        _ = queue.add(makeTestRequestItem(title: "Midnight Run", artist: "Luna", requesterUsername: "nightowl"))
        queue.dequeue()  // nowPlaying = "Howl at the Moon", "Midnight Run" still queued

        service.startPlaybackMonitoring()

        // Let the first poll tick establish playingRequestTrackID = "playing-A"
        // before switching the track, so the poll sees a real divergence.
        try? await Task.sleep(for: .milliseconds(60))

        // Trigger divergence: Music.app loads a different track → advanceQueue fires.
        mockController.currentTrackID = "playing-B"

        let gotMessage = await waitUntil(timeout: .seconds(1)) {
            capturedMessages.contains { $0.hasPrefix("Now playing:") }
        }
        service.stopPlaybackMonitoring()

        XCTAssertTrue(gotMessage, "A 'Now playing:' chat message must fire when the queue advances")
        let message = capturedMessages.first { $0.hasPrefix("Now playing:") } ?? ""
        XCTAssertTrue(message.contains("Midnight Run"), "Chat message must include the new track title")
        XCTAssertTrue(message.contains("Luna"), "Chat message must include the new artist name")
        XCTAssertTrue(message.contains("nightowl"), "Chat message must include the requester username")
    }

    func testSendChatMessageFiresOnHoldRelease() async {
        // setHold(false) also sends a "Now playing:" message when there's a
        // buffered request waiting. Verify this independently of the poll loop.
        DefaultsStore.store.set(true, forKey: AppConstants.UserDefaults.songRequestHoldEnabled)
        var capturedMessages: [String] = []
        service.sendChatMessage = { capturedMessages.append($0) }

        mockController.isMusicAppRunning = true
        mockController.isPlaying = false
        mockController.isPaused = false

        _ = queue.add(makeTestRequestItem(title: "Released Track", artist: "SomeArtist", requesterUsername: "waitingfan"))
        // Do not dequeue: nowPlaying is nil, item is queued, hold is on.
        XCTAssertNil(queue.nowPlaying, "Precondition: nothing playing while hold is on")

        await service.setHold(false)

        // After hold releases, playNextInQueue fires: the controller plays the
        // item's song, the item commits into nowPlaying, and setHold sends the
        // "Now playing:" message.
        XCTAssertTrue(mockController.playNowCalled, "Hold release must actually start the buffered request")
        let sentMessage = capturedMessages.contains { $0.hasPrefix("Now playing:") }
        XCTAssertTrue(sentMessage, "'Now playing:' message must be sent when hold is released with a buffered request")
        XCTAssertTrue(
            capturedMessages.first { $0.hasPrefix("Now playing:") }?.contains("Released Track") == true,
            "Hold-release message must name the dequeued track")
    }
}
