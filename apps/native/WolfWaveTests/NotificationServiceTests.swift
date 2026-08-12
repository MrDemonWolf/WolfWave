//
//  NotificationServiceTests.swift
//  WolfWave
//
//  Created by Nathanial Henniges on 2026-05-22.
//  Copyright © 2026 MrDemonWolf, Inc. All rights reserved.
//

import Testing
import Foundation
import UserNotifications
@testable import WolfWave

/// Test suite verifying `NotificationService` content building and identifiers.
@MainActor
@Suite("Notification Service Tests")
struct NotificationServiceTests {

    // MARK: - Song Change Content

    @Test("Song change content uses Now Playing title, track subtitle, artist + album body")
    func testSongChangeContentFull() async throws {
        let content = NotificationService.makeSongChangeContent(
            track: "Blinding Lights",
            artist: "The Weeknd",
            album: "After Hours"
        )
        #expect(content.title == "Now Playing")
        #expect(content.subtitle == "Blinding Lights")
        #expect(content.body == "The Weeknd · After Hours")
    }

    @Test("Song change content falls back to artist only when album is empty")
    func testSongChangeContentNoAlbum() async throws {
        let content = NotificationService.makeSongChangeContent(
            track: "Some Song",
            artist: "Some Artist",
            album: ""
        )
        #expect(content.title == "Now Playing")
        #expect(content.subtitle == "Some Song")
        #expect(content.body == "Some Artist")
    }

    @Test("Song change content falls back to album only when artist is empty")
    func testSongChangeContentNoArtist() async throws {
        let content = NotificationService.makeSongChangeContent(
            track: "Some Song",
            artist: "",
            album: "Some Album"
        )
        #expect(content.body == "Some Album")
    }

    @Test("Song change content uses an Unknown song subtitle when the track is empty")
    func testSongChangeContentEmptyTrack() async throws {
        let content = NotificationService.makeSongChangeContent(
            track: "",
            artist: "Artist",
            album: "Album"
        )
        #expect(content.title == "Now Playing")
        #expect(content.subtitle == "Unknown song")
    }

    @Test("Song change content trims surrounding whitespace")
    func testSongChangeContentTrimsWhitespace() async throws {
        let content = NotificationService.makeSongChangeContent(
            track: "  Track  ",
            artist: "  Artist  ",
            album: "  Album  "
        )
        #expect(content.subtitle == "Track")
        #expect(content.body == "Artist · Album")
    }

    @Test("Song change content preserves unusual characters")
    func testSongChangeContentUnusualCharacters() async throws {
        let content = NotificationService.makeSongChangeContent(
            track: "Café naïve 🎧",
            artist: "Sigur Rós",
            album: "( )"
        )
        #expect(content.subtitle == "Café naïve 🎧")
        #expect(content.body == "Sigur Rós · ( )")
    }

    @Test("Song change content carries no sound")
    func testSongChangeContentSilent() async throws {
        let content = NotificationService.makeSongChangeContent(
            track: "Track",
            artist: "Artist",
            album: "Album"
        )
        #expect(content.sound == nil)
    }

    // MARK: - Skip Vote Started Content

    @Test("Skip vote started (chat tally) shows the vote threshold in the body")
    func testSkipVoteStartedChat() async throws {
        let content = NotificationService.makeSkipVoteStartedContent(
            track: "Blinding Lights",
            artist: "The Weeknd",
            votesNeeded: 3,
            viaPoll: false
        )
        #expect(content.title == "Skip Vote Started")
        #expect(content.subtitle == "Blinding Lights · The Weeknd")
        #expect(content.body == "Chat is voting to skip. 3 votes needed.")
    }

    @Test("Skip vote started (poll mode) points at the Twitch poll widget")
    func testSkipVoteStartedPoll() async throws {
        let content = NotificationService.makeSkipVoteStartedContent(
            track: "Some Song",
            artist: "Some Artist",
            votesNeeded: 0,
            viaPoll: true
        )
        #expect(content.title == "Skip Vote Started")
        #expect(content.body == "A Twitch poll is open. Viewers vote in the poll widget.")
    }

    @Test("Skip vote started clamps a zero/negative threshold to at least 1")
    func testSkipVoteStartedClampsThreshold() async throws {
        let content = NotificationService.makeSkipVoteStartedContent(
            track: "T", artist: "A", votesNeeded: 0, viaPoll: false)
        #expect(content.body == "Chat is voting to skip. 1 vote needed.")
    }

    @Test("Skip vote started pluralizes the vote count above 1")
    func testSkipVoteStartedPluralizes() async throws {
        let content = NotificationService.makeSkipVoteStartedContent(
            track: "T", artist: "A", votesNeeded: 3, viaPoll: false)
        #expect(content.body == "Chat is voting to skip. 3 votes needed.")
    }

    @Test("Skip vote started is silent")
    func testSkipVoteStartedSilent() async throws {
        let content = NotificationService.makeSkipVoteStartedContent(
            track: "T", artist: "A", votesNeeded: 2, viaPoll: false)
        #expect(content.sound == nil)
    }

    @Test("Skip vote started tolerates an empty track or artist")
    func testSkipVoteStartedEmptyFields() async throws {
        let onlyArtist = NotificationService.makeSkipVoteStartedContent(
            track: "", artist: "Artist", votesNeeded: 2, viaPoll: false)
        #expect(onlyArtist.subtitle == "Artist")

        let onlyTrack = NotificationService.makeSkipVoteStartedContent(
            track: "Track", artist: "", votesNeeded: 2, viaPoll: false)
        #expect(onlyTrack.subtitle == "Track")
    }

    // MARK: - Skip Vote Passed Content

    @Test("Skip vote passed names the skipped track and plays the default sound")
    func testSkipVotePassed() async throws {
        let content = NotificationService.makeSkipVotePassedContent(
            track: "Blinding Lights",
            artist: "The Weeknd"
        )
        #expect(content.title == "Skip Vote Passed")
        #expect(content.subtitle == "Skipping Blinding Lights · The Weeknd")
        #expect(content.body == "Chat voted to skip the current song.")
        #expect(content.sound == .default)
    }

    @Test("Skip vote passed leaves the subtitle empty when no track is known")
    func testSkipVotePassedNoTrack() async throws {
        let content = NotificationService.makeSkipVotePassedContent(track: "", artist: "")
        #expect(content.subtitle == "")
        #expect(content.sound == .default)
    }

    // MARK: - Twitch Re-auth Content

    @Test("Twitch re-auth content names the expired session and plays the default sound")
    func testTwitchReauthContent() async throws {
        let content = NotificationService.makeTwitchReauthContent()
        #expect(content.title == "Twitch Authentication Expired")
        #expect(content.body == "Your Twitch session has expired. Please re-authorize in Settings.")
        #expect(content.sound == .default)
    }

    @Test("Twitch re-auth requests reuse one stable identifier")
    func testTwitchReauthRequestReusesIdentifier() async throws {
        let first = NotificationService.makeRequest(
            content: NotificationService.makeTwitchReauthContent(),
            identifier: AppConstants.UserNotification.twitchReauthIdentifier
        )
        let second = NotificationService.makeRequest(
            content: NotificationService.makeTwitchReauthContent(),
            identifier: AppConstants.UserNotification.twitchReauthIdentifier
        )
        #expect(first.identifier == AppConstants.UserNotification.twitchReauthIdentifier)
        #expect(first.identifier == second.identifier)
    }

    // MARK: - Identifiers

    @Test("Notification identifiers are stable and non-empty")
    func testIdentifiers() async throws {
        #expect(AppConstants.UserNotification.songChangeIdentifier
            == "com.mrdemonwolf.wolfwave.notification.songChange")
        #expect(AppConstants.UserNotification.skipVoteStartedIdentifier
            == "com.mrdemonwolf.wolfwave.notification.skipVoteStarted")
        #expect(AppConstants.UserNotification.skipVotePassedIdentifier
            == "com.mrdemonwolf.wolfwave.notification.skipVotePassed")
        #expect(AppConstants.UserNotification.twitchReauthIdentifier
            == "com.mrdemonwolf.wolfwave.notification.twitchReauth")
        // All request identities stay distinct; lifecycle cleanup is explicit.
        let ids = Set([
            AppConstants.UserNotification.songChangeIdentifier,
            AppConstants.UserNotification.skipVoteStartedIdentifier,
            AppConstants.UserNotification.skipVotePassedIdentifier,
            AppConstants.UserNotification.twitchReauthIdentifier
        ])
        #expect(ids.count == 4)
    }

    // MARK: - Request Dedup (stable identifiers)

    @Test("Song-change requests reuse one stable identifier")
    func testSongChangeRequestReusesIdentifier() async throws {
        let first = NotificationService.makeRequest(
            content: NotificationService.makeSongChangeContent(
                track: "Track One", artist: "Artist", album: "Album"),
            identifier: AppConstants.UserNotification.songChangeIdentifier
        )
        let second = NotificationService.makeRequest(
            content: NotificationService.makeSongChangeContent(
                track: "Track Two", artist: "Artist", album: "Album"),
            identifier: AppConstants.UserNotification.songChangeIdentifier
        )

        #expect(first.identifier == AppConstants.UserNotification.songChangeIdentifier)
        #expect(first.identifier == second.identifier)
    }

    @Test("Skip-vote-started requests reuse one stable identifier")
    func testSkipVoteStartedRequestReusesIdentifier() async throws {
        let first = NotificationService.makeRequest(
            content: NotificationService.makeSkipVoteStartedContent(
                track: "Track", artist: "Artist", votesNeeded: 3, viaPoll: false),
            identifier: AppConstants.UserNotification.skipVoteStartedIdentifier
        )
        let second = NotificationService.makeRequest(
            content: NotificationService.makeSkipVoteStartedContent(
                track: "Track", artist: "Artist", votesNeeded: 5, viaPoll: false),
            identifier: AppConstants.UserNotification.skipVoteStartedIdentifier
        )

        #expect(first.identifier == AppConstants.UserNotification.skipVoteStartedIdentifier)
        #expect(first.identifier == second.identifier)
        // A song-change and a skip-vote-started request keep distinct
        // identifiers, so they never replace each other.
        #expect(first.identifier != AppConstants.UserNotification.songChangeIdentifier)
    }

}

/// Verifies ordered replacement across pending and delivered notification state.
@MainActor
@Suite("Notification Lifecycle Tests")
struct NotificationServiceLifecycleTests {

    // MARK: - Delivery Ordering

    @Test("Posting removes pending and delivered notifications before replacement")
    func testPostRemovesDeliveredIdentifierBeforeAdd() async {
        let center = TestUserNotificationCenter()
        let identifier = AppConstants.UserNotification.songChangeIdentifier
        let service = NotificationService(
            center: center,
            artworkAttachmentProvider: { _, _ in nil }
        )

        await service.postSongChange(track: "Track", artist: "Artist", album: "Album")

        #expect(center.operations == [
            .removePending([identifier]),
            .removeDelivered([identifier]),
            .add(identifier: identifier, subtitle: "Track")
        ])
    }

    @Test("A slow old artwork lookup cannot replace the latest song notification")
    func testSlowArtworkLookupCannotPostStaleSong() async {
        let center = TestUserNotificationCenter()
        let artwork = ControlledArtworkProvider()
        let service = NotificationService(
            center: center,
            artworkAttachmentProvider: { track, artist in
                await artwork.attachment(track: track, artist: artist)
            }
        )

        let first = Task {
            await service.postSongChange(track: "First", artist: "Artist", album: "Album")
        }
        await artwork.waitUntilRequested(track: "First")

        let second = Task {
            await service.postSongChange(track: "Second", artist: "Artist", album: "Album")
        }
        await artwork.waitUntilRequested(track: "Second")

        artwork.complete(track: "Second")
        await second.value
        artwork.complete(track: "First")
        await first.value

        #expect(center.operations == [
            .removePending([AppConstants.UserNotification.songChangeIdentifier]),
            .removeDelivered([AppConstants.UserNotification.songChangeIdentifier]),
            .add(
                identifier: AppConstants.UserNotification.songChangeIdentifier,
                subtitle: "Second"
            )
        ])
        #expect(center.pendingSubtitles == [
            AppConstants.UserNotification.songChangeIdentifier: "Second"
        ])
    }

    @Test("A newer song retracts an older suspended notification submission")
    func testNewerSongRetractsOlderSuspendedSubmission() async {
        let center = TestUserNotificationCenter()
        let artwork = ControlledArtworkProvider()
        let service = NotificationService(
            center: center,
            artworkAttachmentProvider: { track, artist in
                await artwork.attachment(track: track, artist: artist)
            }
        )
        center.suspendNextAdd()

        let first = Task {
            await service.postSongChange(track: "First", artist: "Artist", album: "Album")
        }
        await artwork.waitUntilRequested(track: "First")
        artwork.complete(track: "First")
        await center.waitUntilAddSuspends()

        let second = Task {
            await service.postSongChange(track: "Second", artist: "Artist", album: "Album")
        }
        await artwork.waitUntilRequested(track: "Second")
        artwork.complete(track: "Second")
        await center.waitUntilAuthorizationChecks(2)

        let identifier = AppConstants.UserNotification.songChangeIdentifier
        #expect(Array(center.operations.suffix(1)) == [
            .add(identifier: identifier, subtitle: "First")
        ])

        center.resumeSuspendedAdd()
        await first.value
        await second.value

        #expect(center.pendingSubtitles == [identifier: "Second"])
        #expect(center.deliveredSubtitles.isEmpty)
        #expect(center.operations == [
            .removePending([identifier]),
            .removeDelivered([identifier]),
            .add(identifier: identifier, subtitle: "First"),
            .removePending([identifier]),
            .removeDelivered([identifier]),
            .removePending([identifier]),
            .removeDelivered([identifier]),
            .add(identifier: identifier, subtitle: "Second")
        ])
    }

    @Test("A passed skip vote invalidates a slow started notification across identifiers")
    func testSkipVotePassedInvalidatesSlowStartedPost() async {
        let center = TestUserNotificationCenter()
        let artwork = ControlledArtworkProvider()
        let service = NotificationService(
            center: center,
            artworkAttachmentProvider: { track, artist in
                await artwork.attachment(track: track, artist: artist)
            }
        )

        let started = Task {
            await service.postSkipVoteStarted(
                track: "Started Track",
                artist: "Artist",
                votesNeeded: 3,
                viaPoll: false
            )
        }
        await artwork.waitUntilRequested(track: "Started Track")

        let passed = Task {
            await service.postSkipVotePassed(track: "Passed Track", artist: "Artist")
        }
        await artwork.waitUntilRequested(track: "Passed Track")

        artwork.complete(track: "Passed Track")
        await passed.value
        artwork.complete(track: "Started Track")
        await started.value

        #expect(center.operations == [
            .removePending([
                AppConstants.UserNotification.skipVotePassedIdentifier,
                AppConstants.UserNotification.skipVoteStartedIdentifier
            ]),
            .removeDelivered([
                AppConstants.UserNotification.skipVotePassedIdentifier,
                AppConstants.UserNotification.skipVoteStartedIdentifier
            ]),
            .add(
                identifier: AppConstants.UserNotification.skipVotePassedIdentifier,
                subtitle: "Skipping Passed Track · Artist"
            )
        ])
    }

    @Test("A passed skip vote removes an already-pending started notification")
    func testSkipVotePassedRemovesDeliveredStartedNotification() async {
        let center = TestUserNotificationCenter()
        let service = NotificationService(
            center: center,
            artworkAttachmentProvider: { _, _ in nil }
        )

        await service.postSkipVoteStarted(
            track: "Track",
            artist: "Artist",
            votesNeeded: 3,
            viaPoll: false
        )
        #expect(center.pendingSubtitles == [
            AppConstants.UserNotification.skipVoteStartedIdentifier: "Track · Artist"
        ])
        await service.postSkipVotePassed(track: "Track", artist: "Artist")

        #expect(center.operations == [
            .removePending([
                AppConstants.UserNotification.skipVoteStartedIdentifier,
                AppConstants.UserNotification.skipVotePassedIdentifier
            ]),
            .removeDelivered([
                AppConstants.UserNotification.skipVoteStartedIdentifier,
                AppConstants.UserNotification.skipVotePassedIdentifier
            ]),
            .add(
                identifier: AppConstants.UserNotification.skipVoteStartedIdentifier,
                subtitle: "Track · Artist"
            ),
            .removePending([
                AppConstants.UserNotification.skipVotePassedIdentifier,
                AppConstants.UserNotification.skipVoteStartedIdentifier
            ]),
            .removeDelivered([
                AppConstants.UserNotification.skipVotePassedIdentifier,
                AppConstants.UserNotification.skipVoteStartedIdentifier
            ]),
            .add(
                identifier: AppConstants.UserNotification.skipVotePassedIdentifier,
                subtitle: "Skipping Track · Artist"
            )
        ])
        #expect(center.pendingSubtitles == [
            AppConstants.UserNotification.skipVotePassedIdentifier: "Skipping Track · Artist"
        ])
        #expect(center.deliveredSubtitles.isEmpty)
    }

    @Test("A new skip vote removes the previous vote's delivered passed notification")
    func testSkipVoteStartedRemovesDeliveredPassedNotification() async {
        let center = TestUserNotificationCenter()
        let service = NotificationService(
            center: center,
            artworkAttachmentProvider: { _, _ in nil }
        )

        await service.postSkipVotePassed(track: "Old Track", artist: "Artist")
        center.deliver(AppConstants.UserNotification.skipVotePassedIdentifier)
        #expect(center.deliveredSubtitles == [
            AppConstants.UserNotification.skipVotePassedIdentifier:
                "Skipping Old Track · Artist"
        ])
        await service.postSkipVoteStarted(
            track: "New Track",
            artist: "Artist",
            votesNeeded: 3,
            viaPoll: false
        )

        #expect(center.operations == [
            .removePending([
                AppConstants.UserNotification.skipVotePassedIdentifier,
                AppConstants.UserNotification.skipVoteStartedIdentifier
            ]),
            .removeDelivered([
                AppConstants.UserNotification.skipVotePassedIdentifier,
                AppConstants.UserNotification.skipVoteStartedIdentifier
            ]),
            .add(
                identifier: AppConstants.UserNotification.skipVotePassedIdentifier,
                subtitle: "Skipping Old Track · Artist"
            ),
            .removePending([
                AppConstants.UserNotification.skipVoteStartedIdentifier,
                AppConstants.UserNotification.skipVotePassedIdentifier
            ]),
            .removeDelivered([
                AppConstants.UserNotification.skipVoteStartedIdentifier,
                AppConstants.UserNotification.skipVotePassedIdentifier
            ]),
            .add(
                identifier: AppConstants.UserNotification.skipVoteStartedIdentifier,
                subtitle: "New Track · Artist"
            )
        ])
        #expect(center.pendingSubtitles == [
            AppConstants.UserNotification.skipVoteStartedIdentifier: "New Track · Artist"
        ])
        #expect(center.deliveredSubtitles.isEmpty)
    }

    // MARK: - UserDefaults Keys

    @Test("Notification preference keys are registered for reset")
    func testKeysInAllKeys() async throws {
        for key in [
            AppConstants.UserDefaults.songChangeNotificationsEnabled,
            AppConstants.UserDefaults.skipVoteStartedNotificationsEnabled,
            AppConstants.UserDefaults.skipVotePassedNotificationsEnabled
        ] {
            #expect(!key.isEmpty)
            #expect(AppConstants.UserDefaults.allKeys.contains(key))
        }
    }
}

@MainActor
private final class TestUserNotificationCenter: UserNotificationCenterProviding {
    enum Operation: Equatable {
        case removePending([String])
        case removeDelivered([String])
        case add(identifier: String, subtitle: String)
    }

    var status: UNAuthorizationStatus = .authorized
    var operations: [Operation] = []
    private(set) var pendingSubtitles: [String: String] = [:]
    private(set) var deliveredSubtitles: [String: String] = [:]
    private var shouldSuspendNextAdd = false
    private var addIsSuspended = false
    private var addSuspendedWaiter: CheckedContinuation<Void, Never>?
    private var suspendedAddContinuation: CheckedContinuation<Void, Never>?
    private var authorizationCheckCount = 0
    private var authorizationCheckTarget = 0
    private var authorizationCheckWaiter: CheckedContinuation<Void, Never>?

    func installDelegate(_ delegate: (any UNUserNotificationCenterDelegate)?) {}

    func authorizationStatus() async -> UNAuthorizationStatus {
        authorizationCheckCount += 1
        if authorizationCheckCount >= authorizationCheckTarget {
            authorizationCheckWaiter?.resume()
            authorizationCheckWaiter = nil
        }
        return status
    }

    func requestAuthorization(options: UNAuthorizationOptions) async throws -> Bool {
        true
    }

    func removePendingNotificationRequests(withIdentifiers identifiers: [String]) {
        operations.append(.removePending(identifiers))
        for identifier in identifiers {
            pendingSubtitles.removeValue(forKey: identifier)
        }
    }

    func removeDeliveredNotifications(withIdentifiers identifiers: [String]) {
        operations.append(.removeDelivered(identifiers))
        for identifier in identifiers {
            deliveredSubtitles.removeValue(forKey: identifier)
        }
    }

    func add(_ request: UNNotificationRequest) async throws {
        let subtitle = request.content.subtitle
        operations.append(
            .add(identifier: request.identifier, subtitle: subtitle)
        )
        pendingSubtitles[request.identifier] = subtitle

        guard shouldSuspendNextAdd else { return }
        shouldSuspendNextAdd = false
        addIsSuspended = true
        addSuspendedWaiter?.resume()
        addSuspendedWaiter = nil
        await withCheckedContinuation { continuation in
            suspendedAddContinuation = continuation
        }
        addIsSuspended = false
    }

    func deliver(_ identifier: String) {
        guard let subtitle = pendingSubtitles.removeValue(forKey: identifier) else { return }
        deliveredSubtitles[identifier] = subtitle
    }

    func suspendNextAdd() {
        shouldSuspendNextAdd = true
    }

    func waitUntilAddSuspends() async {
        if addIsSuspended { return }
        await withCheckedContinuation { continuation in
            addSuspendedWaiter = continuation
        }
    }

    func resumeSuspendedAdd() {
        suspendedAddContinuation?.resume()
        suspendedAddContinuation = nil
    }

    func waitUntilAuthorizationChecks(_ count: Int) async {
        if authorizationCheckCount >= count { return }
        authorizationCheckTarget = count
        await withCheckedContinuation { continuation in
            authorizationCheckWaiter = continuation
        }
    }
}

@MainActor
private final class ControlledArtworkProvider {
    private var requested: Set<String> = []
    private var requestWaiters: [String: CheckedContinuation<Void, Never>] = [:]
    private var attachmentContinuations: [
        String: CheckedContinuation<UNNotificationAttachment?, Never>
    ] = [:]

    func attachment(track: String, artist: String) async -> UNNotificationAttachment? {
        await withCheckedContinuation { continuation in
            attachmentContinuations[track] = continuation
            requested.insert(track)
            requestWaiters.removeValue(forKey: track)?.resume()
        }
    }

    func waitUntilRequested(track: String) async {
        if requested.contains(track) { return }
        await withCheckedContinuation { continuation in
            requestWaiters[track] = continuation
        }
    }

    func complete(track: String) {
        attachmentContinuations.removeValue(forKey: track)?.resume(returning: nil)
    }
}
