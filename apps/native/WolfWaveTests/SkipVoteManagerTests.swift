//
//  SkipVoteManagerTests.swift
//  WolfWave
//
//  Created by Nathanial Henniges on 2026-05-22.
//  Copyright © 2026 MrDemonWolf, Inc. All rights reserved.
//

import XCTest

@testable import WolfWave

@MainActor
final class SkipVoteManagerTests: WolfWaveTestCase {

    private let keys: [String] = [
        AppConstants.UserDefaults.voteSkipEnabled,
        AppConstants.UserDefaults.voteSkipMinVotes,
        AppConstants.UserDefaults.voteSkipWindowSeconds,
        AppConstants.UserDefaults.voteSkipSessionCooldown,
        AppConstants.UserDefaults.voteSkipSubscriberOnly,
        AppConstants.UserDefaults.voteSkipUsePolls,
        AppConstants.UserDefaults.voteSkipPollDuration,
    ]

    override func setUp() {
        super.setUp()
        keys.forEach { UserDefaults.standard.removeObject(forKey: $0) }
    }

    override func tearDown() {
        keys.forEach { UserDefaults.standard.removeObject(forKey: $0) }
        super.tearDown()
    }

    // MARK: - Helpers

    private func context(
        userID: String,
        isSubscriber: Bool = false,
        isModerator: Bool = false,
        isBroadcaster: Bool = false
    ) -> BotCommandContext {
        BotCommandContext(
            userID: userID,
            username: "user\(userID)",
            isModerator: isModerator,
            isBroadcaster: isBroadcaster,
            isSubscriber: isSubscriber,
            isVIP: false,
            messageID: "m\(userID)"
        )
    }

    private func enableFeature(minVotes: Int = 3, cooldown: Double = 0, window: Int = 60) {
        let d = UserDefaults.standard
        d.set(true, forKey: AppConstants.UserDefaults.voteSkipEnabled)
        d.set(minVotes, forKey: AppConstants.UserDefaults.voteSkipMinVotes)
        d.set(cooldown, forKey: AppConstants.UserDefaults.voteSkipSessionCooldown)
        d.set(window, forKey: AppConstants.UserDefaults.voteSkipWindowSeconds)
    }

    /// Polls an async `condition` until it returns true or the timeout elapses,
    /// returning the final result. Mirrors `ArtworkServiceNetworkTests.waitUntil`
    /// but awaits the (actor-isolated) condition instead of sleeping a fixed span.
    @discardableResult
    private func waitUntil(
        timeout: Duration = .seconds(2),
        interval: Duration = .milliseconds(10),
        _ condition: () async -> Bool
    ) async -> Bool {
        let deadline = ContinuousClock.now + timeout
        while ContinuousClock.now < deadline {
            if await condition() { return true }
            try? await Task.sleep(for: interval)
        }
        return await condition()
    }

    // MARK: - Disabled

    func testDisabledWhenFeatureOff() async {
        let manager = SkipVoteManager()
        let outcome = await manager.recordVote(context: context(userID: "1"))
        XCTAssertEqual(outcome, .disabled)
    }

    // MARK: - Chat-tally Threshold

    func testFirstVoteStartsSession() async {
        enableFeature(minVotes: 3)
        let manager = SkipVoteManager()
        let outcome = await manager.recordVote(context: context(userID: "1"))
        let state = await manager.currentVoteState()
        XCTAssertEqual(outcome, .started(count: 1, needed: 3))
        XCTAssertEqual(state?.count, 1)
    }

    func testSecondVoterIsCounted() async {
        enableFeature(minVotes: 3)
        let manager = SkipVoteManager()
        _ = await manager.recordVote(context: context(userID: "1"))
        let outcome = await manager.recordVote(context: context(userID: "2"))
        XCTAssertEqual(outcome, .counted(count: 2, needed: 3))
    }

    func testThresholdReachedSkipsAndPasses() async {
        enableFeature(minVotes: 3)
        let manager = SkipVoteManager()
        let skipCount = Atomic(0)
        await manager.configure(
            performSkip: { skipCount.mutate { $0 += 1 } },
            sendChatMessage: nil,
            createPoll: nil
        )

        _ = await manager.recordVote(context: context(userID: "1"))
        _ = await manager.recordVote(context: context(userID: "2"))
        let outcome = await manager.recordVote(context: context(userID: "3"))

        let state = await manager.currentVoteState()
        XCTAssertEqual(outcome, .passed(count: 3))
        XCTAssertEqual(skipCount.value, 1)
        XCTAssertNil(state, "Session should reset after passing")
    }

    func testMinVotesOnePassesImmediately() async {
        enableFeature(minVotes: 1)
        let manager = SkipVoteManager()
        let skipped = Atomic(false)
        await manager.configure(
            performSkip: { skipped.set(true) },
            sendChatMessage: nil,
            createPoll: nil
        )

        let outcome = await manager.recordVote(context: context(userID: "1"))
        XCTAssertEqual(outcome, .passed(count: 1))
        XCTAssertTrue(skipped.value)
    }

    // MARK: - Duplicate Voter

    func testDuplicateVoteIsRejected() async {
        enableFeature(minVotes: 3)
        let manager = SkipVoteManager()
        _ = await manager.recordVote(context: context(userID: "1"))
        let outcome = await manager.recordVote(context: context(userID: "1"))
        XCTAssertEqual(outcome, .alreadyVoted(count: 1, needed: 3))
    }

    func testDuplicateVoteDoesNotCrossThreshold() async {
        enableFeature(minVotes: 2)
        let manager = SkipVoteManager()
        let skipCount = Atomic(0)
        await manager.configure(
            performSkip: { skipCount.mutate { $0 += 1 } },
            sendChatMessage: nil,
            createPoll: nil
        )

        _ = await manager.recordVote(context: context(userID: "1"))
        _ = await manager.recordVote(context: context(userID: "1"))
        XCTAssertEqual(skipCount.value, 0, "Same user voting twice must not pass a 2-vote threshold")
    }

    // MARK: - Subscriber-only

    func testSubscriberOnlyRejectsNonSubscriber() async {
        enableFeature(minVotes: 3)
        UserDefaults.standard.set(true, forKey: AppConstants.UserDefaults.voteSkipSubscriberOnly)
        let manager = SkipVoteManager()
        let outcome = await manager.recordVote(context: context(userID: "1", isSubscriber: false))
        XCTAssertEqual(outcome, .subscriberOnly)
    }

    func testSubscriberOnlyAllowsSubscriber() async {
        enableFeature(minVotes: 3)
        UserDefaults.standard.set(true, forKey: AppConstants.UserDefaults.voteSkipSubscriberOnly)
        let manager = SkipVoteManager()
        let outcome = await manager.recordVote(context: context(userID: "1", isSubscriber: true))
        XCTAssertEqual(outcome, .started(count: 1, needed: 3))
    }

    func testSubscriberOnlyAllowsModerator() async {
        enableFeature(minVotes: 3)
        UserDefaults.standard.set(true, forKey: AppConstants.UserDefaults.voteSkipSubscriberOnly)
        let manager = SkipVoteManager()
        let outcome = await manager.recordVote(context: context(userID: "1", isModerator: true))
        XCTAssertEqual(outcome, .started(count: 1, needed: 3))
    }

    // MARK: - Cooldown

    func testCooldownBlocksRapidReVote() async {
        enableFeature(minVotes: 1, cooldown: 60)
        let manager = SkipVoteManager()
        await manager.configure(performSkip: {}, sendChatMessage: nil, createPoll: nil)

        let first = await manager.recordVote(context: context(userID: "1"))
        XCTAssertEqual(first, .passed(count: 1))

        let second = await manager.recordVote(context: context(userID: "2"))
        if case .onCooldown = second {
            // expected
        } else {
            XCTFail("Expected .onCooldown, got \(second)")
        }
    }

    // MARK: - Window Expiry

    func testWindowExpiryFailsSession() async throws {
        enableFeature(minVotes: 5)
        // Inject a sub-100ms window so expiry is observed in milliseconds instead
        // of waiting out the integer-second `voteSkipWindowSeconds` minimum.
        let manager = SkipVoteManager(windowDuration: .milliseconds(50))
        let chatMessage = Atomic<String?>(nil)
        await manager.configure(
            performSkip: nil,
            sendChatMessage: { chatMessage.set($0) },
            createPoll: nil
        )

        _ = await manager.recordVote(context: context(userID: "1"))
        let preState = await manager.currentVoteState()
        XCTAssertNotNil(preState)

        // Poll until the window timer resets the session, bounded well above the
        // 50ms window so it isn't flaky, but far shorter than the old 2s sleep.
        let didReset = await waitUntil(timeout: .seconds(1)) {
            await manager.currentVoteState() == nil
        }

        XCTAssertTrue(didReset, "Session should reset after the window expires")
        let postState = await manager.currentVoteState()
        XCTAssertNil(postState, "Session should reset after the window expires")
        let message = chatMessage.value
        XCTAssertNotNil(message)
        XCTAssertTrue(message?.contains("failed") ?? false)
    }

    // MARK: - Reset

    func testResetClearsSession() async {
        enableFeature(minVotes: 3)
        let manager = SkipVoteManager()
        _ = await manager.recordVote(context: context(userID: "1"))
        await manager.reset()
        let state = await manager.currentVoteState()
        XCTAssertNil(state)
    }

    // MARK: - Polls Mode

    func testPollsModeRejectsNonModerator() async {
        enableFeature(minVotes: 3)
        UserDefaults.standard.set(true, forKey: AppConstants.UserDefaults.voteSkipUsePolls)
        let manager = SkipVoteManager()
        let outcome = await manager.recordVote(context: context(userID: "1"))
        XCTAssertEqual(outcome, .pollNotAllowed)
    }

    func testPollsModeStartsPollForModerator() async {
        enableFeature(minVotes: 3)
        UserDefaults.standard.set(true, forKey: AppConstants.UserDefaults.voteSkipUsePolls)
        let manager = SkipVoteManager()
        await manager.configure(
            performSkip: nil,
            sendChatMessage: nil,
            createPoll: { _, _ in true }
        )
        let outcome = await manager.recordVote(context: context(userID: "1", isModerator: true))
        XCTAssertEqual(outcome, .pollStarted)
    }

    func testPollsModeFallsBackToChatTallyOnFailure() async {
        enableFeature(minVotes: 3)
        UserDefaults.standard.set(true, forKey: AppConstants.UserDefaults.voteSkipUsePolls)
        let manager = SkipVoteManager()
        await manager.configure(
            performSkip: nil,
            sendChatMessage: nil,
            createPoll: { _, _ in false }
        )
        let outcome = await manager.recordVote(context: context(userID: "1", isBroadcaster: true))
        XCTAssertEqual(outcome, .started(count: 1, needed: 3), "Failed poll should fall back to a chat tally")
    }

    func testPollEndedSkipsWhenSkipWins() async {
        enableFeature(minVotes: 3)
        let manager = SkipVoteManager()
        let skipped = Atomic(false)
        await manager.configure(
            performSkip: { skipped.set(true) },
            sendChatMessage: nil,
            createPoll: nil
        )
        await manager.handlePollEnded(skipVotes: 5, keepVotes: 2)
        XCTAssertTrue(skipped.value)
    }

    func testPollEndedDoesNotSkipBelowMinimum() async {
        enableFeature(minVotes: 10)
        let manager = SkipVoteManager()
        let skipped = Atomic(false)
        await manager.configure(
            performSkip: { skipped.set(true) },
            sendChatMessage: nil,
            createPoll: nil
        )
        await manager.handlePollEnded(skipVotes: 5, keepVotes: 2)
        XCTAssertFalse(skipped.value, "Skip wins but is below the minimum vote threshold")
    }

    func testPollEndedDoesNotSkipWhenKeepWins() async {
        enableFeature(minVotes: 1)
        let manager = SkipVoteManager()
        let skipped = Atomic(false)
        await manager.configure(
            performSkip: { skipped.set(true) },
            sendChatMessage: nil,
            createPoll: nil
        )
        await manager.handlePollEnded(skipVotes: 2, keepVotes: 9)
        XCTAssertFalse(skipped.value)
    }

    // MARK: - Vote Event Hook

    func testOnVoteEventFiresStartedWhenSessionOpens() async {
        enableFeature(minVotes: 3)
        let manager = SkipVoteManager()
        let events = Atomic<[String]>([])
        await manager.configure(
            performSkip: nil,
            sendChatMessage: nil,
            createPoll: nil,
            onVoteEvent: { event in
                if case .started(let needed) = event {
                    events.mutate { $0.append("started:\(needed)") }
                }
            }
        )

        _ = await manager.recordVote(context: context(userID: "1"))
        XCTAssertEqual(events.value, ["started:3"])
    }

    func testOnVoteEventFiresPassedOnThreshold() async {
        enableFeature(minVotes: 2)
        let manager = SkipVoteManager()
        let events = Atomic<[String]>([])
        await manager.configure(
            performSkip: nil,
            sendChatMessage: nil,
            createPoll: nil,
            onVoteEvent: { event in
                switch event {
                case .started: events.mutate { $0.append("started") }
                case .passed: events.mutate { $0.append("passed") }
                case .pollStarted: events.mutate { $0.append("pollStarted") }
                }
            }
        )

        _ = await manager.recordVote(context: context(userID: "1"))
        _ = await manager.recordVote(context: context(userID: "2"))
        XCTAssertEqual(events.value, ["started", "passed"])
    }

    func testOnVoteEventFiresPassedFromPollResult() async {
        enableFeature(minVotes: 3)
        let manager = SkipVoteManager()
        let events = Atomic<[String]>([])
        await manager.configure(
            performSkip: nil,
            sendChatMessage: nil,
            createPoll: nil,
            onVoteEvent: { event in
                if case .passed = event { events.mutate { $0.append("passed") } }
            }
        )

        await manager.handlePollEnded(skipVotes: 9, keepVotes: 2)
        XCTAssertEqual(events.value, ["passed"])
    }
}

// MARK: - Sendable Atomic Box for closure capture

/// Thread-safe value box, used by `@Sendable` closures captured into the actor
/// under test. NSLock is fine here; the test isn't measuring lock perf.
private final class Atomic<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: Value

    init(_ value: Value) { stored = value }

    var value: Value { lock.withLock { stored } }

    /// Atomically replaces the stored value.
    func set(_ newValue: Value) { lock.withLock { stored = newValue } }

    /// Atomically transforms the stored value in place.
    func mutate(_ transform: (inout Value) -> Void) { lock.withLock { transform(&stored) } }
}
