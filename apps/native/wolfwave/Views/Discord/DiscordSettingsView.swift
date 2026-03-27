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

    /// Result of the "Test Connection" button.
    enum TestConnectionResult: Equatable {
        case idle
        case testing
        case success
        case failure
    }
    
    /// Current test connection result state.
    @State private var testConnectionResult: TestConnectionResult = .idle

    /// Task for clearing test result after delay.
    @State private var clearTask: Task<Void, Never>?

    /// Whether a valid Discord Client ID is configured.
    @State private var hasClientID = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Section Header
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .center, spacing: 10) {
                    Text("Discord Status")
                        .sectionHeader()

                    Spacer()

                    statusChip
                }

                Text("Show your music on your Discord profile.")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

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
                    Button {
                        testDiscordConnection()
                    } label: {
                        switch testConnectionResult {
                        case .idle:
                            Label("Check Discord", systemImage: "antenna.radiowaves.left.and.right")
                                .font(.system(size: 12, weight: .medium))
                        case .testing:
                            HStack(spacing: 6) {
                                ProgressView()
                                    .progressViewStyle(.circular)
                                    .controlSize(.mini)
                                Text("Testing...")
                                    .font(.system(size: 12))
                            }
                        case .success:
                            Label("Connected", systemImage: "checkmark.circle.fill")
                                .font(.system(size: 12, weight: .medium))
                        case .failure:
                            Label("Failed", systemImage: "xmark.circle.fill")
                                .font(.system(size: 12, weight: .medium))
                        }
                    }
                    .buttonStyle(.bordered)
                    .tint(testConnectionButtonTint)
                    .controlSize(.small)
                    .disabled(testConnectionResult == .testing)
                    .pointerCursor()
                    .help("Checks if Discord is open and ready.")
                    .accessibilityLabel("Test Discord connection")
                    .accessibilityIdentifier("discordTestConnectionButton")

                    Spacer()
                }
            }

            #if DEBUG
            if !hasClientID {
                Text("Set DISCORD_CLIENT_ID in Config.xcconfig to enable this feature.")
                    .font(.system(size: 11))
                    .foregroundStyle(.orange)
            }
            #endif
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

    @ViewBuilder
    private var statusChip: some View {
        StatusChip(text: statusChipText, color: statusChipColor)
            .accessibilityLabel("Discord status: \(statusChipText)")
    }

    // MARK: - Helpers

    /// Computed tint color for the test connection button based on result state.
    private var testConnectionButtonTint: Color? {
        switch testConnectionResult {
        case .success:
            return .green
        case .failure:
            return .red
        case .idle, .testing:
            return nil
        }
    }

    /// Reads the current connection state from the AppDelegate's Discord service.
    private func refreshConnectionState() {
        if let appDelegate = AppDelegate.shared {
            connectionState = appDelegate.discordService?.state ?? .disconnected
        }
    }

    /// Tests the Discord IPC connection and displays a result in the button.
    private func testDiscordConnection() {
        testConnectionResult = .testing

        guard let service = AppDelegate.shared?.discordService else {
            testConnectionResult = .failure
            scheduleResultReset()
            return
        }

        service.testConnection { success in
            withAnimation {
                testConnectionResult = success ? .success : .failure
            }
            scheduleResultReset()
        }
    }

    /// Resets the test connection result to idle after 3 seconds.
    private func scheduleResultReset() {
        clearTask?.cancel()
        clearTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            guard !Task.isCancelled else { return }
            withAnimation {
                testConnectionResult = .idle
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

