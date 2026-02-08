//
//  DiscordSettingsView.swift
//  wolfwave
//
//  Created by MrDemonWolf, Inc. on 2/7/26.
//

import SwiftUI

/// Settings for Discord Rich Presence integration.
///
/// Displays an enable/disable toggle and a status chip showing the current
/// connection state (Connected, Not connected, Discord not running).
///
/// When enabled, WolfWave shows "Listening to Apple Music" on the user's
/// Discord profile with the current track, artist, album, and progress bar.
struct DiscordSettingsView: View {
    // MARK: - User Settings

    /// Whether Discord Rich Presence is currently enabled.
    @AppStorage(AppConstants.UserDefaults.discordPresenceEnabled)
    private var presenceEnabled = false

    // MARK: - State

    /// Current Discord connection state, updated via notification from AppDelegate.
    @State private var connectionState: DiscordRPCService.ConnectionState = .disconnected

    /// Whether a valid Discord Client ID is configured.
    private var hasClientID: Bool {
        DiscordRPCService.resolveClientID() != nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Section Header
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .center, spacing: 10) {
                    Text("Discord Rich Presence")
                        .font(.system(size: 17, weight: .semibold))

                    Spacer()

                    statusChip
                        .animation(.easeInOut(duration: 0.2), value: connectionState)
                }

                Text("Show what you're listening to on your Discord profile, just like Spotify does.")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            // Toggle Card
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Enable Discord Rich Presence")
                        .font(.system(size: 13, weight: .medium))
                    Text("Shows current track on your Discord profile")
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                }
                Spacer()
                Toggle("", isOn: $presenceEnabled)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .pointerCursor()
                    .disabled(!hasClientID)
                    .accessibilityLabel("Enable Discord Rich Presence")
                    .accessibilityHint("Toggle to enable or disable Discord Rich Presence")
                    .accessibilityIdentifier("discordPresenceToggle")
                    .onChange(of: presenceEnabled) { _, newValue in
                        notifyPresenceSettingChanged(enabled: newValue)
                    }
            }
            .padding(AppConstants.SettingsUI.cardPadding)
            .background(Color(nsColor: .controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: AppConstants.SettingsUI.cardCornerRadius))

            if !hasClientID {
                Text("Set DISCORD_CLIENT_ID in Config.xcconfig to enable this feature.")
                    .font(.system(size: 11))
                    .foregroundStyle(.orange)
            }
        }
        .onAppear {
            refreshConnectionState()
        }
        .onReceive(
            NotificationCenter.default.publisher(
                for: NSNotification.Name(AppConstants.Notifications.discordStateChanged)
            )
        ) { notification in
            if let rawValue = notification.userInfo?["state"] as? String {
                switch rawValue {
                case "connected":
                    connectionState = .connected
                case "connecting":
                    connectionState = .connecting
                default:
                    connectionState = .disconnected
                }
            }
        }
    }

    // MARK: - Subviews

    @ViewBuilder
    private var statusChip: some View {
        switch connectionState {
        case .connected:
            StatusChip(text: "Connected", color: .green)
        case .connecting:
            StatusChip(text: "Connecting", color: .orange)
        case .disconnected:
            if presenceEnabled {
                StatusChip(text: "Discord not running", color: .gray)
            } else {
                StatusChip(text: "Disabled", color: .gray)
            }
        }
    }

    // MARK: - Helpers

    /// Reads the current connection state from the AppDelegate's Discord service.
    private func refreshConnectionState() {
        if let appDelegate = AppDelegate.shared {
            connectionState = appDelegate.discordService?.state ?? .disconnected
        }
    }

    /// Posts a notification when Discord presence is toggled.
    private func notifyPresenceSettingChanged(enabled: Bool) {
        NotificationCenter.default.post(
            name: NSNotification.Name(AppConstants.Notifications.discordPresenceChanged),
            object: nil,
            userInfo: ["enabled": enabled]
        )
    }
}

// MARK: - Status Chip

private struct StatusChip: View {
    let text: String
    let color: Color

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(color)
                .frame(width: 6, height: 6)

            Text(text)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.primary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(color.opacity(0.1))
        .clipShape(Capsule())
    }
}

// MARK: - Preview

#Preview {
    DiscordSettingsView()
        .padding()
}
