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
                            .font(BrandTileGlyph.font)
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
            // The gate. Grants permission; the alert group below stays locked
            // until it's on.
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

            // The three alerts share one bordered container so they read as a
            // single group sitting under the gate above. Disabled until
            // notifications are authorized. They do nothing without permission.
            alertGroup
                .disabled(!isAuthorized)
                .opacity(isAuthorized ? 1 : 0.5)
        }
        .animation(.easeInOut(duration: DSMotion.Duration.base), value: notificationsStatus)
    }

    /// The per-alert toggles, rendered as chrome-free rows stacked inside one
    /// bordered card with text-aligned dividers between them.
    @ViewBuilder
    private var alertGroup: some View {
        VStack(spacing: 0) {
            groupedRow(
                icon: "music.note",
                iconColor: .pink,
                title: "Song changes",
                subtitle: "A banner with album art each time the track changes.",
                isOn: $songChangeNotificationsEnabled,
                accessibilityLabel: "Song change notifications",
                accessibilityIdentifier: "onboardingSongChangeNotificationsToggle"
            )

            rowDivider

            groupedRow(
                icon: "hand.raised.fill",
                iconColor: .orange,
                title: "Skip vote started",
                subtitle: "When chat opens a vote to skip the current song.",
                isOn: $skipVoteStartedNotificationsEnabled,
                accessibilityLabel: "Skip vote started notifications",
                accessibilityIdentifier: "onboardingSkipVoteStartedNotificationsToggle"
            )

            rowDivider

            groupedRow(
                icon: "checkmark.seal.fill",
                iconColor: .green,
                title: "Skip vote passed",
                subtitle: "When a chat skip-vote wins and the song is skipped.",
                isOn: $skipVotePassedNotificationsEnabled,
                accessibilityLabel: "Skip vote passed notifications",
                accessibilityIdentifier: "onboardingSkipVotePassedNotificationsToggle"
            )
        }
        .subtleCardShell(cornerRadius: DSRadius.lg2)
    }

    /// Hairline between grouped rows, inset to start under the row title so it
    /// clears the icon tile (the standard grouped-list look).
    private var rowDivider: some View {
        Divider()
            .padding(.leading, AppConstants.OnboardingUI.iconTileSize + DSSpace.s4 * 2)
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

    /// Same row, minus its own card chrome, for stacking inside `alertGroup`'s
    /// shared border.
    @ViewBuilder
    private func groupedRow(
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
            accessibilityIdentifier: accessibilityIdentifier,
            showsCardBackground: false
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
        ExternalLink.open(AppConstants.URLs.systemNotificationSettings)
    }
}

// MARK: - Preview

#Preview {
    OnboardingNotificationsStepView()
        .frame(width: 600, height: 520)
}
