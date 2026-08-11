//
//  SkipVoteManagerTests.swift
//  WolfWave
//
//  Created by Nathanial Henniges on 2026-05-22.
//  Copyright © 2026 MrDemonWolf, Inc. All rights reserved.
//

import XCTest

@testable import WolfWave

/// Suspends Twitch poll creation so tests can deterministically change tracks
/// while the actor is reentrant at the network boundary.
private actor PollCreationGate {
    private let result: SkipPollCreationOutcome
    private var hasStarted = false
    private var wasReleased = false
    private var startWaiters: [CheckedContinuation<Void, Never>] = []
    private var releaseWaiter: CheckedContinuation<Void, Never>?

    init(result: SkipPollCreationOutcome) {
        self.result = result
    }

    func create() async -> SkipPollCreationOutcome {
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
        return result
    }

    func waitUntilStarted() async {
        guard !hasStarted else { return }
        await withCheckedContinuation { continuation in
            startWaiters.append(continuation)
        }
    }

    func started() -> Bool {
        hasStarted
    }

    func release() {
        wasReleased = true
        releaseWaiter?.resume()
        releaseWaiter = nil
    }
}

/// Suspends the final target-bound Music mutation so a test can change the
/// supplied playback identity while a poll result is being applied.
private actor TargetedSkipGate {
    private let result: Bool
    private var target: PlaybackTarget?
    private var hasStarted = false
    private var wasReleased = false
    private var startWaiters: [CheckedContinuation<Void, Never>] = []
    private var releaseWaiter: CheckedContinuation<Void, Never>?

    init(result: Bool) {
        self.result = result
    }

    func perform(target: PlaybackTarget) async -> Bool {
        self.target = target
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
        return result
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

    func receivedTarget() -> PlaybackTarget? {
        target
    }
}

/// Suspends Music.app target capture so generation changes can be applied at
/// the actor reentrancy boundary before a vote claims session or poll state.
private actor PlaybackTargetCaptureGate {
    private let target: PlaybackTarget
    private var captureCount = 0
    private var wasReleased = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    init(target: PlaybackTarget = PlaybackTarget(trackKey: "target\tartist", revision: 0)) {
        self.target = target
    }

    func capture() async -> PlaybackTarget {
        captureCount += 1
        await withCheckedContinuation { continuation in
            if wasReleased {
                continuation.resume()
            } else {
                waiters.append(continuation)
            }
        }
        return target
    }

    func startedCount() -> Int {
        captureCount
    }

    func release() {
        wasReleased = true
        let pending = waiters
        waiters.removeAll()
        pending.forEach { $0.resume() }
    }
}

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
        let skipCount = ThreadSafeBox(0)
        await manager.configure(
            capturePlaybackTarget: { PlaybackTarget(trackKey: "target\tartist", revision: 0) },
            performSkip: { _ in skipCount.mutate { $0 += 1 }; return true },
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
        let skipped = ThreadSafeBox(false)
        await manager.configure(
            capturePlaybackTarget: { PlaybackTarget(trackKey: "target\tartist", revision: 0) },
            performSkip: { _ in skipped.set(true); return true },
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
        let skipCount = ThreadSafeBox(0)
        await manager.configure(
            capturePlaybackTarget: { PlaybackTarget(trackKey: "target\tartist", revision: 0) },
            performSkip: { _ in skipCount.mutate { $0 += 1 }; return true },
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
        await manager.configure(
            capturePlaybackTarget: {
                PlaybackTarget(trackKey: "target\tartist", revision: 0)
            },
            performSkip: { _ in true },
            sendChatMessage: nil,
            createPoll: nil)

        let first = await manager.recordVote(context: context(userID: "1"))
        XCTAssertEqual(first, .passed(count: 1))

        let second = await manager.recordVote(context: context(userID: "2"))
        if case .onCooldown = second {
            // expected
        } else {
            XCTFail("Expected .onCooldown, got \(second)")
        }
    }

    func testCorruptSessionCooldownClampsAndDoesNotTrap() async {
        // The cooldown key is user-writable (exportable backup, `defaults write`).
        // An out-of-range value flows into Int(ceil(...)) on the next vote and
        // would trap unclamped. The accessor must clamp to 0...3600.
        UserDefaults.standard.set(1e300, forKey: AppConstants.UserDefaults.voteSkipSessionCooldown)
        let manager = SkipVoteManager()
        XCTAssertEqual(manager.sessionCooldown, 3600, accuracy: 0.001)

        // Drive a real vote through the cooldown branch to prove no trap.
        enableFeature(minVotes: 1, cooldown: 1e300)
        await manager.configure(
            capturePlaybackTarget: {
                PlaybackTarget(trackKey: "target\tartist", revision: 0)
            },
            performSkip: { _ in true },
            sendChatMessage: nil,
            createPoll: nil)
        _ = await manager.recordVote(context: context(userID: "1"))
        let second = await manager.recordVote(context: context(userID: "2"))
        if case .onCooldown(let remaining) = second {
            XCTAssertGreaterThanOrEqual(remaining, 0)
            XCTAssertLessThanOrEqual(remaining, 3600)
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
        let chatMessage = ThreadSafeBox<String?>(nil)
        await manager.configure(
            capturePlaybackTarget: { PlaybackTarget(trackKey: "target\tartist", revision: 0) },
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

    // MARK: - Track Change

    func testTrackChangeClearsChatTallySession() async {
        enableFeature(minVotes: 3)
        let manager = SkipVoteManager()
        _ = await manager.recordVote(context: context(userID: "1"))
        _ = await manager.recordVote(context: context(userID: "2"))
        let before = await manager.currentVoteState()
        XCTAssertEqual(before?.count, 2)

        await manager.trackDidChange()

        let after = await manager.currentVoteState()
        XCTAssertNil(after, "Votes against the old song must not carry over to the new one")
    }

    func testTrackChangeDoesNotStartCooldown() async {
        // A long cooldown would block the next vote if trackDidChange (wrongly)
        // ended the session the way window expiry does.
        enableFeature(minVotes: 3, cooldown: 60)
        let manager = SkipVoteManager()
        _ = await manager.recordVote(context: context(userID: "1"))

        await manager.trackDidChange()

        let outcome = await manager.recordVote(context: context(userID: "2"))
        XCTAssertEqual(
            outcome,
            .started(count: 1, needed: 3),
            "A fresh vote must open immediately after a track change; no cooldown applies"
        )
    }

    func testTrackChangeWithoutSessionIsNoOp() async {
        enableFeature(minVotes: 3, cooldown: 60)
        let manager = SkipVoteManager()

        await manager.trackDidChange()

        let outcome = await manager.recordVote(context: context(userID: "1"))
        XCTAssertEqual(outcome, .started(count: 1, needed: 3))
    }

    func testTrackChangeLeavesActivePollAlone() async {
        enableFeature(minVotes: 3)
        UserDefaults.standard.set(true, forKey: AppConstants.UserDefaults.voteSkipUsePolls)
        let manager = SkipVoteManager()
        await manager.configure(
            capturePlaybackTarget: { PlaybackTarget(trackKey: "target\tartist", revision: 0) },
            performSkip: nil,
            sendChatMessage: nil,
            createPoll: { _, _ in .created(id: "poll-1") }
        )
        _ = await manager.recordVote(context: context(userID: "1", isModerator: true))

        await manager.trackDidChange()

        let active = await manager.isPollInProgress()
        XCTAssertTrue(
            active,
            "trackDidChange only ends chat-tally sessions; a live Twitch poll still resolves via poll.end"
        )
    }

    func testTrackChangeDuringChatTargetCaptureDoesNotOpenSession() async {
        enableFeature(minVotes: 3)
        let manager = SkipVoteManager()
        let gate = PlaybackTargetCaptureGate()
        await manager.configure(
            capturePlaybackTarget: { await gate.capture() },
            performSkip: nil,
            sendChatMessage: nil,
            createPoll: nil
        )

        let vote = Task {
            await manager.recordVote(context: self.context(userID: "capture-chat"))
        }
        let reachedCapture = await waitUntil(timeout: .seconds(1)) {
            await gate.startedCount() == 1
        }
        XCTAssertTrue(reachedCapture)
        await manager.trackDidChange()
        await gate.release()

        let outcome = await vote.value
        XCTAssertEqual(outcome, .playbackUnavailable)
        let state = await manager.currentVoteState()
        XCTAssertNil(state)
    }

    func testResetDuringChatTargetCaptureDoesNotReopenSession() async {
        enableFeature(minVotes: 3)
        let manager = SkipVoteManager()
        let gate = PlaybackTargetCaptureGate()
        await manager.configure(
            capturePlaybackTarget: { await gate.capture() },
            performSkip: nil,
            sendChatMessage: nil,
            createPoll: nil
        )

        let vote = Task {
            await manager.recordVote(context: self.context(userID: "capture-reset"))
        }
        let reachedCapture = await waitUntil(timeout: .seconds(1)) {
            await gate.startedCount() == 1
        }
        XCTAssertTrue(reachedCapture)
        await manager.reset()
        await gate.release()

        let outcome = await vote.value
        XCTAssertEqual(outcome, .playbackUnavailable)
        let state = await manager.currentVoteState()
        XCTAssertNil(state)
    }

    func testTrackChangeDuringPollTargetCaptureDoesNotCreatePoll() async {
        enableFeature(minVotes: 3)
        UserDefaults.standard.set(true, forKey: AppConstants.UserDefaults.voteSkipUsePolls)
        let manager = SkipVoteManager()
        let gate = PlaybackTargetCaptureGate()
        let createCalls = ThreadSafeBox(0)
        await manager.configure(
            capturePlaybackTarget: { await gate.capture() },
            performSkip: nil,
            sendChatMessage: nil,
            createPoll: { _, _ in
                createCalls.mutate { $0 += 1 }
                return .created(id: "must-not-open")
            }
        )

        let vote = Task {
            await manager.recordVote(
                context: self.context(userID: "capture-poll", isModerator: true))
        }
        let reachedCapture = await waitUntil(timeout: .seconds(1)) {
            await gate.startedCount() == 1
        }
        XCTAssertTrue(reachedCapture)
        await manager.trackDidChange()
        await gate.release()

        let outcome = await vote.value
        XCTAssertEqual(outcome, .pollTrackChanged)
        XCTAssertEqual(createCalls.value, 0)
        let active = await manager.isPollInProgress()
        XCTAssertFalse(active)
    }

    func testResetDuringPollTargetCaptureDoesNotCreatePoll() async {
        enableFeature(minVotes: 3)
        UserDefaults.standard.set(true, forKey: AppConstants.UserDefaults.voteSkipUsePolls)
        let manager = SkipVoteManager()
        let gate = PlaybackTargetCaptureGate()
        let createCalls = ThreadSafeBox(0)
        await manager.configure(
            capturePlaybackTarget: { await gate.capture() },
            performSkip: nil,
            sendChatMessage: nil,
            createPoll: { _, _ in
                createCalls.mutate { $0 += 1 }
                return .created(id: "must-not-open")
            }
        )

        let vote = Task {
            await manager.recordVote(
                context: self.context(userID: "capture-reset-poll", isModerator: true))
        }
        let reachedCapture = await waitUntil(timeout: .seconds(1)) {
            await gate.startedCount() == 1
        }
        XCTAssertTrue(reachedCapture)
        await manager.reset()
        await gate.release()

        let outcome = await vote.value
        XCTAssertEqual(outcome, .pollRequestCancelled)
        XCTAssertEqual(createCalls.value, 0)
        let active = await manager.isPollInProgress()
        XCTAssertFalse(active)
    }

    func testConcurrentModeratorVotesCreateOnlyOnePoll() async {
        enableFeature(minVotes: 3)
        UserDefaults.standard.set(true, forKey: AppConstants.UserDefaults.voteSkipUsePolls)
        let manager = SkipVoteManager()
        let gate = PlaybackTargetCaptureGate()
        let createCalls = ThreadSafeBox(0)
        await manager.configure(
            capturePlaybackTarget: { await gate.capture() },
            performSkip: nil,
            sendChatMessage: nil,
            createPoll: { _, _ in
                createCalls.mutate { $0 += 1 }
                return .created(id: "single-poll")
            }
        )

        let first = Task {
            await manager.recordVote(
                context: self.context(userID: "mod-1", isModerator: true))
        }
        let second = Task {
            await manager.recordVote(
                context: self.context(userID: "mod-2", isModerator: true))
        }
        let bothReachedCapture = await waitUntil(timeout: .seconds(1)) {
            await gate.startedCount() == 2
        }
        XCTAssertTrue(bothReachedCapture)
        await gate.release()

        let outcomes = [await first.value, await second.value]
        XCTAssertEqual(outcomes.filter { $0 == .pollStarted }.count, 1)
        XCTAssertEqual(outcomes.filter { $0 == .pollInProgress }.count, 1)
        XCTAssertEqual(createCalls.value, 1)
    }

    func testChatModeToggleDuringTargetCaptureDoesNotOpenTally() async {
        enableFeature(minVotes: 3)
        let manager = SkipVoteManager()
        let gate = PlaybackTargetCaptureGate()
        await manager.configure(
            capturePlaybackTarget: { await gate.capture() },
            performSkip: nil,
            sendChatMessage: nil,
            createPoll: nil
        )

        let vote = Task {
            await manager.recordVote(context: self.context(userID: "mode-chat"))
        }
        let reachedCapture = await waitUntil(timeout: .seconds(1)) {
            await gate.startedCount() == 1
        }
        XCTAssertTrue(reachedCapture)
        UserDefaults.standard.set(true, forKey: AppConstants.UserDefaults.voteSkipUsePolls)
        await gate.release()

        let outcome = await vote.value
        XCTAssertEqual(outcome, .playbackUnavailable)
        let state = await manager.currentVoteState()
        XCTAssertNil(state)
    }

    func testPollModeToggleDuringTargetCaptureDoesNotCreatePoll() async {
        enableFeature(minVotes: 3)
        UserDefaults.standard.set(true, forKey: AppConstants.UserDefaults.voteSkipUsePolls)
        let manager = SkipVoteManager()
        let gate = PlaybackTargetCaptureGate()
        let createCalls = ThreadSafeBox(0)
        await manager.configure(
            capturePlaybackTarget: { await gate.capture() },
            performSkip: nil,
            sendChatMessage: nil,
            createPoll: { _, _ in
                createCalls.mutate { $0 += 1 }
                return .created(id: "must-not-open")
            }
        )

        let vote = Task {
            await manager.recordVote(
                context: self.context(userID: "mode-poll", isModerator: true))
        }
        let reachedCapture = await waitUntil(timeout: .seconds(1)) {
            await gate.startedCount() == 1
        }
        XCTAssertTrue(reachedCapture)
        UserDefaults.standard.set(false, forKey: AppConstants.UserDefaults.voteSkipUsePolls)
        await gate.release()

        let outcome = await vote.value
        XCTAssertEqual(outcome, .pollRequestCancelled)
        XCTAssertEqual(createCalls.value, 0)
        let active = await manager.isPollInProgress()
        XCTAssertFalse(active)
    }

    func testActivePollBlocksChatTallyAfterPollModeIsDisabled() async {
        enableFeature(minVotes: 3)
        UserDefaults.standard.set(true, forKey: AppConstants.UserDefaults.voteSkipUsePolls)
        let manager = SkipVoteManager()
        let createCalls = ThreadSafeBox(0)
        await manager.configure(
            capturePlaybackTarget: {
                PlaybackTarget(trackKey: "target\tartist", revision: 0)
            },
            performSkip: nil,
            sendChatMessage: nil,
            createPoll: { _, _ in
                createCalls.mutate { $0 += 1 }
                return .created(id: "latched")
            }
        )
        _ = await manager.recordVote(
            context: context(userID: "starter", isModerator: true))
        UserDefaults.standard.set(false, forKey: AppConstants.UserDefaults.voteSkipUsePolls)

        let outcome = await manager.recordVote(context: context(userID: "viewer"))

        XCTAssertEqual(outcome, .pollInProgress)
        XCTAssertEqual(createCalls.value, 1)
        let chatState = await manager.currentVoteState()
        XCTAssertNil(chatState)
    }

    func testPollEndDrainsWithoutSkippingAfterFeatureIsDisabled() async {
        enableFeature(minVotes: 1)
        UserDefaults.standard.set(true, forKey: AppConstants.UserDefaults.voteSkipUsePolls)
        let manager = SkipVoteManager()
        let skipped = ThreadSafeBox(false)
        await manager.configure(
            capturePlaybackTarget: {
                PlaybackTarget(trackKey: "target\tartist", revision: 0)
            },
            performSkip: { _ in
                skipped.set(true)
                return true
            },
            sendChatMessage: nil,
            createPoll: { _, _ in .created(id: "disabled-result") }
        )
        _ = await manager.recordVote(
            context: context(userID: "starter", isModerator: true))
        UserDefaults.standard.set(false, forKey: AppConstants.UserDefaults.voteSkipEnabled)

        await manager.handlePollEnded(
            pollID: "disabled-result", skipVotes: 10, keepVotes: 0)

        XCTAssertFalse(skipped.value)
        let active = await manager.isPollInProgress()
        XCTAssertFalse(active)
    }

    func testFeatureDisableDuringChatTargetCaptureDoesNotOpenTally() async {
        enableFeature(minVotes: 3)
        let manager = SkipVoteManager()
        let gate = PlaybackTargetCaptureGate()
        await manager.configure(
            capturePlaybackTarget: { await gate.capture() },
            performSkip: nil,
            sendChatMessage: nil,
            createPoll: nil
        )

        let vote = Task {
            await manager.recordVote(context: self.context(userID: "disable-chat"))
        }
        let reachedCapture = await waitUntil(timeout: .seconds(1)) {
            await gate.startedCount() == 1
        }
        XCTAssertTrue(reachedCapture)
        UserDefaults.standard.set(false, forKey: AppConstants.UserDefaults.voteSkipEnabled)
        await gate.release()

        let outcome = await vote.value
        XCTAssertEqual(outcome, .disabled)
        let state = await manager.currentVoteState()
        XCTAssertNil(state)
    }

    func testFeatureDisableDuringPollTargetCaptureDoesNotCreatePoll() async {
        enableFeature(minVotes: 3)
        UserDefaults.standard.set(true, forKey: AppConstants.UserDefaults.voteSkipUsePolls)
        let manager = SkipVoteManager()
        let gate = PlaybackTargetCaptureGate()
        let createCalls = ThreadSafeBox(0)
        await manager.configure(
            capturePlaybackTarget: { await gate.capture() },
            performSkip: nil,
            sendChatMessage: nil,
            createPoll: { _, _ in
                createCalls.mutate { $0 += 1 }
                return .created(id: "must-not-open")
            }
        )

        let vote = Task {
            await manager.recordVote(
                context: self.context(userID: "disable-poll", isModerator: true))
        }
        let reachedCapture = await waitUntil(timeout: .seconds(1)) {
            await gate.startedCount() == 1
        }
        XCTAssertTrue(reachedCapture)
        UserDefaults.standard.set(false, forKey: AppConstants.UserDefaults.voteSkipEnabled)
        await gate.release()

        let outcome = await vote.value
        XCTAssertEqual(outcome, .disabled)
        XCTAssertEqual(createCalls.value, 0)
        let active = await manager.isPollInProgress()
        XCTAssertFalse(active)
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
            capturePlaybackTarget: { PlaybackTarget(trackKey: "target\tartist", revision: 0) },
            performSkip: nil,
            sendChatMessage: nil,
            createPoll: { _, _ in .created(id: "poll-1") }
        )
        let outcome = await manager.recordVote(context: context(userID: "1", isModerator: true))
        XCTAssertEqual(outcome, .pollStarted)
    }

    func testPollsModeDoesNotCallTwitchWithoutVerifiedPlaybackTarget() async {
        enableFeature(minVotes: 3)
        UserDefaults.standard.set(true, forKey: AppConstants.UserDefaults.voteSkipUsePolls)
        let manager = SkipVoteManager()
        let createCalls = ThreadSafeBox(0)
        await manager.configure(
            capturePlaybackTarget: { nil },
            performSkip: nil,
            sendChatMessage: nil,
            createPoll: { _, _ in
                createCalls.mutate { $0 += 1 }
                return .created(id: "should-not-exist")
            })

        let outcome = await manager.recordVote(
            context: context(userID: "1", isModerator: true))

        XCTAssertEqual(outcome, .playbackUnavailable)
        XCTAssertEqual(createCalls.value, 0)
    }

    func testPollsModeFallsBackToChatTallyOnFailure() async {
        enableFeature(minVotes: 3)
        UserDefaults.standard.set(true, forKey: AppConstants.UserDefaults.voteSkipUsePolls)
        let manager = SkipVoteManager()
        let chatMessages = ThreadSafeBox<[String]>([])
        let createCalls = ThreadSafeBox(0)
        await manager.configure(
            capturePlaybackTarget: { PlaybackTarget(trackKey: "target\tartist", revision: 0) },
            performSkip: nil,
            sendChatMessage: { message in chatMessages.mutate { $0.append(message) } },
            createPoll: { _, _ in
                createCalls.mutate { $0 += 1 }
                return .definitiveFailure
            }
        )
        let outcome = await manager.recordVote(context: context(userID: "1", isBroadcaster: true))
        XCTAssertEqual(outcome, .started(count: 1, needed: 3), "Failed poll should fall back to a chat tally")
        let second = await manager.recordVote(context: context(userID: "2"))
        XCTAssertEqual(second, .counted(count: 2, needed: 3))
        XCTAssertEqual(createCalls.value, 1)
        XCTAssertEqual(
            chatMessages.value,
            ["📊 Twitch couldn't open a poll, counting chat votes instead."])
    }

    func testExistingNativePollLatchesWithoutOpeningChatFallback() async {
        enableFeature(minVotes: 3)
        UserDefaults.standard.set(true, forKey: AppConstants.UserDefaults.voteSkipUsePolls)
        let manager = SkipVoteManager(pollTimeoutDuration: .seconds(30))
        let chatMessages = ThreadSafeBox<[String]>([])
        await manager.configure(
            capturePlaybackTarget: { PlaybackTarget(trackKey: "target\tartist", revision: 0) },
            performSkip: nil,
            sendChatMessage: { message in chatMessages.mutate { $0.append(message) } },
            createPoll: { _, _ in .pollAlreadyActive })

        let outcome = await manager.recordVote(
            context: context(userID: "1", isBroadcaster: true))
        let isPollActive = await manager.isPollInProgress()
        let chatState = await manager.currentVoteState()

        XCTAssertEqual(outcome, .pollInProgress)
        XCTAssertTrue(isPollActive)
        XCTAssertNil(chatState)
        XCTAssertTrue(chatMessages.value.isEmpty)
    }

    func testIndeterminatePollCreationLatchesUntilTimeoutAndBlocksFallback() async {
        enableFeature(minVotes: 3)
        UserDefaults.standard.set(true, forKey: AppConstants.UserDefaults.voteSkipUsePolls)
        let manager = SkipVoteManager(pollTimeoutDuration: .milliseconds(50))
        let createCalls = ThreadSafeBox(0)
        let chatMessages = ThreadSafeBox<[String]>([])
        await manager.configure(
            capturePlaybackTarget: { PlaybackTarget(trackKey: "target\tartist", revision: 0) },
            performSkip: nil,
            sendChatMessage: { message in
                chatMessages.mutate { $0.append(message) }
            },
            createPoll: { _, _ in
                createCalls.mutate { $0 += 1 }
                return .indeterminate
            }
        )

        let outcome = await manager.recordVote(
            context: context(userID: "1", isModerator: true))
        XCTAssertEqual(outcome, .pollStatusUnknown)
        let active = await manager.isPollInProgress()
        let chatState = await manager.currentVoteState()
        XCTAssertTrue(active)
        XCTAssertNil(chatState)
        XCTAssertTrue(chatMessages.value.isEmpty)

        let blocked = await manager.recordVote(
            context: context(userID: "2", isModerator: true))
        XCTAssertEqual(blocked, .pollInProgress)
        XCTAssertEqual(createCalls.value, 1)
        let blockedChatState = await manager.currentVoteState()
        XCTAssertNil(blockedChatState)

        let timedOut = await waitUntil(timeout: .seconds(1)) {
            await manager.isPollInProgress() == false
        }
        XCTAssertTrue(timedOut)

        let afterTimeout = await manager.recordVote(
            context: context(userID: "3", isModerator: true))
        XCTAssertEqual(afterTimeout, .pollStatusUnknown)
        XCTAssertEqual(createCalls.value, 2)
    }

    func testPollEndedSkipsWhenSkipWins() async {
        enableFeature(minVotes: 3)
        UserDefaults.standard.set(true, forKey: AppConstants.UserDefaults.voteSkipUsePolls)
        let manager = SkipVoteManager()
        let skipped = ThreadSafeBox(false)
        await manager.configure(
            capturePlaybackTarget: { PlaybackTarget(trackKey: "target\tartist", revision: 0) },
            performSkip: { _ in skipped.set(true); return true },
            sendChatMessage: nil,
            createPoll: { _, _ in .created(id: "poll-1") }
        )
        _ = await manager.recordVote(context: context(userID: "1", isModerator: true))
        await manager.handlePollEnded(pollID: "poll-1", skipVotes: 5, keepVotes: 2)
        XCTAssertTrue(skipped.value)
    }

    func testPollPassUsesOpeningTargetAndDoesNotClaimSuccessWhenMutationIsStale() async {
        enableFeature(minVotes: 1)
        UserDefaults.standard.set(true, forKey: AppConstants.UserDefaults.voteSkipUsePolls)
        let manager = SkipVoteManager()
        let openingTarget = PlaybackTarget(trackKey: "Opening\tArtist", revision: 7)
        let suppliedTarget = ThreadSafeBox(openingTarget)
        let gate = TargetedSkipGate(result: false)
        let chatMessages = ThreadSafeBox<[String]>([])
        let events = ThreadSafeBox<[String]>([])
        await manager.configure(
            capturePlaybackTarget: { suppliedTarget.value },
            performSkip: { target in await gate.perform(target: target) },
            sendChatMessage: { message in chatMessages.mutate { $0.append(message) } },
            createPoll: { _, _ in .created(id: "poll-opening") },
            onVoteEvent: { event in
                if case .passed = event { events.mutate { $0.append("passed") } }
            }
        )
        _ = await manager.recordVote(context: context(userID: "1", isModerator: true))

        let ending = Task {
            await manager.handlePollEnded(
                pollID: "poll-opening", skipVotes: 10, keepVotes: 0)
        }
        await gate.waitUntilStarted()
        suppliedTarget.set(PlaybackTarget(trackKey: "Replacement\tArtist", revision: 8))
        await gate.release()
        await ending.value

        let receivedTarget = await gate.receivedTarget()
        XCTAssertEqual(receivedTarget, openingTarget)
        XCTAssertTrue(chatMessages.value.isEmpty)
        XCTAssertTrue(events.value.isEmpty)
    }

    func testChatTallyBindsOpeningTargetAndDoesNotReportPassedForStaleMutation() async {
        enableFeature(minVotes: 2)
        let manager = SkipVoteManager()
        let openingTarget = PlaybackTarget(trackKey: "Opening\tArtist", revision: 4)
        let suppliedTarget = ThreadSafeBox(openingTarget)
        let receivedTarget = ThreadSafeBox<PlaybackTarget?>(nil)
        let events = ThreadSafeBox<[String]>([])
        await manager.configure(
            capturePlaybackTarget: { suppliedTarget.value },
            performSkip: { target in
                receivedTarget.set(target)
                return false
            },
            sendChatMessage: nil,
            createPoll: nil,
            onVoteEvent: { event in
                switch event {
                case .started: events.mutate { $0.append("started") }
                case .passed: events.mutate { $0.append("passed") }
                case .pollStarted: break
                }
            }
        )

        let first = await manager.recordVote(context: context(userID: "1"))
        suppliedTarget.set(PlaybackTarget(trackKey: "Replacement\tArtist", revision: 5))
        let second = await manager.recordVote(context: context(userID: "2"))

        XCTAssertEqual(first, .started(count: 1, needed: 2))
        XCTAssertEqual(second, .skipUnavailable)
        XCTAssertEqual(receivedTarget.value, openingTarget)
        XCTAssertEqual(events.value, ["started"])
    }

    func testPollEndedDoesNotSkipBelowMinimum() async {
        enableFeature(minVotes: 10)
        UserDefaults.standard.set(true, forKey: AppConstants.UserDefaults.voteSkipUsePolls)
        let manager = SkipVoteManager()
        let skipped = ThreadSafeBox(false)
        await manager.configure(
            capturePlaybackTarget: { PlaybackTarget(trackKey: "target\tartist", revision: 0) },
            performSkip: { _ in skipped.set(true); return true },
            sendChatMessage: nil,
            createPoll: { _, _ in .created(id: "poll-1") }
        )
        _ = await manager.recordVote(context: context(userID: "1", isModerator: true))
        await manager.handlePollEnded(pollID: "poll-1", skipVotes: 5, keepVotes: 2)
        XCTAssertFalse(skipped.value, "Skip wins but is below the minimum vote threshold")
    }

    func testPollEndedDoesNotSkipWhenKeepWins() async {
        enableFeature(minVotes: 1)
        UserDefaults.standard.set(true, forKey: AppConstants.UserDefaults.voteSkipUsePolls)
        let manager = SkipVoteManager()
        let skipped = ThreadSafeBox(false)
        await manager.configure(
            capturePlaybackTarget: { PlaybackTarget(trackKey: "target\tartist", revision: 0) },
            performSkip: { _ in skipped.set(true); return true },
            sendChatMessage: nil,
            createPoll: { _, _ in .created(id: "poll-1") }
        )
        _ = await manager.recordVote(context: context(userID: "1", isModerator: true))
        await manager.handlePollEnded(pollID: "poll-1", skipVotes: 2, keepVotes: 9)
        XCTAssertFalse(skipped.value)
    }

    func testWrongPollIDDoesNotClearOrApplyActivePoll() async {
        enableFeature(minVotes: 1)
        UserDefaults.standard.set(true, forKey: AppConstants.UserDefaults.voteSkipUsePolls)
        let manager = SkipVoteManager()
        let skipped = ThreadSafeBox(false)
        await manager.configure(
            capturePlaybackTarget: { PlaybackTarget(trackKey: "target\tartist", revision: 0) },
            performSkip: { _ in skipped.set(true); return true },
            sendChatMessage: nil,
            createPoll: { _, _ in .created(id: "poll-active") }
        )
        _ = await manager.recordVote(context: context(userID: "1", isModerator: true))

        await manager.handlePollEnded(
            pollID: "poll-other", skipVotes: 99, keepVotes: 0)

        XCTAssertFalse(skipped.value)
        let stillActive = await manager.isPollInProgress()
        XCTAssertTrue(stillActive, "An unrelated poll.end must not clear the active poll or its timer")

        await manager.handlePollEnded(
            pollID: "poll-active", skipVotes: 0, keepVotes: 1)
        let inactive = await manager.isPollInProgress()
        XCTAssertFalse(inactive)
    }

    func testPollForPreviousTrackCannotSkipReplacementTrack() async {
        enableFeature(minVotes: 1)
        UserDefaults.standard.set(true, forKey: AppConstants.UserDefaults.voteSkipUsePolls)
        let manager = SkipVoteManager()
        let skipped = ThreadSafeBox(false)
        await manager.configure(
            capturePlaybackTarget: { PlaybackTarget(trackKey: "target\tartist", revision: 0) },
            performSkip: { _ in skipped.set(true); return true },
            sendChatMessage: nil,
            createPoll: { _, _ in .created(id: "poll-old-track") }
        )
        _ = await manager.recordVote(context: context(userID: "1", isModerator: true))

        await manager.trackDidChange()
        await manager.handlePollEnded(
            pollID: "poll-old-track", skipVotes: 10, keepVotes: 0)

        XCTAssertFalse(skipped.value, "A poll against the outgoing track must never skip its replacement")
        let active = await manager.isPollInProgress()
        XCTAssertFalse(active, "The matching stale poll result should still drain active state")
    }

    func testTrackChangeDuringPollCreationRetainsSuccessfulRemotePollUntilDrain() async {
        enableFeature(minVotes: 1)
        UserDefaults.standard.set(true, forKey: AppConstants.UserDefaults.voteSkipUsePolls)
        let manager = SkipVoteManager()
        let gate = PollCreationGate(result: .created(id: "poll-delayed"))
        let skipped = ThreadSafeBox(false)
        await manager.configure(
            capturePlaybackTarget: { PlaybackTarget(trackKey: "target\tartist", revision: 0) },
            performSkip: { _ in skipped.set(true); return true },
            sendChatMessage: nil,
            createPoll: { _, _ in await gate.create() }
        )

        let creation = Task {
            await manager.recordVote(context: self.context(userID: "1", isModerator: true))
        }
        await gate.waitUntilStarted()
        await manager.trackDidChange()
        await gate.release()

        let outcome = await creation.value
        XCTAssertEqual(outcome, .pollTrackChanged)
        let active = await manager.isPollInProgress()
        XCTAssertTrue(active, "A remotely-created poll must stay latched until Twitch drains it")

        let newAttempt = await manager.recordVote(
            context: context(userID: "2", isModerator: true))
        XCTAssertEqual(
            newAttempt, .pollInProgress,
            "Twitch allows only one active poll; do not fall back to a simultaneous chat tally")

        await manager.handlePollEnded(
            pollID: "poll-delayed", skipVotes: 10, keepVotes: 0)
        XCTAssertFalse(skipped.value)
        let drained = await manager.isPollInProgress()
        XCTAssertFalse(drained)
    }

    func testTrackChangeDuringFailedPollCreationDoesNotFallbackVote() async {
        enableFeature(minVotes: 3)
        UserDefaults.standard.set(true, forKey: AppConstants.UserDefaults.voteSkipUsePolls)
        let manager = SkipVoteManager()
        let gate = PollCreationGate(result: .definitiveFailure)
        await manager.configure(
            capturePlaybackTarget: { PlaybackTarget(trackKey: "target\tartist", revision: 0) },
            performSkip: nil,
            sendChatMessage: nil,
            createPoll: { _, _ in await gate.create() }
        )

        let creation = Task {
            await manager.recordVote(context: self.context(userID: "1", isModerator: true))
        }
        await gate.waitUntilStarted()
        await manager.trackDidChange()
        await gate.release()

        let outcome = await creation.value
        XCTAssertEqual(outcome, .pollTrackChanged)
        let chatState = await manager.currentVoteState()
        XCTAssertNil(chatState, "The outgoing track's failed poll must not seed a vote on the new track")
        let active = await manager.isPollInProgress()
        XCTAssertFalse(active)
    }

    func testDisableDuringDefinitivePollFailureDoesNotFallbackOrSkip() async {
        enableFeature(minVotes: 1)
        UserDefaults.standard.set(true, forKey: AppConstants.UserDefaults.voteSkipUsePolls)
        let manager = SkipVoteManager()
        let gate = PollCreationGate(result: .definitiveFailure)
        let skipped = ThreadSafeBox(false)
        let chatMessages = ThreadSafeBox<[String]>([])
        await manager.configure(
            capturePlaybackTarget: {
                PlaybackTarget(trackKey: "target\tartist", revision: 0)
            },
            performSkip: { _ in
                skipped.set(true)
                return true
            },
            sendChatMessage: { message in
                chatMessages.mutate { $0.append(message) }
            },
            createPoll: { _, _ in await gate.create() }
        )

        let creation = Task {
            await manager.recordVote(
                context: self.context(userID: "disabled-create", isModerator: true))
        }
        let createStarted = await waitUntil(timeout: .seconds(1)) {
            await gate.started()
        }
        XCTAssertTrue(createStarted)
        UserDefaults.standard.set(false, forKey: AppConstants.UserDefaults.voteSkipEnabled)
        await gate.release()

        let outcome = await creation.value
        XCTAssertEqual(outcome, .disabled)
        XCTAssertFalse(skipped.value)
        XCTAssertTrue(chatMessages.value.isEmpty)
        let chatState = await manager.currentVoteState()
        let pollActive = await manager.isPollInProgress()
        XCTAssertNil(chatState)
        XCTAssertFalse(pollActive)
    }

    // MARK: - Polls Mode Timeout Fallback

    func testResetDuringPollCreationReturnsSilentCancellationWithoutFallback() async {
        enableFeature(minVotes: 3)
        UserDefaults.standard.set(true, forKey: AppConstants.UserDefaults.voteSkipUsePolls)
        let manager = SkipVoteManager()
        let gate = PollCreationGate(result: .indeterminate)
        let chatMessages = ThreadSafeBox<[String]>([])
        await manager.configure(
            capturePlaybackTarget: { PlaybackTarget(trackKey: "target\tartist", revision: 0) },
            performSkip: nil,
            sendChatMessage: { message in
                chatMessages.mutate { $0.append(message) }
            },
            createPoll: { _, _ in await gate.create() }
        )

        let creation = Task {
            await manager.recordVote(
                context: self.context(userID: "1", isModerator: true))
        }
        await gate.waitUntilStarted()
        await manager.reset()
        await gate.release()

        let outcome = await creation.value
        XCTAssertEqual(outcome, .pollRequestCancelled)
        let active = await manager.isPollInProgress()
        let chatState = await manager.currentVoteState()
        XCTAssertFalse(active)
        XCTAssertNil(chatState)
        XCTAssertTrue(chatMessages.value.isEmpty)
    }

    func testPollTimeoutClearsStuckPoll() async {
        enableFeature(minVotes: 3)
        UserDefaults.standard.set(true, forKey: AppConstants.UserDefaults.voteSkipUsePolls)
        // Inject a sub-100ms fallback timeout so the "poll.end never arrived"
        // path is observed in milliseconds instead of pollDuration plus grace.
        let manager = SkipVoteManager(pollTimeoutDuration: .milliseconds(50))
        await manager.configure(
            capturePlaybackTarget: { PlaybackTarget(trackKey: "target\tartist", revision: 0) },
            performSkip: nil,
            sendChatMessage: nil,
            createPoll: { _, _ in .created(id: "poll-1") }
        )

        let outcome = await manager.recordVote(context: context(userID: "1", isModerator: true))
        XCTAssertEqual(outcome, .pollStarted)
        let activeBefore = await manager.isPollInProgress()
        XCTAssertTrue(activeBefore)

        // EventSub never delivers channel.poll.end (e.g. a WebSocket drop).
        // The fallback timer must clear the latched poll state.
        let cleared = await waitUntil(timeout: .seconds(1)) {
            await manager.isPollInProgress() == false
        }
        XCTAssertTrue(cleared, "A missed poll.end must not latch pollActive forever")

        // The stuck state is gone, so a fresh poll can start.
        let next = await manager.recordVote(context: context(userID: "2", isModerator: true))
        XCTAssertEqual(next, .pollStarted)
    }

    func testPollEndedCancelsTimeoutFallback() async {
        enableFeature(minVotes: 1)
        UserDefaults.standard.set(true, forKey: AppConstants.UserDefaults.voteSkipUsePolls)
        let manager = SkipVoteManager(pollTimeoutDuration: .milliseconds(50))
        await manager.configure(
            capturePlaybackTarget: { PlaybackTarget(trackKey: "target\tartist", revision: 0) },
            performSkip: nil,
            sendChatMessage: nil,
            createPoll: { _, _ in .created(id: "poll-1") }
        )

        _ = await manager.recordVote(context: context(userID: "1", isModerator: true))
        await manager.handlePollEnded(pollID: "poll-1", skipVotes: 0, keepVotes: 1)
        let active = await manager.isPollInProgress()
        XCTAssertFalse(active, "poll.end must clear the active poll")

        // Give the cancelled fallback timer time to have fired if it were still
        // alive; state must stay clear and a fresh poll must start cleanly.
        try? await Task.sleep(for: .milliseconds(120))
        let stillInactive = await manager.isPollInProgress()
        XCTAssertFalse(stillInactive)
        let next = await manager.recordVote(context: context(userID: "2", isModerator: true))
        XCTAssertEqual(next, .pollStarted)
    }

    func testResetClearsActivePoll() async {
        enableFeature(minVotes: 3)
        UserDefaults.standard.set(true, forKey: AppConstants.UserDefaults.voteSkipUsePolls)
        let manager = SkipVoteManager()
        await manager.configure(
            capturePlaybackTarget: { PlaybackTarget(trackKey: "target\tartist", revision: 0) },
            performSkip: nil,
            sendChatMessage: nil,
            createPoll: { _, _ in .created(id: "poll-1") }
        )

        _ = await manager.recordVote(context: context(userID: "1", isModerator: true))
        let activeBefore = await manager.isPollInProgress()
        XCTAssertTrue(activeBefore)

        await manager.reset()
        let activeAfter = await manager.isPollInProgress()
        XCTAssertFalse(activeAfter, "reset (e.g. on disconnect) must clear a latched poll")
        let next = await manager.recordVote(context: context(userID: "2", isModerator: true))
        XCTAssertEqual(next, .pollStarted)
    }

    // MARK: - Vote Event Hook

    func testOnVoteEventFiresStartedWhenSessionOpens() async {
        enableFeature(minVotes: 3)
        let manager = SkipVoteManager()
        let events = ThreadSafeBox<[String]>([])
        await manager.configure(
            capturePlaybackTarget: { PlaybackTarget(trackKey: "target\tartist", revision: 0) },
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
        let events = ThreadSafeBox<[String]>([])
        await manager.configure(
            capturePlaybackTarget: { PlaybackTarget(trackKey: "target\tartist", revision: 0) },
            performSkip: { _ in true },
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
        UserDefaults.standard.set(true, forKey: AppConstants.UserDefaults.voteSkipUsePolls)
        let manager = SkipVoteManager()
        let events = ThreadSafeBox<[String]>([])
        await manager.configure(
            capturePlaybackTarget: { PlaybackTarget(trackKey: "target\tartist", revision: 0) },
            performSkip: { _ in true },
            sendChatMessage: nil,
            createPoll: { _, _ in .created(id: "poll-1") },
            onVoteEvent: { event in
                if case .passed = event { events.mutate { $0.append("passed") } }
            }
        )

        _ = await manager.recordVote(context: context(userID: "1", isModerator: true))
        await manager.handlePollEnded(pollID: "poll-1", skipVotes: 9, keepVotes: 2)
        XCTAssertEqual(events.value, ["passed"])
    }
}
