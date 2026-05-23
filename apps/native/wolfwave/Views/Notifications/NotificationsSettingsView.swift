//
//  NotificationsSettingsView.swift
//  wolfwave
//
//  Created by MrDemonWolf, Inc. on 5/22/26.
//

import SwiftUI
import UserNotifications

/// Notification preferences — controls the macOS song-change notification.
struct NotificationsSettingsView: View {

    // MARK: - User Settings

    @AppStorage(AppConstants.UserDefaults.songChangeNotificationsEnabled)
    private var songChangeNotificationsEnabled = false

    // MARK: - State

    /// Cached system authorization status, used to surface the denied-permission notice.
    @State private var authorizationStatus: UNAuthorizationStatus = .notDetermined

    // MARK: - Body

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Notifications")
                    .sectionSubHeader()

                Text("Get a heads-up in Notification Center as your music plays.")
                    .font(.system(size: DSFont.Size.base))
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 12) {
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

                if songChangeNotificationsEnabled && authorizationStatus == .denied {
                    permissionDeniedNotice
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(AppConstants.SettingsUI.cardPadding)
            .background(Color(nsColor: .controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: AppConstants.SettingsUI.cardCornerRadius))
        }
        .task {
            await refreshAuthorizationStatus()
        }
    }

    // MARK: - Permission Notice

    /// Shown when notifications are enabled in WolfWave but denied at the system level.
    private var permissionDeniedNotice: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: DSFont.Size.body))
                .foregroundStyle(.orange)

            VStack(alignment: .leading, spacing: 6) {
                Text("Notifications are turned off for WolfWave. Enable them in System Settings to see song changes.")
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
        .background(Color.orange.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 7))
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
