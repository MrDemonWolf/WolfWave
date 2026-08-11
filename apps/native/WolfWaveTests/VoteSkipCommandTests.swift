//
//  VoteSkipCommandTests.swift
//  WolfWave
//
//  Created by Nathanial Henniges on 2026-05-22.
//  Copyright © 2026 MrDemonWolf, Inc. All rights reserved.
//

import XCTest

@testable import WolfWave

@MainActor
final class VoteSkipCommandTests: WolfWaveTestCase {

    override func setUp() {
        super.setUp()
        resetAllSettings()
    }

    override func tearDown() {
        resetAllSettings()
        super.tearDown()
    }

    private func context(userID: String) -> BotCommandContext {
        BotCommandContext(
            userID: userID, username: "user\(userID)",
            isModerator: false, isBroadcaster: false,
            isSubscriber: false, isVIP: false, messageID: "m\(userID)"
        )
    }

    // MARK: - Triggers & Configuration

    func testTriggers() {
        XCTAssertEqual(VoteSkipCommand().triggers, ["!voteskip", "!vs"])
    }

    func testZeroCooldowns() {
        let command = VoteSkipCommand()
        XCTAssertEqual(command.globalCooldown, 0)
        XCTAssertEqual(command.userCooldown, 0)
    }

    func testDefaultEnabled() {
        XCTAssertTrue(VoteSkipCommand().isCommandEnabled)
    }

    func testDisabledViaUserDefaults() {
        UserDefaults.standard.set(false, forKey: AppConstants.UserDefaults.voteSkipCommandEnabled)
        XCTAssertFalse(VoteSkipCommand().isCommandEnabled)
    }

    func testCustomAliasesAppendToTriggers() {
        UserDefaults.standard.set("skipvote, sv", forKey: AppConstants.UserDefaults.voteSkipCommandAliases)
        let triggers = VoteSkipCommand().allTriggers
        XCTAssertTrue(triggers.contains("!skipvote"))
        XCTAssertTrue(triggers.contains("!sv"))
    }

    func testSyncExecuteReturnsNil() {
        XCTAssertNil(VoteSkipCommand().execute(message: "!voteskip"))
    }

    // MARK: - Reply Formatting

    func testFormatDisabledIsSilent() {
        XCTAssertNil(VoteSkipCommand.format(.pollRequestCancelled))
        XCTAssertNil(VoteSkipCommand.format(.disabled))
    }

    func testFormatStartedAndCountedShowProgress() {
        XCTAssertEqual(VoteSkipCommand.format(.started(count: 1, needed: 3))?.contains("1/3"), true)
        XCTAssertEqual(VoteSkipCommand.format(.counted(count: 2, needed: 3))?.contains("2/3"), true)
    }

    func testFormatPassedAndCooldown() {
        XCTAssertEqual(VoteSkipCommand.format(.passed(count: 3))?.isEmpty, false)
        XCTAssertEqual(VoteSkipCommand.format(.onCooldown(remaining: 12))?.contains("12"), true)
    }

    func testStaleTargetRepliesDoNotInviteUnsafeRetry() {
        XCTAssertEqual(
            VoteSkipCommand.format(.pollTrackChanged),
            "🎵 The song changed while Twitch handled the poll. It won't skip the new song.")
        XCTAssertEqual(
            VoteSkipCommand.format(.skipUnavailable),
            "🎵 The voted song changed or couldn't be skipped. The current song was left alone.")
    }

    func testFormatNonDisabledOutcomesProduceReplies() {
        let outcomes: [SkipVoteManager.VoteOutcome] = [
            .subscriberOnly,
            .alreadyVoted(count: 1, needed: 3),
            .pollStarted,
            .pollInProgress,
            .pollTrackChanged,
            .pollNotAllowed,
            .pollStatusUnknown,
            .playbackUnavailable,
            .skipUnavailable,
        ]
        for outcome in outcomes {
            XCTAssertNotNil(VoteSkipCommand.format(outcome), "\(outcome) should produce a reply")
        }
    }

    // MARK: - Execution

    func testExecuteRepliesWhenVotePasses() async {
        UserDefaults.standard.set(true, forKey: AppConstants.UserDefaults.voteSkipEnabled)
        UserDefaults.standard.set(1, forKey: AppConstants.UserDefaults.voteSkipMinVotes)

        let manager = SkipVoteManager()
        await manager.configure(
            capturePlaybackTarget: {
                PlaybackTarget(trackKey: "Current\tArtist", revision: 0)
            },
            performSkip: { _ in true },
            sendChatMessage: nil,
            createPoll: nil)
        let command = VoteSkipCommand()
        command.skipVoteManager = { manager }

        let response = await command.execute(message: "!voteskip", context: context(userID: "1"))
        XCTAssertFalse(response?.isEmpty ?? true)
    }

    func testExecuteStaysSilentWhenFeatureDisabled() async {
        // voteSkipEnabled is unset → feature off → manager returns .disabled → no reply.
        let manager = SkipVoteManager()
        let command = VoteSkipCommand()
        command.skipVoteManager = { manager }

        let response = await command.execute(message: "!voteskip", context: context(userID: "1"))
        XCTAssertNil(response)
    }
}
