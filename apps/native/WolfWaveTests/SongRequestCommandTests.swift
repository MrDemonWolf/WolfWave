//
//  SongRequestCommandTests.swift
//  WolfWave
//
//  Created by Nathanial Henniges on 2026-04-15.
//  Copyright © 2026 MrDemonWolf, Inc. All rights reserved.
//

import XCTest

@testable import WolfWave

@MainActor
final class SongRequestCommandTests: WolfWaveTestCase {

    override func setUp() {
        super.setUp()
        resetAllSettings()
    }

    override func tearDown() {
        resetAllSettings()
        super.tearDown()
    }

    // MARK: - SongRequestCommand Triggers

    func testSongRequestCommandTriggers() {
        let command = SongRequestCommand()
        XCTAssertEqual(command.triggers, ["!sr", "!request", "!songrequest"])
    }

    func testSongRequestCommandDefaultEnabled() {
        let command = SongRequestCommand()
        XCTAssertTrue(command.isCommandEnabled)
    }

    func testSongRequestCommandDisabled() {
        UserDefaults.standard.set(false, forKey: AppConstants.UserDefaults.srCommandEnabled)
        let command = SongRequestCommand()
        XCTAssertFalse(command.isCommandEnabled)
    }

    func testSongRequestCommandSyncExecuteReturnsNil() {
        let command = SongRequestCommand()
        // AsyncBotCommand sync execute should return nil
        XCTAssertNil(command.execute(message: "!sr test"))
    }

    // MARK: - QueueCommand Triggers

    func testQueueCommandTriggers() {
        let command = QueueCommand()
        XCTAssertEqual(command.triggers, ["!queue", "!songlist", "!requests"])
    }

    func testQueueCommandEmptyResponse() {
        let command = QueueCommand()
        let queue = SongRequestQueue()
        command.getQueue = { queue }
        let response = command.execute(message: "!queue")
        XCTAssertEqual(response, "Queue is empty. Request a song with !sr <song name>")
    }

    // MARK: - SkipCommand

    func testSkipCommandTriggers() {
        let command = SkipCommand()
        XCTAssertEqual(command.triggers, ["!skip", "!next"])
    }

    // MARK: - ClearQueueCommand

    func testClearQueueCommandTriggers() {
        let command = ClearQueueCommand()
        XCTAssertEqual(command.triggers, ["!clearqueue", "!cq"])
    }

    // MARK: - MyQueueCommand

    func testMyQueueCommandTriggers() {
        let command = MyQueueCommand()
        XCTAssertEqual(command.triggers, ["!myqueue", "!mysongs"])
    }

    // MARK: - Custom Aliases

    func testCustomAliasesAdded() {
        UserDefaults.standard.set("play, add", forKey: AppConstants.UserDefaults.srCommandAliases)
        let command = SongRequestCommand()
        let allTriggers = command.allTriggers
        XCTAssertTrue(allTriggers.contains("!play"))
        XCTAssertTrue(allTriggers.contains("!add"))
        // Original triggers still present
        XCTAssertTrue(allTriggers.contains("!sr"))
        XCTAssertTrue(allTriggers.contains("!request"))
    }

    func testCustomAliasesWithBangPrefix() {
        UserDefaults.standard.set("!play", forKey: AppConstants.UserDefaults.srCommandAliases)
        let command = SongRequestCommand()
        let allTriggers = command.allTriggers
        XCTAssertTrue(allTriggers.contains("!play"))
        // Should not double-prefix
        XCTAssertFalse(allTriggers.contains("!!play"))
    }

    func testEmptyAliases() {
        UserDefaults.standard.set("", forKey: AppConstants.UserDefaults.srCommandAliases)
        let command = SongRequestCommand()
        // Should just have original triggers
        XCTAssertEqual(command.allTriggers.count, command.triggers.count)
    }

    // MARK: - Enable/Disable via Dispatcher

    func testDispatcherSkipsDisabledCommand() {
        UserDefaults.standard.set(false, forKey: AppConstants.UserDefaults.queueCommandEnabled)
        let dispatcher = BotCommandDispatcher()
        let result = dispatcher.processMessage("!queue")
        XCTAssertNil(result)
    }

    // MARK: - BotCommandContext

    func testContextPrivileged() {
        let modContext = BotCommandContext(
            userID: "123", username: "moduser",
            isModerator: true, isBroadcaster: false,
            isSubscriber: false, isVIP: false, messageID: "msg1"
        )
        XCTAssertTrue(modContext.isPrivileged)

        let broadcasterContext = BotCommandContext(
            userID: "456", username: "streamer",
            isModerator: false, isBroadcaster: true,
            isSubscriber: false, isVIP: false, messageID: "msg2"
        )
        XCTAssertTrue(broadcasterContext.isPrivileged)

        let viewerContext = BotCommandContext(
            userID: "789", username: "viewer",
            isModerator: false, isBroadcaster: false,
            isSubscriber: true, isVIP: false, messageID: "msg3"
        )
        XCTAssertFalse(viewerContext.isPrivileged)
    }

    // MARK: - Link Detection

    func testSpotifyLinkDetection() {
        XCTAssertTrue(LinkResolverService.isSpotifyLink("https://open.spotify.com/track/abc123"))
        XCTAssertFalse(LinkResolverService.isSpotifyLink("bohemian rhapsody"))
        XCTAssertFalse(LinkResolverService.isSpotifyLink("https://youtube.com/watch?v=abc"))
    }

    func testYouTubeLinkDetection() {
        XCTAssertTrue(LinkResolverService.isYouTubeLink("https://youtube.com/watch?v=abc123"))
        XCTAssertTrue(LinkResolverService.isYouTubeLink("https://youtu.be/abc123"))
        XCTAssertTrue(LinkResolverService.isYouTubeLink("https://music.youtube.com/watch?v=abc"))
        XCTAssertFalse(LinkResolverService.isYouTubeLink("bohemian rhapsody"))
    }

    func testAppleMusicLinkDetection() {
        XCTAssertTrue(LinkResolverService.isAppleMusicLink("https://music.apple.com/us/album/song/123"))
        XCTAssertFalse(LinkResolverService.isAppleMusicLink("bohemian rhapsody"))
        XCTAssertFalse(LinkResolverService.isAppleMusicLink("https://open.spotify.com/track/abc"))
    }

    func testMusicLinkDetection() {
        XCTAssertTrue(LinkResolverService.isMusicLink("https://open.spotify.com/track/abc123"))
        XCTAssertTrue(LinkResolverService.isMusicLink("https://youtu.be/abc123"))
        XCTAssertTrue(LinkResolverService.isMusicLink("https://music.apple.com/us/album/song/123"))
        XCTAssertFalse(LinkResolverService.isMusicLink("just a song name"))
    }

    func testExtractURL() {
        XCTAssertEqual(
            LinkResolverService.extractURL(from: "!sr https://open.spotify.com/track/abc123"),
            "https://open.spotify.com/track/abc123"
        )
        XCTAssertNil(LinkResolverService.extractURL(from: "!sr bohemian rhapsody"))
    }

    // MARK: - Blocklist

    func testBlocklistAddAndCheck() async {
        let blocklist = SongBlocklist(storage: InMemoryBlocklistStorage())
        await blocklist.clearAll()

        let songItem = BlocklistItem(value: "Bad Song", type: .song)
        await blocklist.add(songItem)
        let blocked1 = await blocklist.isBlocked(title: "Bad Song", artist: "Any Artist")
        let blocked2 = await blocklist.isBlocked(title: "bad song", artist: "Any Artist")
        let blocked3 = await blocklist.isBlocked(title: "Good Song", artist: "Any Artist")
        XCTAssertTrue(blocked1)
        XCTAssertTrue(blocked2)
        XCTAssertFalse(blocked3)

        let artistItem = BlocklistItem(value: "Bad Artist", type: .artist)
        await blocklist.add(artistItem)
        let blocked4 = await blocklist.isBlocked(title: "Any Song", artist: "Bad Artist")
        let blocked5 = await blocklist.isBlocked(title: "Any Song", artist: "bad artist")
        let blocked6 = await blocklist.isBlocked(title: "Any Song", artist: "Good Artist")
        XCTAssertTrue(blocked4)
        XCTAssertTrue(blocked5)
        XCTAssertFalse(blocked6)

        await blocklist.clearAll()
    }

    func testBlocklistRemove() async {
        let blocklist = SongBlocklist(storage: InMemoryBlocklistStorage())
        await blocklist.clearAll()

        let item = BlocklistItem(value: "Remove Me", type: .song)
        await blocklist.add(item)
        let before = await blocklist.isBlocked(title: "Remove Me", artist: "")
        XCTAssertTrue(before)

        await blocklist.remove(id: item.id)
        let after = await blocklist.isBlocked(title: "Remove Me", artist: "")
        XCTAssertFalse(after)

        await blocklist.clearAll()
    }

    func testBlocklistNoDuplicates() async {
        let blocklist = SongBlocklist(storage: InMemoryBlocklistStorage())
        await blocklist.clearAll()

        let item1 = BlocklistItem(value: "Duplicate", type: .song)
        let item2 = BlocklistItem(value: "duplicate", type: .song)
        await blocklist.add(item1)
        await blocklist.add(item2) // Should be ignored (case-insensitive)
        let count = await blocklist.allEntries.count
        XCTAssertEqual(count, 1)

        await blocklist.clearAll()
    }

    // MARK: - QueueCommand Output

    func testQueueCommandWithNowPlayingAndItems() {
        let command = QueueCommand()
        let queue = SongRequestQueue()
        command.getQueue = { queue }

        // Set up: dequeue one item as now-playing, leave one in queue
        queue.add(SongRequestItem(title: "Playing Song", artist: "Artist A", requesterUsername: "viewer1"))
        queue.add(SongRequestItem(title: "Next Song", artist: "Artist B", requesterUsername: "viewer2"))
        queue.dequeue() // moves "Playing Song" to nowPlaying

        let response = command.execute(message: "!queue")
        XCTAssertNotNil(response)
        XCTAssertTrue(response!.contains("Now playing:"))
        XCTAssertTrue(response!.contains("Playing Song"))
        XCTAssertTrue(response!.contains("Next Song"))
        XCTAssertTrue(response!.contains("Queue (1):"))
    }

    func testQueueCommandShowsUpToFiveItems() {
        let command = QueueCommand()
        let queue = SongRequestQueue()
        command.getQueue = { queue }
        UserDefaults.standard.set(10, forKey: AppConstants.UserDefaults.songRequestMaxQueueSize)
        UserDefaults.standard.set(10, forKey: AppConstants.UserDefaults.songRequestPerUserLimit)

        for i in 1...7 {
            queue.add(SongRequestItem(title: "Song \(i)", artist: "Artist", requesterUsername: "user\(i)"))
        }

        let response = command.execute(message: "!queue")
        XCTAssertNotNil(response)
        XCTAssertTrue(response!.contains("...and 2 more"))

        UserDefaults.standard.removeObject(forKey: AppConstants.UserDefaults.songRequestMaxQueueSize)
        UserDefaults.standard.removeObject(forKey: AppConstants.UserDefaults.songRequestPerUserLimit)
    }

    func testQueueCommandExactlyFiveItemsNoOverflow() {
        let command = QueueCommand()
        let queue = SongRequestQueue()
        command.getQueue = { queue }
        UserDefaults.standard.set(10, forKey: AppConstants.UserDefaults.songRequestMaxQueueSize)
        UserDefaults.standard.set(10, forKey: AppConstants.UserDefaults.songRequestPerUserLimit)

        for i in 1...5 {
            queue.add(SongRequestItem(title: "Song \(i)", artist: "Artist", requesterUsername: "user\(i)"))
        }

        let response = command.execute(message: "!queue")
        XCTAssertNotNil(response)
        XCTAssertFalse(response!.contains("more"))

        UserDefaults.standard.removeObject(forKey: AppConstants.UserDefaults.songRequestMaxQueueSize)
        UserDefaults.standard.removeObject(forKey: AppConstants.UserDefaults.songRequestPerUserLimit)
    }

    // MARK: - MyQueueCommand Output

    func testMyQueueCommandWithItems() {
        let command = MyQueueCommand()
        let queue = SongRequestQueue()
        command.getQueue = { queue }
        UserDefaults.standard.set(10, forKey: AppConstants.UserDefaults.songRequestPerUserLimit)

        queue.add(SongRequestItem(title: "My Song 1", artist: "Artist", requesterUsername: "testuser"))
        queue.add(SongRequestItem(title: "Other Song", artist: "Artist", requesterUsername: "other"))
        queue.add(SongRequestItem(title: "My Song 2", artist: "Artist2", requesterUsername: "testuser"))

        let context = BotCommandContext(
            userID: "999", username: "testuser",
            isModerator: false, isBroadcaster: false,
            isSubscriber: false, isVIP: false, messageID: "m1"
        )

        var reply: String?
        command.execute(message: "!myqueue", context: context) { reply = $0 }

        XCTAssertNotNil(reply)
        XCTAssertTrue(reply!.contains("My Song 1"))
        XCTAssertTrue(reply!.contains("My Song 2"))
        XCTAssertFalse(reply!.contains("Other Song"))
        XCTAssertTrue(reply!.contains("#1"))
        XCTAssertTrue(reply!.contains("#3"))

        UserDefaults.standard.removeObject(forKey: AppConstants.UserDefaults.songRequestPerUserLimit)
    }

    func testMyQueueCommandNoItemsPrompt() {
        let command = MyQueueCommand()
        let queue = SongRequestQueue()
        command.getQueue = { queue }

        let context = BotCommandContext(
            userID: "999", username: "emptyuser",
            isModerator: false, isBroadcaster: false,
            isSubscriber: false, isVIP: false, messageID: "m2"
        )

        var reply: String?
        command.execute(message: "!myqueue", context: context) { reply = $0 }

        XCTAssertNotNil(reply)
        XCTAssertTrue(reply!.contains("!sr"))
    }

    // MARK: - Privilege Checks (silent ignore)

    func testSkipCommandSilentlyIgnoresNonPrivileged() {
        let command = SkipCommand()
        var replyCalled = false
        command.execute(
            message: "!skip",
            context: BotCommandContext(
                userID: "1", username: "viewer",
                isModerator: false, isBroadcaster: false,
                isSubscriber: false, isVIP: false, messageID: "m"
            )
        ) { _ in replyCalled = true }
        XCTAssertFalse(replyCalled)
    }

    func testClearQueueCommandSilentlyIgnoresNonPrivileged() {
        let command = ClearQueueCommand()
        var replyCalled = false
        command.execute(
            message: "!clearqueue",
            context: BotCommandContext(
                userID: "1", username: "viewer",
                isModerator: false, isBroadcaster: false,
                isSubscriber: false, isVIP: false, messageID: "m"
            )
        ) { _ in replyCalled = true }
        XCTAssertFalse(replyCalled)
    }
}
