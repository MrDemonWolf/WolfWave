//
//  OnboardingNotificationsStepView.swift
//  WolfWave
//
//  Created by Nathanial Henniges on 2026-06-01.
//  Copyright © 2026 MrDemonWolf, Inc. All rights reserved.
//

import AppKit
import SwiftUI
import UserNotifications

/// Notifications step. Asks for notification authorization, then lets the user
/// pick which alerts they want. The per-alert toggles (song change, skip-vote
/// started, skip-vote passed) stay disabled until authorization is granted.
/// Split out from the Apple Music permission step so each screen has one job.
struct OnboardingNotificationsStepView: View {

    // MARK: - Notification State

    @State private var notificationsStatus: UNAuthorizationStatus = .notDetermined

    // MARK: - Notification Preferences

    @AppStorage(AppConstants.UserDefaults.songChangeNotificationsEnabled)
    private var songChangeNotificationsEnabled = false

    @AppStorage(AppConstants.UserDefaults.skipVoteStartedNotificationsEnabled)
    private var skipVoteStartedNotificationsEnabled = false

    @AppStorage(AppConstants.UserDefaults.skipVotePassedNotificationsEnabled)
    private var skipVotePassedNotificationsEnabled = false

    // MARK: - Body

    var body: some View {
        OnboardingStepScaffold(
            title: "Pick your alerts",
            description: "WolfWave can ping you when something happens. Turn on notifications, then choose what's worth a banner.",
            icon: {
                BrandTile(
                    background: AnyShapeStyle(
                        LinearGradient(
                            colors: [Color.red, Color.red.opacity(0.75)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    ),
                    glowColor: Color.red,
                    glyph:
                        Image(systemName: "bell.badge.fill")
                            .font(.system(size: DSFont.Size.x3xl, weight: .semibold))
                            .foregroundStyle(.white)
                )
            },
            extras: {
                notificationsSection
            }
        )
        .task {
            await refreshNotificationStatus()
        }
    }

    // MARK: - Notifications Section

    /// Notification permission row with three states:
    ///   - notDetermined → toggle requests authorization
    ///   - authorized / provisional → toggle is on, locked
    ///   - denied → toggle deep-links to System Settings → Notifications
    @ViewBuilder
    private var notificationsSection: some View {
        let isAuthorized = notificationsStatus == .authorized || notificationsStatus == .provisional

        VStack(alignment: .leading, spacing: DSSpace.s3) {
            sectionLabel(icon: "bell.badge.fill", title: "Notifications")

            preferenceRow(
                icon: "bell.badge.fill",
                iconColor: .red,
                title: "Allow notifications",
                subtitle: notificationsStatus == .denied
                    ? "Enable in System Settings so we can ping you about songs and votes."
                    : "We'll only ping for things you turn on below. Song changes, skip votes.",
                isOn: Binding(
                    get: { isAuthorized },
                    set: { newValue in
                        if notificationsStatus == .denied {
                            if newValue { openNotificationsSettings() }
                        } else {
                            if newValue { requestNotificationAuthorization() }
                        }
                    }
                ),
                accessibilityLabel: "Allow notifications",
                accessibilityIdentifier: "onboardingNotificationsToggle"
            )
            .disabled(isAuthorized)

            // Per-alert toggles. Disabled until notifications are authorized
            // above. They do nothing without permission.
            VStack(spacing: DSSpace.s2) {
                preferenceRow(
                    icon: "music.note",
                    iconColor: .pink,
                    title: "Song changes",
                    subtitle: "A banner with album art each time the track changes.",
                    isOn: $songChangeNotificationsEnabled,
                    accessibilityLabel: "Song change notifications",
                    accessibilityIdentifier: "onboardingSongChangeNotificationsToggle"
                )

                preferenceRow(
                    icon: "hand.raised.fill",
                    iconColor: .orange,
                    title: "Skip vote started",
                    subtitle: "When chat opens a vote to skip the current song.",
                    isOn: $skipVoteStartedNotificationsEnabled,
                    accessibilityLabel: "Skip vote started notifications",
                    accessibilityIdentifier: "onboardingSkipVoteStartedNotificationsToggle"
                )

                preferenceRow(
                    icon: "checkmark.seal.fill",
                    iconColor: .green,
                    title: "Skip vote passed",
                    subtitle: "When a chat skip-vote wins and the song is skipped.",
                    isOn: $skipVotePassedNotificationsEnabled,
                    accessibilityLabel: "Skip vote passed notifications",
                    accessibilityIdentifier: "onboardingSkipVotePassedNotificationsToggle"
                )
            }
            .disabled(!isAuthorized)
        }
        .animation(.easeInOut(duration: DSMotion.Duration.base), value: notificationsStatus)
    }

    // MARK: - Section Label

    private func sectionLabel(icon: String, title: String) -> some View {
        HStack(spacing: DSSpace.s2) {
            Image(systemName: icon)
                .font(.system(size: DSFont.Size.sm, weight: .semibold))
                .foregroundStyle(.secondary)
            Text(title)
                .font(.system(size: DSFont.Size.sm, weight: .semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
            Spacer()
        }
    }

    // MARK: - Row

    /// Builds a single labeled toggle row: colored icon tile, title, subtitle,
    /// and a binding switch. Mirrors the row used in the Preferences step.
    @ViewBuilder
    private func preferenceRow(
        icon: String,
        iconColor: Color,
        title: String,
        subtitle: String,
        isOn: Binding<Bool>,
        accessibilityLabel: String,
        accessibilityIdentifier: String
    ) -> some View {
        OnboardingToggleCard(
            icon: icon,
            iconColor: iconColor,
            title: title,
            subtitle: subtitle,
            isOn: isOn,
            accessibilityLabel: accessibilityLabel,
            accessibilityIdentifier: accessibilityIdentifier
        )
    }

    // MARK: - Notification Actions

    /// Queries the current notification authorization status and updates the
    /// view state on the main actor.
    private func refreshNotificationStatus() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        await MainActor.run {
            notificationsStatus = settings.authorizationStatus
        }
    }

    /// Requests notification authorization (`.alert`, `.sound`, `.badge`) and
    /// refreshes the view state with whatever decision the user makes.
    private func requestNotificationAuthorization() {
        Task {
            _ = try? await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .sound, .badge])
            let settings = await UNUserNotificationCenter.current().notificationSettings()
            await MainActor.run {
                notificationsStatus = settings.authorizationStatus
            }
        }
    }

    /// Opens System Settings → Notifications. macOS 13+ deep-link.
    private func openNotificationsSettings() {
        ExternalLink.open("x-apple.systempreferences:com.apple.Notifications-Settings.extension")
    }
}

// MARK: - Preview

#Preview {
    OnboardingNotificationsStepView()
        .frame(width: 600, height: 520)
}
