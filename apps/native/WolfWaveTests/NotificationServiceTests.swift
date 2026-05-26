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

    @Test("Song change content uses track as title and artist + album as body")
    func testSongChangeContentFull() async throws {
        let content = NotificationService.makeSongChangeContent(
            track: "Blinding Lights",
            artist: "The Weeknd",
            album: "After Hours"
        )
        #expect(content.title == "Blinding Lights")
        #expect(content.body == "The Weeknd — After Hours")
    }

    @Test("Song change content falls back to artist only when album is empty")
    func testSongChangeContentNoAlbum() async throws {
        let content = NotificationService.makeSongChangeContent(
            track: "Some Song",
            artist: "Some Artist",
            album: ""
        )
        #expect(content.title == "Some Song")
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

    @Test("Song change content uses a default title when the track is empty")
    func testSongChangeContentEmptyTrack() async throws {
        let content = NotificationService.makeSongChangeContent(
            track: "",
            artist: "Artist",
            album: "Album"
        )
        #expect(content.title == "Now Playing")
    }

    @Test("Song change content trims surrounding whitespace")
    func testSongChangeContentTrimsWhitespace() async throws {
        let content = NotificationService.makeSongChangeContent(
            track: "  Track  ",
            artist: "  Artist  ",
            album: "  Album  "
        )
        #expect(content.title == "Track")
        #expect(content.body == "Artist — Album")
    }

    @Test("Song change content preserves unusual characters")
    func testSongChangeContentUnusualCharacters() async throws {
        let content = NotificationService.makeSongChangeContent(
            track: "Café — naïve 🎧",
            artist: "Sigur Rós",
            album: "( )"
        )
        #expect(content.title == "Café — naïve 🎧")
        #expect(content.body == "Sigur Rós — ( )")
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

    // MARK: - Identifier

    @Test("Song change notification identifier is stable and non-empty")
    func testSongChangeIdentifier() async throws {
        #expect(!AppConstants.UserNotification.songChangeIdentifier.isEmpty)
        #expect(AppConstants.UserNotification.songChangeIdentifier
            == "com.mrdemonwolf.wolfwave.notification.songChange")
    }

    // MARK: - UserDefaults Key

    @Test("Song change notifications key is registered for reset")
    func testSongChangeKeyInAllKeys() async throws {
        #expect(!AppConstants.UserDefaults.songChangeNotificationsEnabled.isEmpty)
        #expect(AppConstants.UserDefaults.allKeys
            .contains(AppConstants.UserDefaults.songChangeNotificationsEnabled))
    }
}
