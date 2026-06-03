//
//  NotificationsSettingsView.swift
//  WolfWave
//
//  Created by Nathanial Henniges on 2026-05-22.
//  Copyright © 2026 MrDemonWolf, Inc. All rights reserved.
//

import SwiftUI
import UserNotifications

/// Notification preferences: toggles for the macOS song-change banner plus the
/// skip-vote-started / skip-vote-passed banners (the latter two are gated on the
/// master vote-to-skip setting). Requests system authorization on first enable
/// and surfaces a notice if banners are denied at the system level.
struct NotificationsSettingsView: View {

    // MARK: - User Settings

    @AppStorage(AppConstants.UserDefaults.songChangeNotificationsEnabled)
    private var songChangeNotificationsEnabled = false

    @AppStorage(AppConstants.UserDefaults.skipVoteStartedNotificationsEnabled)
    private var skipVoteStartedNotificationsEnabled = false

    @AppStorage(AppConstants.UserDefaults.skipVotePassedNotificationsEnabled)
    private var skipVotePassedNotificationsEnabled = false

    /// Master vote-skip toggle: the skip-vote notification rows do nothing
    /// without it, so they're disabled (with a hint) when it's off.
    @AppStorage(AppConstants.UserDefaults.voteSkipEnabled)
    private var voteSkipEnabled = false

    // MARK: - State

    /// Cached system authorization status, used to surface the denied-permission notice.
    @State private var authorizationStatus: UNAuthorizationStatus = .notDetermined

    // MARK: - Body

    var body: some View {
        VStack(alignment: .leading, spacing: DSSpace.s6) {
            VStack(alignment: .leading, spacing: DSSpace.s1h) {
                Text("Notifications")
                    .sectionSubHeader()

                Text("Get a heads-up in Notification Center as your music plays.")
                    .font(.system(size: DSFont.Size.base))
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: DSSpace.s4) {
                ToggleSettingRow(
                    title: "Song change notifications",
                    subtitle: "Show a notification with album art each time the track changes.",
                    isOn: $songChangeNotificationsEnabled,
                    accessibilityLabel: "Song change notifications",
                    accessibilityIdentifier: "songChangeNotificationsToggle",
                    accessibilityHint: "Posts a macOS notification when the playing song changes"
                ) { enabled in
                    if enabled { handleEnabled() }
                }

                Divider()

                ToggleSettingRow(
                    title: "Skip vote started",
                    subtitle: "Notify when chat opens a vote to skip the current song.",
                    isOn: $skipVoteStartedNotificationsEnabled,
                    accessibilityLabel: "Skip vote started notifications",
                    accessibilityIdentifier: "skipVoteStartedNotificationsToggle",
                    accessibilityHint: "Posts a macOS notification when a chat skip-vote starts"
                ) { enabled in
                    if enabled { handleEnabled() }
                }
                .disabled(!voteSkipEnabled)

                ToggleSettingRow(
                    title: "Skip vote passed",
                    subtitle: "Notify when a chat skip-vote wins and the song is skipped.",
                    isOn: $skipVotePassedNotificationsEnabled,
                    accessibilityLabel: "Skip vote passed notifications",
                    accessibilityIdentifier: "skipVotePassedNotificationsToggle",
                    accessibilityHint: "Posts a macOS notification when a chat skip-vote passes"
                ) { enabled in
                    if enabled { handleEnabled() }
                }
                .disabled(!voteSkipEnabled)

                if !voteSkipEnabled {
                    Text("Turn on vote-to-skip in Song Requests to use these.")
                        .font(.system(size: DSFont.Size.sm))
                        .foregroundStyle(.secondary)
                }

                if (songChangeNotificationsEnabled
                    || skipVoteStartedNotificationsEnabled
                    || skipVotePassedNotificationsEnabled)
                    && authorizationStatus == .denied {
                    permissionDeniedNotice
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .cardStyle()
        }
        .task {
            await refreshAuthorizationStatus()
        }
    }

    // MARK: - Permission Notice

    /// Shown when notifications are enabled in WolfWave but denied at the system level.
    private var permissionDeniedNotice: some View {
        HStack(alignment: .top, spacing: DSSpace.s3) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: DSFont.Size.body))
                .foregroundStyle(.orange)

            VStack(alignment: .leading, spacing: DSSpace.s1h) {
                Text("Notifications are turned off for WolfWave. Enable them in System Settings to get these alerts.")
                    .font(.system(size: DSFont.Size.sm))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Button("Open System Settings") {
                    NotificationService.shared.openSystemNotificationSettings()
                }
                .font(.system(size: DSFont.Size.sm))
                .pointerCursor()
                .accessibilityIdentifier("openNotificationSettingsButton")
            }
        }
        .padding(DSSpace.s3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DSColor.warning.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: DSRadius.sm))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Notifications are turned off for WolfWave. Open System Settings to enable them.")
    }

    // MARK: - Helpers

    /// Requests authorization the first time the user enables the toggle, then
    /// refreshes the cached status so the denied notice appears if needed.
    private func handleEnabled() {
        Task {
            if authorizationStatus == .notDetermined {
                await NotificationService.shared.requestAuthorization()
            }
            await refreshAuthorizationStatus()
        }
    }

    /// Re-syncs the cached authorization status from the system.
    private func refreshAuthorizationStatus() async {
        let status = await NotificationService.shared.authorizationStatus()
        await MainActor.run {
            authorizationStatus = status
        }
    }
}

// MARK: - Preview

#Preview("Enabled") {
    @Previewable @AppStorage(AppConstants.UserDefaults.songChangeNotificationsEnabled)
    var enabled = true

    NotificationsSettingsView()
        .padding()
        .frame(width: 600)
}

#Preview("Disabled") {
    @Previewable @AppStorage(AppConstants.UserDefaults.songChangeNotificationsEnabled)
    var enabled = false

    NotificationsSettingsView()
        .padding()
        .frame(width: 600)
}
