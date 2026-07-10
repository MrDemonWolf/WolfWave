//
//  NotificationService.swift
//  WolfWave
//
//  Created by Nathanial Henniges on 2026-05-22.
//  Copyright © 2026 MrDemonWolf, Inc. All rights reserved.
//

import AppKit
import Foundation
import UserNotifications

/// Centralizes macOS User Notification delivery for WolfWave.
///
/// Wraps `UNUserNotificationCenter` so callers don't repeat authorization and
/// error-handling boilerplate. Posts song-change, skip-vote (started /
/// passed), and Twitch re-auth notifications; the private
/// `post(content:identifier:)` core is the shared extension point for any
/// future notification type.
///
/// Also acts as the `UNUserNotificationCenterDelegate` (installed once at
/// launch via `installCenterDelegate()`) so banners still present while
/// WolfWave is frontmost. Inherits `NSObject` because that delegate protocol
/// requires it.
final class NotificationService: NSObject {

    // MARK: - Singleton

    /// Shared instance used across the app.
    static let shared = NotificationService()

    private override init() {}

    // MARK: - Center Delegate Installation

    /// Installs this service as the notification-center delegate.
    ///
    /// Without a delegate, macOS suppresses every banner while the app is
    /// frontmost, which is exactly when the user is in Settings flipping the
    /// notification toggles and expecting to see one. Call once at launch.
    func installCenterDelegate() {
        UNUserNotificationCenter.current().delegate = self
    }

    // MARK: - Song Change

    /// Posts a "now playing" notification for a newly-started track.
    ///
    /// Fetches album artwork and attaches it when available, falling back to a
    /// text-only notification otherwise. Reuses the stable song-change
    /// identifier so each new song replaces the previous notification rather
    /// than stacking in Notification Center. Does nothing when the user has not
    /// granted notification authorization.
    ///
    /// - Parameters:
    ///   - track: Song title.
    ///   - artist: Artist name.
    ///   - album: Album title (may be empty).
    func postSongChange(track: String, artist: String, album: String) async {
        let content = Self.makeSongChangeContent(track: track, artist: artist, album: album)

        if let attachment = await songChangeArtworkAttachment(track: track, artist: artist) {
            content.attachments = [attachment]
        }

        await post(content: content, identifier: AppConstants.UserNotification.songChangeIdentifier)
    }

    /// Builds the notification content for a song change.
    ///
    /// Pure, performs no system calls, so it can be unit-tested directly.
    ///
    /// - Parameters:
    ///   - track: Song title.
    ///   - artist: Artist name.
    ///   - album: Album title (may be empty).
    /// - Returns: A configured notification content value.
    static func makeSongChangeContent(
        track: String,
        artist: String,
        album: String
    ) -> UNMutableNotificationContent {
        let content = UNMutableNotificationContent()

        let trimmedTrack = track.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedArtist = artist.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedAlbum = album.trimmingCharacters(in: .whitespacesAndNewlines)

        // "Now Playing" header keeps the banner self-explanatory; the song name
        // sits on the subtitle line, artist + album on the body line.
        content.title = "Now Playing"
        content.subtitle = trimmedTrack.isEmpty ? "Unknown song" : trimmedTrack

        if trimmedArtist.isEmpty {
            content.body = trimmedAlbum
        } else if trimmedAlbum.isEmpty {
            content.body = trimmedArtist
        } else {
            content.body = "\(trimmedArtist) · \(trimmedAlbum)"
        }

        // Silent banner. Song changes are frequent, so a sound would be noise.
        content.sound = nil
        return content
    }

    // MARK: - Skip Vote

    /// Posts a notification when a chat skip-vote starts.
    ///
    /// Silent (like song-change). The start is informational, not urgent.
    /// Reuses a stable identifier so a fresh vote-start replaces the previous
    /// one. Attaches current-track artwork when available. No-op without
    /// notification authorization.
    ///
    /// - Parameters:
    ///   - track: Currently-playing song title (may be empty).
    ///   - artist: Currently-playing artist (may be empty).
    ///   - votesNeeded: Votes required to skip (chat-tally mode).
    ///   - viaPoll: `true` when a native Twitch poll opened instead of a chat tally.
    func postSkipVoteStarted(
        track: String,
        artist: String,
        votesNeeded: Int,
        viaPoll: Bool
    ) async {
        let content = Self.makeSkipVoteStartedContent(
            track: track, artist: artist, votesNeeded: votesNeeded, viaPoll: viaPoll)

        if let attachment = await songChangeArtworkAttachment(track: track, artist: artist) {
            content.attachments = [attachment]
        }

        await post(content: content, identifier: AppConstants.UserNotification.skipVoteStartedIdentifier)
    }

    /// Posts a notification when a chat skip-vote passes.
    ///
    /// Plays the default system sound. Passing is a rare, worth-a-chime event.
    /// Attaches current-track artwork when available. No-op without
    /// notification authorization.
    ///
    /// - Parameters:
    ///   - track: The skipped song's title (may be empty).
    ///   - artist: The skipped song's artist (may be empty).
    func postSkipVotePassed(track: String, artist: String) async {
        let content = Self.makeSkipVotePassedContent(track: track, artist: artist)

        if let attachment = await songChangeArtworkAttachment(track: track, artist: artist) {
            content.attachments = [attachment]
        }

        await post(content: content, identifier: AppConstants.UserNotification.skipVotePassedIdentifier)
    }

    /// Builds the notification content for a skip-vote start.
    ///
    /// Pure, performs no system calls, so it can be unit-tested directly.
    ///
    /// - Parameters:
    ///   - track: Currently-playing song title (may be empty).
    ///   - artist: Currently-playing artist (may be empty).
    ///   - votesNeeded: Votes required to skip (chat-tally mode).
    ///   - viaPoll: `true` when a native Twitch poll opened.
    /// - Returns: A configured, silent notification content value.
    static func makeSkipVoteStartedContent(
        track: String,
        artist: String,
        votesNeeded: Int,
        viaPoll: Bool
    ) -> UNMutableNotificationContent {
        let content = UNMutableNotificationContent()

        content.title = "Skip Vote Started"
        content.subtitle = Self.trackLine(track: track, artist: artist)
        let needed = max(votesNeeded, 1)
        content.body = viaPoll
            ? "A Twitch poll is open. Viewers vote in the poll widget."
            : "Chat is voting to skip. \(needed) \(needed == 1 ? "vote" : "votes") needed."

        // Silent. The start is informational. The "passed" banner gets the chime.
        content.sound = nil
        return content
    }

    /// Builds the notification content for a passed skip-vote.
    ///
    /// Pure, performs no system calls, so it can be unit-tested directly.
    ///
    /// - Parameters:
    ///   - track: The skipped song's title (may be empty).
    ///   - artist: The skipped song's artist (may be empty).
    /// - Returns: A configured notification content value with the default sound.
    static func makeSkipVotePassedContent(
        track: String,
        artist: String
    ) -> UNMutableNotificationContent {
        let content = UNMutableNotificationContent()

        content.title = "Skip Vote Passed"
        let line = Self.trackLine(track: track, artist: artist)
        content.subtitle = line.isEmpty ? "" : "Skipping \(line)"
        content.body = "Chat voted to skip the current song."

        // Rare, celebratory event. A chime is warranted.
        content.sound = .default
        return content
    }

    // MARK: - Twitch Re-auth

    /// Posts a "Twitch session expired" notification.
    ///
    /// Reuses the stable re-auth identifier so a repeat prompt in the same
    /// session replaces the previous banner instead of stacking. Safe to call
    /// from unattended paths (e.g. the boot token check): the shared post core
    /// never requests authorization, it simply drops the banner unless the
    /// user already granted it. The in-app re-auth banner covers that case.
    func postTwitchReauthNeeded() async {
        await post(
            content: Self.makeTwitchReauthContent(),
            identifier: AppConstants.UserNotification.twitchReauthIdentifier
        )
    }

    /// Builds the notification content for an expired Twitch session.
    ///
    /// Pure, performs no system calls, so it can be unit-tested directly.
    ///
    /// - Returns: A configured notification content value with the default
    ///   sound (the user must act to restore the Twitch connection).
    static func makeTwitchReauthContent() -> UNMutableNotificationContent {
        let content = UNMutableNotificationContent()
        content.title = "Twitch Authentication Expired"
        content.body = "Your Twitch session has expired. Please re-authorize in Settings."
        content.sound = .default
        return content
    }

    /// Formats a `track · artist` line, tolerating either field being empty.
    private static func trackLine(track: String, artist: String) -> String {
        let trimmedTrack = track.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedArtist = artist.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedTrack.isEmpty { return trimmedArtist }
        if trimmedArtist.isEmpty { return trimmedTrack }
        return "\(trimmedTrack) · \(trimmedArtist)"
    }

    // MARK: - Authorization

    /// Returns the current notification authorization status.
    func authorizationStatus() async -> UNAuthorizationStatus {
        await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
    }

    /// Requests notification authorization (`.alert`, `.sound`, `.badge`).
    ///
    /// - Returns: `true` when the user grants authorization.
    @discardableResult
    func requestAuthorization() async -> Bool {
        (try? await UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .sound, .badge])) ?? false
    }

    /// Opens System Settings → Notifications. macOS 13+ deep-link.
    func openSystemNotificationSettings() {
        ExternalLink.open(AppConstants.URLs.systemNotificationSettings)
    }

    // MARK: - Request Building

    /// Wraps notification `content` and an `identifier` into an immediate
    /// (`trigger: nil`) request.
    ///
    /// Pure, performs no system calls, so tests can assert that each
    /// notification type reuses its stable identifier (the dedup contract:
    /// a new request with the same identifier replaces the previous one rather
    /// than stacking in Notification Center).
    ///
    /// - Parameters:
    ///   - content: The notification content to deliver.
    ///   - identifier: Request identifier. Reuse a stable value per type so a
    ///     fresh notification replaces the previous one.
    /// - Returns: A configured, immediately-firing notification request.
    static func makeRequest(
        content: UNNotificationContent,
        identifier: String
    ) -> UNNotificationRequest {
        UNNotificationRequest(identifier: identifier, content: content, trigger: nil)
    }

    // MARK: - Private Helpers

    /// Adds a notification request. No-op unless authorization has already been
    /// granted.
    ///
    /// `.notDetermined` is treated exactly like `.denied`: a background delivery
    /// must never trigger the system authorization prompt out of nowhere. The user
    /// only grants permission through the deliberate, primed button paths
    /// (`requestAuthorization()` from onboarding / settings), so an un-asked
    /// install simply drops the notification.
    ///
    /// - Parameters:
    ///   - content: The notification content to deliver.
    ///   - identifier: Request identifier. Reuse a stable value to replace an
    ///     existing notification rather than stacking a new one.
    private func post(content: UNNotificationContent, identifier: String) async {
        let center = UNUserNotificationCenter.current()

        switch await center.notificationSettings().authorizationStatus {
        case .notDetermined, .denied:
            // No prompt, no delivery. Authorization happens only via the primed
            // button paths, never as a side effect of a notification firing.
            return
        default:
            break
        }

        let request = Self.makeRequest(content: content, identifier: identifier)
        do {
            try await center.add(request)
        } catch {
            Log.error(
                "NotificationService: Failed to post notification: \(error.localizedDescription)",
                category: "App"
            )
        }
    }

    /// Fetches album artwork and writes it to a temporary file for use as a
    /// notification attachment.
    ///
    /// - Returns: An attachment, or `nil` when artwork is unavailable or the
    ///   download fails (the caller then posts a text-only notification).
    private func songChangeArtworkAttachment(
        track: String,
        artist: String
    ) async -> UNNotificationAttachment? {
        guard let urlString = await fetchArtworkURLString(track: track, artist: artist),
              let remoteURL = URL(string: urlString) else { return nil }

        do {
            let data = try await HTTPClient.shared.data(url: remoteURL)
            let ext = remoteURL.pathExtension.isEmpty ? "jpg" : remoteURL.pathExtension
            let fileURL = FileManager.default.temporaryDirectory
                .appending(path: "wolfwave-artwork-\(UUID().uuidString).\(ext)")
            try data.write(to: fileURL)
            return try UNNotificationAttachment(identifier: "artwork", url: fileURL, options: nil)
        } catch {
            Log.debug(
                "NotificationService: Artwork attachment unavailable: \(error.localizedDescription)",
                category: "App"
            )
            return nil
        }
    }

    /// Bridges `ArtworkService`'s completion-handler API to async/await.
    private func fetchArtworkURLString(track: String, artist: String) async -> String? {
        await withCheckedContinuation { continuation in
            ArtworkService.shared.fetchArtworkURL(track: track, artist: artist) { url in
                continuation.resume(returning: url)
            }
        }
    }
}

// MARK: - UNUserNotificationCenterDelegate

extension NotificationService: UNUserNotificationCenterDelegate {

    /// Presents notifications while WolfWave is frontmost.
    ///
    /// Without this, macOS silently swallows every banner for the foreground
    /// app, so a user testing the toggles in Settings would never see one.
    ///
    /// `nonisolated`: UserNotifications may invoke its delegate off the main
    /// thread, and this class is MainActor by the module default. The method
    /// touches no isolated state, so opting out of isolation avoids the
    /// off-main-callback-into-MainActor-witness crash pattern.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }
}
