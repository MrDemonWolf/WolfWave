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
    @State private var hasClientID = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            SectionHeaderWithStatus(
                title: "Discord Status",
                subtitle: "Show your music on your Discord profile.",
                statusText: statusChipText,
                statusColor: statusChipColor
            )

            // Toggle Card
            ToggleSettingRow(
                title: "Show Status",
                subtitle: "Displays the song and cover art on your profile",
                isOn: $presenceEnabled,
                isDisabled: !hasClientID,
                accessibilityLabel: "Enable Discord Status",
                accessibilityIdentifier: "discordPresenceToggle",
                accessibilityHint: "Toggle to enable or disable Discord Status",
                onChange: { newValue in
                    notifyPresenceSettingChanged(enabled: newValue)
                }
            )
            .cardStyle()

            // Test Connection
            if presenceEnabled && hasClientID {
                HStack(spacing: 10) {
                    ConnectionTestButton(
                        label: "Check Discord",
                        icon: "antenna.radiowaves.left.and.right"
                    ) { completion in
                        guard let service = AppDelegate.shared?.discordService else {
                            completion(false)
                            return
                        }
                        service.testConnection(completion: completion)
                    }
                    .help("Checks if Discord is open and ready.")
                    .accessibilityLabel("Test Discord connection")
                    .accessibilityHint("Checks if Discord is open and ready to receive status updates")
                    .accessibilityIdentifier("discordTestConnectionButton")

                    Spacer()
                }
                .transition(.opacity)
            }

            if !hasClientID {
                ConfigRequiredBanner(message: "Set DISCORD_CLIENT_ID in Config.xcconfig to enable this feature.")
            }
        }
        .animation(.easeInOut(duration: 0.2), value: presenceEnabled)
        .onAppear {
            hasClientID = DiscordRPCService.resolveClientID() != nil
            refreshConnectionState()
        }
        .onReceive(
            NotificationCenter.default.publisher(
                for: NSNotification.Name(AppConstants.Notifications.discordStateChanged)
            )
        ) { notification in
            if let rawValue = notification.userInfo?["state"] as? String {
                withAnimation(.easeInOut(duration: 0.2)) {
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
    }

    // MARK: - Subviews

    private var statusChipText: String {
        switch connectionState {
        case .connected:
            return "Connected"
        case .connecting:
            return "Connecting"
        case .disconnected:
            return presenceEnabled ? "Discord not running" : "Disconnected"
        }
    }

    private var statusChipColor: Color {
        switch connectionState {
        case .connected:
            return .green
        case .connecting:
            return .orange
        case .disconnected:
            return .gray
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

// MARK: - Preview

#Preview("Disconnected") {
    @Previewable @AppStorage(AppConstants.UserDefaults.discordPresenceEnabled) var presenceEnabled = false
    
    DiscordSettingsView()
        .padding()
        .frame(width: 600)
}
#Preview("Connected") {
    @Previewable @AppStorage(AppConstants.UserDefaults.discordPresenceEnabled) var presenceEnabled = true
    
    let view = DiscordSettingsView()
    return view
        .padding()
        .frame(width: 600)
        .onAppear {
            NotificationCenter.default.post(
                name: NSNotification.Name(AppConstants.Notifications.discordStateChanged),
                object: nil,
                userInfo: ["state": "connected"]
            )
        }
}

#Preview("Connecting") {
    @Previewable @AppStorage(AppConstants.UserDefaults.discordPresenceEnabled) var presenceEnabled = true
    
    let view = DiscordSettingsView()
    return view
        .padding()
        .frame(width: 600)
        .onAppear {
            NotificationCenter.default.post(
                name: NSNotification.Name(AppConstants.Notifications.discordStateChanged),
                object: nil,
                userInfo: ["state": "connecting"]
            )
        }
}

#Preview("Discord Not Running") {
    @Previewable @AppStorage(AppConstants.UserDefaults.discordPresenceEnabled) var presenceEnabled = true
    
    let view = DiscordSettingsView()
    return view
        .padding()
        .frame(width: 600)
        .onAppear {
            NotificationCenter.default.post(
                name: NSNotification.Name(AppConstants.Notifications.discordStateChanged),
                object: nil,
                userInfo: ["state": "disconnected"]
            )
        }
}

