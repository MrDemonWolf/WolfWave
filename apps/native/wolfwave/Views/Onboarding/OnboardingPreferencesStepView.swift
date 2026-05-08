//
//  OnboardingPreferencesStepView.swift
//  wolfwave
//
//  Created by MrDemonWolf, Inc. on 5/7/26.
//

import SwiftUI
import UserNotifications

/// Preferences step — wire up the two macOS-level conveniences (launch at login,
/// notifications) so the user doesn't have to hunt for them in Settings later.
struct OnboardingPreferencesStepView: View {

    // MARK: - Properties

    @Binding var launchAtLogin: Bool

    @State private var notificationsAuthorized = false
    @State private var notificationsRequesting = false

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
                Text("A couple Mac things")
                    .font(.system(size: 20, weight: .bold))

                Text("Have WolfWave start when you log in, and let it ping you when something needs attention.")
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
                    title: "Open WolfWave at login",
                    subtitle: "Starts in the menu bar — no Dock icon clutter.",
                    isOn: Binding(
                        get: { launchAtLogin },
                        set: { newValue in
                            guard LaunchAtLoginService.setEnabled(newValue) else { return }
                            launchAtLogin = newValue
                        }
                    ),
                    accessibilityLabel: "Open WolfWave at login",
                    accessibilityIdentifier: "onboardingLaunchAtLoginToggle"
                )

                preferenceRow(
                    icon: "bell.badge.fill",
                    iconColor: .red,
                    title: "Allow notifications",
                    subtitle: "We'll only ping for important things — updates, reconnect prompts.",
                    isOn: Binding(
                        get: { notificationsAuthorized },
                        set: { newValue in
                            if newValue {
                                requestNotificationAuthorization()
                            }
                        }
                    ),
                    accessibilityLabel: "Allow notifications",
                    accessibilityIdentifier: "onboardingNotificationsToggle"
                )
            }
            .frame(maxWidth: 440)
            .padding(.horizontal, 24)

            Spacer(minLength: 0)
        }
        .task {
            await refreshNotificationStatus()
        }
    }

    // MARK: - Row

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

    private func refreshNotificationStatus() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        await MainActor.run {
            notificationsAuthorized = settings.authorizationStatus == .authorized ||
                                       settings.authorizationStatus == .provisional
        }
    }

    private func requestNotificationAuthorization() {
        notificationsRequesting = true
        Task {
            let granted = (try? await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .sound, .badge])) ?? false
            await MainActor.run {
                notificationsAuthorized = granted
                notificationsRequesting = false
            }
        }
    }
}

// MARK: - Preview

#Preview {
    OnboardingPreferencesStepView(launchAtLogin: .constant(false))
        .frame(width: 600, height: 480)
}
