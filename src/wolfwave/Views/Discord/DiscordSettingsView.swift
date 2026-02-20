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

    /// Whether a test connection is in progress.
    @State private var isTesting = false

    /// Result message from the last test connection attempt.
    @State private var testResultMessage = ""

    /// Whether a valid Discord Client ID is configured.
    @State private var hasClientID = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Section Header
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .center, spacing: 10) {
                    Text("Discord Integration")
                        .font(.system(size: 17, weight: .semibold))

                    Spacer()

                    statusChip
                        .animation(.easeInOut(duration: 0.2), value: connectionState)
                }

                Text("Display your currently playing Apple Music track on your Discord profile, similar to Spotify's listening activity.")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            // Toggle Card
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Rich Presence")
                        .font(.system(size: 13, weight: .medium))
                    Text("Displays song, artist, and album art on your Discord profile")
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
            .cardStyle()

            // Test Connection
            if presenceEnabled && hasClientID {
                HStack(spacing: 10) {
                    Button {
                        testDiscordConnection()
                    } label: {
                        HStack(spacing: 6) {
                            if isTesting {
                                ProgressView()
                                    .progressViewStyle(.circular)
                                    .controlSize(.mini)
                            } else {
                                Image(systemName: "antenna.radiowaves.left.and.right")
                                    .font(.system(size: 11))
                            }
                            Text(isTesting ? "Testing…" : "Test Connection")
                                .font(.system(size: 12, weight: .medium))
                        }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(isTesting)
                    .pointerCursor()
                    .accessibilityLabel("Test Discord connection")
                    .accessibilityIdentifier("discordTestConnectionButton")

                    if !testResultMessage.isEmpty {
                        Text(testResultMessage)
                            .font(.system(size: 12))
                            .foregroundStyle(testResultMessage.contains("✅") ? .green : .red)
                            .transition(.opacity)
                    }

                    Spacer()
                }
            }

            if !hasClientID {
                Text("Set DISCORD_CLIENT_ID in Config.xcconfig to enable this feature.")
                    .font(.system(size: 11))
                    .foregroundStyle(.orange)
            }
        }
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
                StatusChip(text: "Disconnected", color: .gray)
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

    /// Tests the Discord IPC connection and displays a result message.
    private func testDiscordConnection() {
        isTesting = true
        testResultMessage = ""

        guard let service = AppDelegate.shared?.discordService else {
            testResultMessage = "❌ Discord service not available"
            isTesting = false
            return
        }

        service.testConnection { success in
            withAnimation {
                testResultMessage = success
                    ? "✅ Connected to Discord"
                    : "❌ Cannot reach Discord — is it running?"
                isTesting = false
            }

            // Auto-clear the message after 5 seconds
            DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
                withAnimation { testResultMessage = "" }
            }
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
