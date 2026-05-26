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
/// error-handling boilerplate. Currently posts song-change notifications; the
/// private `post(content:identifier:)` core is the extension point for future
/// notification types (for example, a skip-vote alert).
final class NotificationService {

    // MARK: - Singleton

    /// Shared instance used across the app.
    static let shared = NotificationService()

    private init() {}

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
    /// Pure — performs no system calls — so it can be unit-tested directly.
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

        content.title = trimmedTrack.isEmpty ? "Now Playing" : trimmedTrack

        if trimmedArtist.isEmpty {
            content.body = trimmedAlbum
        } else if trimmedAlbum.isEmpty {
            content.body = trimmedArtist
        } else {
            content.body = "\(trimmedArtist) — \(trimmedAlbum)"
        }

        // Silent banner — song changes are frequent, so a sound would be noise.
        content.sound = nil
        return content
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
        if let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension") {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: - Private Helpers

    /// Adds a notification request, requesting authorization first when the
    /// status is undetermined. No-op when authorization is denied.
    ///
    /// - Parameters:
    ///   - content: The notification content to deliver.
    ///   - identifier: Request identifier — reuse a stable value to replace an
    ///     existing notification rather than stacking a new one.
    private func post(content: UNNotificationContent, identifier: String) async {
        let center = UNUserNotificationCenter.current()

        switch await center.notificationSettings().authorizationStatus {
        case .notDetermined:
            guard await requestAuthorization() else { return }
        case .denied:
            return
        default:
            break
        }

        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: nil)
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
            let (data, _) = try await URLSession.shared.data(from: remoteURL)
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
