//
//  OnboardingPreferencesStepView.swift
//  wolfwave
//
//  Created by MrDemonWolf, Inc. on 5/7/26.
//

import AppKit
import SwiftUI
import UserNotifications

/// Preferences step — wire up the two macOS-level conveniences (launch at login,
/// notifications) so the user doesn't have to hunt for them in Settings later.
struct OnboardingPreferencesStepView: View {

    // MARK: - Properties

    @Binding var launchAtLogin: Bool

    @State private var notificationsStatus: UNAuthorizationStatus = .notDetermined

    // MARK: - Body

    var body: some View {
        VStack(spacing: 16) {
            Spacer(minLength: 0)

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
                    Image(systemName: "gearshape.fill")
                        .font(.system(size: 26, weight: .semibold))
                        .foregroundStyle(.white)
            )

            VStack(spacing: 6) {
                Text("A couple Mac settings")
                    .font(.system(size: 20, weight: .bold))

                Text("Start WolfWave at login, and get notified when something needs attention.")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 440)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(spacing: 10) {
                preferenceRow(
                    icon: "power",
                    iconColor: .green,
                    title: "Start WolfWave at login",
                    subtitle: "Starts in the menu bar — no Dock icon clutter.",
                    isOn: Binding(
                        get: { launchAtLogin },
                        set: { newValue in
                            guard LaunchAtLoginService.setEnabled(newValue) else { return }
                            launchAtLogin = newValue
                        }
                    ),
                    accessibilityLabel: "Start WolfWave at login",
                    accessibilityIdentifier: "onboardingLaunchAtLoginToggle"
                )

                notificationsRow
            }
            .frame(maxWidth: 440)
            .padding(.horizontal, 24)

            Spacer(minLength: 0)
        }
        .task {
            await refreshNotificationStatus()
        }
    }

    // MARK: - Notifications Row

    /// Notifications row with three states:
    ///   - notDetermined → toggle requests authorization
    ///   - authorized / provisional → toggle is on, locked
    ///   - denied → button deep-links to System Settings → Notifications
    @ViewBuilder
    private var notificationsRow: some View {
        let isAuthorized = notificationsStatus == .authorized || notificationsStatus == .provisional

        preferenceRow(
            icon: "bell.badge.fill",
            iconColor: .red,
            title: "Allow notifications",
            subtitle: notificationsStatus == .denied
                ? "Enable in System Settings so we can ping you about updates."
                : "We'll only ping for important things — updates, reconnect prompts.",
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
    }

    // MARK: - Row

    /// Builds a single labeled toggle row used in the preferences step:
    /// colored icon tile, title, subtitle, and a binding switch.
    ///
    /// - Parameters:
    ///   - icon: SF Symbol name shown in the colored tile.
    ///   - iconColor: Accent color for the tile background and glyph.
    ///   - title: Primary row title.
    ///   - subtitle: Supporting copy under the title.
    ///   - isOn: Two-way binding to the underlying boolean preference.
    ///   - accessibilityLabel: VoiceOver label for the toggle.
    ///   - accessibilityIdentifier: UI-testing identifier for the toggle.
    /// - Returns: A styled preference row.
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
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(iconColor.opacity(0.15))
                    .frame(width: 32, height: 32)

                Image(systemName: icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(iconColor)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))

                Text(subtitle)
                    .font(.system(size: 11))
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
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.primary.opacity(0.06), lineWidth: 0.5)
        )
    }

    // MARK: - Notifications

    /// Queries the current notification authorization status and updates the
    /// view state on the main actor. Used to re-sync the UI after a user
    /// flips the toggle in System Settings.
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
    OnboardingPreferencesStepView(launchAtLogin: .constant(false))
        .frame(width: 600, height: 480)
}
