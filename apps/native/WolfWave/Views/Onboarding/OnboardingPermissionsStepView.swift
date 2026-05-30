//
//  OnboardingPermissionsStepView.swift
//  WolfWave
//
//  Created by Nathanial Henniges on 2026-05-30.
//  Copyright © 2026 MrDemonWolf, Inc. All rights reserved.
//

import AppKit
import SwiftUI
import UserNotifications

/// Permissions step. Asks for the system grants WolfWave needs and lets the user
/// pick their alerts, all on one screen:
///   - **Apple Music** automation (the TCC bucket `MusicPlaybackMonitor` needs to
///     read the current track). We never read the catalog or library.
///   - **Notifications** authorization, plus per-alert toggles (song change,
///     skip-vote started, skip-vote passed) that stay disabled until granted.
struct OnboardingPermissionsStepView: View {

    // MARK: - Apple Music State

    @State private var permissionState: MusicPermissionState = MusicPermissionChecker.currentState()
    @State private var isRequesting = false
    @State private var isRechecking = false

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
            title: "Permissions & alerts",
            description: "WolfWave reads the current track from the Music app and pings you when something happens. Grant access and pick your alerts here.",
            icon: {
                BrandTile(
                    background: AnyShapeStyle(
                        LinearGradient(
                            colors: [Color.accentColor, Color.accentColor.opacity(0.75)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    ),
                    glowColor: Color.accentColor,
                    glyph:
                        Image(systemName: "lock.shield.fill")
                            .font(.system(size: DSFont.Size.x26, weight: .semibold))
                            .foregroundStyle(.white)
                )
            },
            extras: {
                VStack(spacing: DSSpace.s5) {
                    appleMusicSection
                        .animation(.easeInOut(duration: DSMotion.Duration.base), value: permissionState)

                    notificationsSection
                }
            }
        )
        .task {
            await refreshNotificationStatus()
        }
    }

    // MARK: - Apple Music Section

    @ViewBuilder
    private var appleMusicSection: some View {
        VStack(alignment: .leading, spacing: DSSpace.s3) {
            sectionLabel(icon: "music.note", title: "Apple Music access")

            switch permissionState {
            case .granted:
                HStack(spacing: DSSpace.s3) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: DSFont.Size.x18))
                        .foregroundStyle(.green)
                    Text("Access granted. Sync Music is on.")
                        .font(.system(size: DSFont.Size.base))
                        .foregroundStyle(.primary)
                }
                .padding(DSSpace.s4)
                .frame(maxWidth: .infinity, alignment: .leading)
                .cardStyle()

            case .denied:
                VStack(spacing: DSSpace.s3) {
                    HStack(alignment: .top, spacing: DSSpace.s2) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                        Text("Access was denied. Enable in **System Settings → Privacy & Security → Automation → WolfWave → Music**.")
                            .font(.system(size: DSFont.Size.body))
                            .foregroundStyle(.primary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(DSSpace.s4)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(DSColor.warning.opacity(0.10))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(DSColor.warning.opacity(0.40), lineWidth: 0.5)
                    )

                    HStack(spacing: DSSpace.s2) {
                        Button(action: recheckTapped) {
                            HStack(spacing: 6) {
                                if isRechecking {
                                    ProgressView()
                                        .progressViewStyle(.circular)
                                        .controlSize(.small)
                                }
                                Text("Recheck")
                            }
                        }
                        .buttonStyle(.bordered)
                        .pointerCursor()
                        .disabled(isRechecking)
                        .accessibilityLabel("Recheck Apple Music access")
                        .accessibilityHint("Re-queries macOS for the current automation permission state")
                        .accessibilityIdentifier("onboardingAppleMusic.recheckButton")

                        Button("Open System Settings") {
                            MusicPermissionChecker.openAutomationSettings()
                        }
                        .buttonStyle(.borderedProminent)
                        .pointerCursor()
                        .accessibilityLabel("Open System Settings")
                        .accessibilityHint("Opens Privacy and Security to grant Apple Music access")
                        .accessibilityIdentifier("onboardingAppleMusic.openSystemSettingsButton")
                    }
                }

            case .unknown:
                VStack(spacing: DSSpace.s3) {
                    PillButton(
                        background: AnyShapeStyle(
                            LinearGradient(
                                colors: [
                                    AppConstants.Brand.appleMusicGradientStart,
                                    AppConstants.Brand.appleMusicGradientEnd
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        ),
                        glowColor: AppConstants.Brand.appleMusicGradientEnd,
                        disabled: isRequesting,
                        action: requestAccess,
                        label: {
                            HStack(spacing: DSSpace.s2) {
                                if isRequesting {
                                    ProgressView()
                                        .progressViewStyle(.circular)
                                        .controlSize(.small)
                                        .tint(.white)
                                }
                                Text("Allow Music access")
                            }
                        }
                    )
                    .accessibilityLabel("Allow Music access")
                    .accessibilityIdentifier("onboardingAppleMusicGrant")

                    Text("macOS will ask once. You can change this later in System Settings → Privacy → Automation.")
                        .font(.system(size: DSFont.Size.sm))
                        .foregroundStyle(.tertiary)
                        .multilineTextAlignment(.center)
                }
            }
        }
    }

    // MARK: - Notifications Section

    /// Notification permission row with three states:
    ///   - notDetermined → toggle requests authorization
    ///   - authorized / provisional → toggle is on, locked
    ///   - denied → button deep-links to System Settings → Notifications
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
                    : "We'll only ping for things you turn on next — song changes, skip votes.",
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
            // above — they do nothing without permission.
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
        HStack(spacing: DSSpace.s4) {
            ZStack {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(iconColor.opacity(0.15))
                    .frame(width: 28, height: 28)

                Image(systemName: icon)
                    .font(.system(size: DSFont.Size.base, weight: .semibold))
                    .foregroundStyle(iconColor)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: DSFont.Size.base, weight: .semibold))

                Text(subtitle)
                    .font(.system(size: DSFont.Size.sm))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()

            Toggle("", isOn: isOn)
                .toggleStyle(.switch)
                .labelsHidden()
                .pointerCursor()
                .accessibilityLabel(accessibilityLabel)
                .accessibilityIdentifier(accessibilityIdentifier)
        }
        .padding(DSSpace.s4)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.primary.opacity(0.06), lineWidth: 0.5)
        )
    }

    // MARK: - Apple Music Actions

    /// Re-queries Apple Music automation permission with a brief spinner so
    /// the user gets visible feedback even when the state doesn't change.
    private func recheckTapped() {
        guard !isRechecking else { return }
        withAnimation(.easeInOut(duration: DSMotion.Duration.fast)) {
            isRechecking = true
        }
        Task {
            let start = Date()
            let next = MusicPermissionChecker.currentState()
            let elapsed = Date().timeIntervalSince(start)
            let minSpin: TimeInterval = 0.25
            if elapsed < minSpin {
                try? await Task.sleep(nanoseconds: UInt64((minSpin - elapsed) * 1_000_000_000))
            }
            await MainActor.run {
                withAnimation(.easeInOut(duration: DSMotion.Duration.base)) {
                    permissionState = next
                    isRechecking = false
                }
            }
        }
    }

    /// Prompts the user for Apple Music automation permission via
    /// `MusicPermissionChecker.requestAccess()` and refreshes the UI state.
    private func requestAccess() {
        isRequesting = true
        Task {
            let resolved = MusicPermissionChecker.requestAccess()
            permissionState = resolved
            isRequesting = false
        }
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
        if let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension") {
            NSWorkspace.shared.open(url)
        }
    }
}

// MARK: - Preview

#Preview {
    OnboardingPermissionsStepView()
        .frame(width: 600, height: 520)
}
