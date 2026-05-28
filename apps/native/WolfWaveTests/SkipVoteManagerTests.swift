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
        XCTAssertEqual(outcome, .started(count: 1, needed: 3))
        XCTAssertEqual(manager.currentVoteState()?.count, 1)
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
        var skipCount = 0
        manager.performSkip = { skipCount += 1 }

        _ = await manager.recordVote(context: context(userID: "1"))
        _ = await manager.recordVote(context: context(userID: "2"))
        let outcome = await manager.recordVote(context: context(userID: "3"))

        XCTAssertEqual(outcome, .passed(count: 3))
        XCTAssertEqual(skipCount, 1)
        XCTAssertNil(manager.currentVoteState(), "Session should reset after passing")
    }

    func testMinVotesOnePassesImmediately() async {
        enableFeature(minVotes: 1)
        let manager = SkipVoteManager()
        var skipped = false
        manager.performSkip = { skipped = true }

        let outcome = await manager.recordVote(context: context(userID: "1"))
        XCTAssertEqual(outcome, .passed(count: 1))
        XCTAssertTrue(skipped)
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
        var skipCount = 0
        manager.performSkip = { skipCount += 1 }

        _ = await manager.recordVote(context: context(userID: "1"))
        _ = await manager.recordVote(context: context(userID: "1"))
        XCTAssertEqual(skipCount, 0, "Same user voting twice must not pass a 2-vote threshold")
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
        manager.performSkip = {}

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
        enableFeature(minVotes: 5, window: 1)
        let manager = SkipVoteManager()
        var chatMessage: String?
        manager.sendChatMessage = { chatMessage = $0 }

        _ = await manager.recordVote(context: context(userID: "1"))
        XCTAssertNotNil(manager.currentVoteState())

        try await Task.sleep(for: .seconds(2))

        XCTAssertNil(manager.currentVoteState(), "Session should reset after the window expires")
        XCTAssertNotNil(chatMessage)
        XCTAssertTrue(chatMessage?.contains("failed") ?? false)
    }

    // MARK: - Reset

    func testResetClearsSession() async {
        enableFeature(minVotes: 3)
        let manager = SkipVoteManager()
        _ = await manager.recordVote(context: context(userID: "1"))
        manager.reset()
        XCTAssertNil(manager.currentVoteState())
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
        manager.createPoll = { _, _ in true }
        let outcome = await manager.recordVote(context: context(userID: "1", isModerator: true))
        XCTAssertEqual(outcome, .pollStarted)
    }

    func testPollsModeFallsBackToChatTallyOnFailure() async {
        enableFeature(minVotes: 3)
        UserDefaults.standard.set(true, forKey: AppConstants.UserDefaults.voteSkipUsePolls)
        let manager = SkipVoteManager()
        manager.createPoll = { _, _ in false }
        let outcome = await manager.recordVote(context: context(userID: "1", isBroadcaster: true))
        XCTAssertEqual(outcome, .started(count: 1, needed: 3), "Failed poll should fall back to a chat tally")
    }

    func testPollEndedSkipsWhenSkipWins() async {
        enableFeature(minVotes: 3)
        let manager = SkipVoteManager()
        var skipped = false
        manager.performSkip = { skipped = true }
        await manager.handlePollEnded(skipVotes: 5, keepVotes: 2)
        XCTAssertTrue(skipped)
    }

    func testPollEndedDoesNotSkipBelowMinimum() async {
        enableFeature(minVotes: 10)
        let manager = SkipVoteManager()
        var skipped = false
        manager.performSkip = { skipped = true }
        await manager.handlePollEnded(skipVotes: 5, keepVotes: 2)
        XCTAssertFalse(skipped, "Skip wins but is below the minimum vote threshold")
    }

    func testPollEndedDoesNotSkipWhenKeepWins() async {
        enableFeature(minVotes: 1)
        let manager = SkipVoteManager()
        var skipped = false
        manager.performSkip = { skipped = true }
        await manager.handlePollEnded(skipVotes: 2, keepVotes: 9)
        XCTAssertFalse(skipped)
    }
}
