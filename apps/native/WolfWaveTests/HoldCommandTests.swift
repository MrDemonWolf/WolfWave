//
//  HoldCommandTests.swift
//  WolfWave
//
//  Created by Nathanial Henniges on 2026-05-27.
//  Copyright © 2026 MrDemonWolf, Inc. All rights reserved.
//

import XCTest

@testable import WolfWave

@MainActor
final class HoldCommandTests: XCTestCase {

    // MARK: - Setup

    override func setUp() {
        super.setUp()
        UserDefaults.standard.removeObject(forKey: AppConstants.UserDefaults.songRequestHoldEnabled)
    }

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: AppConstants.UserDefaults.songRequestHoldEnabled)
        super.tearDown()
    }

    // MARK: - Helpers

    private func privilegedContext(
        broadcaster: Bool = true,
        moderator: Bool = false
    ) -> BotCommandContext {
        BotCommandContext(
            userID: "1", username: "streamer",
            isModerator: moderator, isBroadcaster: broadcaster,
            isSubscriber: false, isVIP: false, messageID: "m"
        )
    }

    private func viewerContext() -> BotCommandContext {
        BotCommandContext(
            userID: "2", username: "viewer",
            isModerator: false, isBroadcaster: false,
            isSubscriber: false, isVIP: false, messageID: "m"
        )
    }

    private func makeService() -> SongRequestService {
        SongRequestService(
            queue: SongRequestQueue(),
            blocklist: SongBlocklist(storage: InMemoryBlocklistStorage()),
            musicController: MockAppleMusicController()
        )
    }

    // MARK: - Metadata

    func testTriggers() {
        let command = HoldCommand()
        XCTAssertEqual(command.triggers, ["!hold", "!resume", "!unhold"])
    }

    func testDescriptionMentionsPrivilegeGate() {
        let command = HoldCommand()
        XCTAssertTrue(command.description.lowercased().contains("mod"))
    }

    func testCooldowns() {
        let command = HoldCommand()
        XCTAssertEqual(command.globalCooldown, 3.0)
        XCTAssertEqual(command.userCooldown, 3.0)
    }

    func testAlwaysEnabledByDefault() {
        let command = HoldCommand()
        XCTAssertNil(command.enabledKey)
        XCTAssertTrue(command.isCommandEnabled)
    }

    func testNoAliasSupport() {
        let command = HoldCommand()
        XCTAssertNil(command.aliasesKey)
        XCTAssertEqual(command.allTriggers, command.triggers)
    }

    func testSyncExecuteReturnsNil() {
        let command = HoldCommand()
        XCTAssertNil(command.execute(message: "!hold"))
    }

    // MARK: - Privilege Gate (silent ignore)

    func testNonPrivilegedHoldIsSilent() {
        let command = HoldCommand()
        command.songRequestService = { self.makeService() }

        var replyCalled = false
        command.execute(message: "!hold", context: viewerContext()) { _ in replyCalled = true }
        XCTAssertFalse(replyCalled)
    }

    func testNonPrivilegedResumeIsSilent() {
        let command = HoldCommand()
        command.songRequestService = { self.makeService() }

        var replyCalled = false
        command.execute(message: "!resume", context: viewerContext()) { _ in replyCalled = true }
        XCTAssertFalse(replyCalled)
    }

    func testNonPrivilegedUnholdIsSilent() {
        let command = HoldCommand()
        command.songRequestService = { self.makeService() }

        var replyCalled = false
        command.execute(message: "!unhold", context: viewerContext()) { _ in replyCalled = true }
        XCTAssertFalse(replyCalled)
    }

    func testSubscriberWithoutModBadgeIsSilent() {
        let command = HoldCommand()
        command.songRequestService = { self.makeService() }

        let subscriber = BotCommandContext(
            userID: "3", username: "fan",
            isModerator: false, isBroadcaster: false,
            isSubscriber: true, isVIP: true, messageID: "m"
        )

        var replyCalled = false
        command.execute(message: "!hold", context: subscriber) { _ in replyCalled = true }
        XCTAssertFalse(replyCalled)
    }

    // MARK: - Hold Path (privileged)

    func testBroadcasterHoldEnablesHoldAndReplies() async {
        let command = HoldCommand()
        let service = makeService()
        command.songRequestService = { service }

        let reply = await captureReply { done in
            command.execute(message: "!hold", context: privilegedContext()) { done($0) }
        }

        XCTAssertTrue(service.isHoldEnabled)
        XCTAssertTrue(reply.contains("on hold"))
        XCTAssertTrue(reply.contains("!resume"))
    }

    func testModeratorCanHold() async {
        let command = HoldCommand()
        let service = makeService()
        command.songRequestService = { service }

        let reply = await captureReply { done in
            command.execute(
                message: "!hold",
                context: privilegedContext(broadcaster: false, moderator: true)
            ) { done($0) }
        }

        XCTAssertTrue(service.isHoldEnabled)
        XCTAssertFalse(reply.isEmpty)
    }

    // MARK: - Resume Path (privileged)

    func testResumeDisablesHoldAndReplies() async {
        UserDefaults.standard.set(true, forKey: AppConstants.UserDefaults.songRequestHoldEnabled)
        let command = HoldCommand()
        let service = makeService()
        command.songRequestService = { service }

        let reply = await captureReply { done in
            command.execute(message: "!resume", context: privilegedContext()) { done($0) }
        }

        XCTAssertFalse(service.isHoldEnabled)
        XCTAssertTrue(reply.lowercased().contains("resumed"))
    }

    func testUnholdAliasAlsoResumes() async {
        UserDefaults.standard.set(true, forKey: AppConstants.UserDefaults.songRequestHoldEnabled)
        let command = HoldCommand()
        let service = makeService()
        command.songRequestService = { service }

        let reply = await captureReply { done in
            command.execute(message: "!unhold", context: privilegedContext()) { done($0) }
        }

        XCTAssertFalse(service.isHoldEnabled)
        XCTAssertTrue(reply.lowercased().contains("resumed"))
    }

    // MARK: - Trigger Parsing

    func testTriggerIsCaseInsensitive() async {
        let command = HoldCommand()
        let service = makeService()
        command.songRequestService = { service }

        _ = await captureReply { done in
            command.execute(message: "!HOLD", context: privilegedContext()) { done($0) }
        }

        XCTAssertTrue(service.isHoldEnabled, "Uppercase !HOLD should still enable hold mode")
    }

    func testTrailingArgumentsIgnored() async {
        let command = HoldCommand()
        let service = makeService()
        command.songRequestService = { service }

        _ = await captureReply { done in
            command.execute(message: "!hold for a sec", context: privilegedContext()) { done($0) }
        }

        XCTAssertTrue(service.isHoldEnabled)
    }

    // MARK: - Missing Service

    func testMissingServiceCallbackResultsInSilentNoOp() {
        let command = HoldCommand()
        command.songRequestService = { nil }

        var replyCalled = false
        command.execute(message: "!hold", context: privilegedContext()) { _ in replyCalled = true }
        XCTAssertFalse(replyCalled)
    }

    // MARK: - Reply Capture

    /// Waits for an async reply callback delivered via `Task` inside a command's `execute`.
    private func captureReply(
        timeout: TimeInterval = 2.0,
        _ trigger: (@escaping (String) -> Void) -> Void
    ) async -> String {
        await withCheckedContinuation { continuation in
            let box = ReplyBox()
            trigger { value in
                guard box.fulfill() else { return }
                continuation.resume(returning: value)
            }
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(timeout))
                guard box.fulfill() else { return }
                continuation.resume(returning: "")
            }
        }
    }
}

// MARK: - ReplyBox

/// Ensures the continuation in `captureReply` resumes exactly once.
private final class ReplyBox {
    private var done = false
    private let lock = NSLock()

    func fulfill() -> Bool {
        lock.lock(); defer { lock.unlock() }
        if done { return false }
        done = true
        return true
    }
}
