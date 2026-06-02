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
        #expect(content.body == "Chat is voting to skip. 1 votes needed.")
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

    // MARK: - Identifiers

    @Test("Notification identifiers are stable and non-empty")
    func testIdentifiers() async throws {
        #expect(AppConstants.UserNotification.songChangeIdentifier
            == "com.mrdemonwolf.wolfwave.notification.songChange")
        #expect(AppConstants.UserNotification.skipVoteStartedIdentifier
            == "com.mrdemonwolf.wolfwave.notification.skipVoteStarted")
        #expect(AppConstants.UserNotification.skipVotePassedIdentifier
            == "com.mrdemonwolf.wolfwave.notification.skipVotePassed")
        // All distinct so they don't replace each other in Notification Center.
        let ids = Set([
            AppConstants.UserNotification.songChangeIdentifier,
            AppConstants.UserNotification.skipVoteStartedIdentifier,
            AppConstants.UserNotification.skipVotePassedIdentifier
        ])
        #expect(ids.count == 3)
    }

    // MARK: - Request Dedup (stable identifiers)

    @Test("Song-change requests reuse the song-change identifier so they dedup")
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
        // Two consecutive song-change requests share one identifier, so the
        // second replaces the first in Notification Center rather than stacking.
        #expect(first.identifier == second.identifier)
    }

    @Test("Skip-vote-started requests reuse the skip-vote-started identifier so they dedup")
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
