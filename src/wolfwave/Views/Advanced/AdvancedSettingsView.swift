//
//  AdvancedSettingsView.swift
//  wolfwave
//
//  Created by MrDemonWolf, Inc. on 1/17/26.
//

import SwiftUI

/// Advanced settings interface providing software update controls and dangerous operations.
///
/// Provides controls for:
/// - Checking for software updates (manual and automatic)
/// - Resetting the onboarding wizard so it shows again on next launch
/// - Resetting all application settings to defaults
/// - Clearing stored authentication tokens from Keychain
/// - Disconnecting from Twitch
///
/// State:
/// - Uses @Binding for showingResetAlert (passed from parent SettingsView)
/// - Shares context with AppDelegate via NSApplication.shared.delegate
///
/// Actions:
/// - Software Update card shows current version, update availability, and install instructions
/// - Reset Onboarding clears the onboarding flag so the wizard runs on next launch
/// - Reset All button shows confirmation dialog before proceeding
/// - Actual full reset is performed by SettingsView.resetSettings()
struct AdvancedSettingsView: View {
    // MARK: - State

    /// Whether the reset confirmation alert is currently shown.
    ///
    /// Passed as binding from parent to control alert visibility.
    @Binding var showingResetAlert: Bool

    /// Whether the onboarding reset confirmation alert is shown.
    @State private var showingOnboardingResetAlert = false

    /// Whether automatic update checking is enabled.
    @AppStorage(AppConstants.UserDefaults.updateCheckEnabled)
    private var updateCheckEnabled = true

    /// Version string the user chose to skip.
    @AppStorage(AppConstants.UserDefaults.updateSkippedVersion)
    private var skippedVersion: String = ""

    /// Latest version reported by the update checker.
    @State private var latestVersion: String?

    /// Whether an update is currently available (respects skipped version).
    @State private var updateAvailable = false

    /// Whether a manual check is in progress.
    @State private var isCheckingForUpdates = false

    /// Current app version from bundle.
    private var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"
    }

    /// Reference to the AppDelegate for accessing the update checker.
    private var appDelegate: AppDelegate? {
        AppDelegate.shared
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Section Header
            VStack(alignment: .leading, spacing: 6) {
                Text("Advanced")
                    .font(.system(size: 17, weight: .semibold))

                Text("Check for updates, manage your setup wizard, and reset WolfWave to its default state.")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }

            // Software Update Card
            softwareUpdateCard

            // Onboarding Card
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Setup Wizard")
                        .font(.system(size: 13, weight: .semibold))

                    Text("Walk through the initial setup steps again to reconfigure your integrations.")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Button(action: { showingOnboardingResetAlert = true }) {
                    Label("Rerun Setup Wizard", systemImage: "arrow.counterclockwise")
                        .font(.system(size: 13, weight: .medium))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.regular)
                .pointerCursor()
                .accessibilityLabel("Reset onboarding wizard")
                .accessibilityHint("Opens the setup wizard")
            }
            .cardStyle()
            .alert("Reset Onboarding?", isPresented: $showingOnboardingResetAlert) {
                Button("Cancel", role: .cancel) {}
                Button("Reset") {
                    UserDefaults.standard.removeObject(forKey: AppConstants.UserDefaults.hasCompletedOnboarding)
                    Log.info("Onboarding reset by user", category: "Onboarding")
                    AppDelegate.shared?.showOnboarding()
                }
            } message: {
                Text("This will open the setup wizard. Your current settings will not be changed.")
            }

            // Danger Zone Card
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 14))
                            .foregroundStyle(.red)
                        Text("Danger Zone")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.red)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("Danger Zone")

                    Text("This will erase all preferences, remove saved accounts from Keychain, and disconnect from Twitch and Discord. This cannot be undone.")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Button(role: .destructive, action: { showingResetAlert = true }) {
                    Label("Reset All Settings to Defaults", systemImage: "trash.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)
                .tint(.red)
                .pointerCursor()
                .accessibilityLabel("Reset all settings to defaults")
                .accessibilityHint("Permanently delete all settings and stored credentials")
                .accessibilityIdentifier("resetAllSettingsButton")
            }
            .padding(AppConstants.SettingsUI.cardPadding)
            .background(Color.red.opacity(0.06))
            .clipShape(RoundedRectangle(cornerRadius: AppConstants.SettingsUI.cardCornerRadius))
            .overlay(
                RoundedRectangle(cornerRadius: AppConstants.SettingsUI.cardCornerRadius)
                    .stroke(Color.red.opacity(0.2), lineWidth: 1)
            )
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name(AppConstants.Notifications.updateStateChanged))) { notification in
            if let version = notification.userInfo?["latestVersion"] as? String,
               let available = notification.userInfo?["isUpdateAvailable"] as? Bool {
                latestVersion = version
                updateAvailable = available && skippedVersion != version
            }
        }
    }

    // MARK: - Software Update Card

    @ViewBuilder
    private var softwareUpdateCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header row: title + version badge
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Software Update")
                        .font(.system(size: 13, weight: .semibold))

                    Text("Current version: \(currentVersion)")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if updateAvailable, let version = latestVersion {
                    Text("v\(version) available")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.accentColor)
                        .clipShape(Capsule())
                }
            }

            // Update instructions (only when update is available)
            if updateAvailable {
                let installMethod = appDelegate?.updateChecker?.detectInstallMethod() ?? .dmg

                if installMethod == .homebrew {
                    // Homebrew command
                    HStack(spacing: 8) {
                        Text("$ brew upgrade wolfwave")
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(.primary)

                        Spacer()

                        Button {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString("brew upgrade wolfwave", forType: .string)
                        } label: {
                            Image(systemName: "doc.on.doc")
                                .font(.system(size: 11))
                        }
                        .buttonStyle(.borderless)
                        .pointerCursor()
                        .accessibilityLabel("Copy brew command")
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(Color(nsColor: .textBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                } else {
                    // DMG download button
                    Button {
                        openDownloadURL()
                    } label: {
                        Label("Download Update", systemImage: "arrow.down.circle.fill")
                            .font(.system(size: 13, weight: .medium))
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.regular)
                    .pointerCursor()
                    .accessibilityLabel("Download update")
                }

                // Skip This Version
                Button {
                    if let version = latestVersion {
                        skippedVersion = version
                        updateAvailable = false
                        Log.info("UpdateChecker: User skipped version \(version)", category: "Update")
                    }
                } label: {
                    Text("Skip This Version")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .pointerCursor()
                .accessibilityLabel("Skip this version")
            }

            Divider()

            // Bottom row: auto-check toggle + Check Now button
            HStack {
                Toggle("Check automatically", isOn: $updateCheckEnabled)
                    .toggleStyle(.checkbox)
                    .font(.system(size: 12))
                    .onChange(of: updateCheckEnabled) { _, newValue in
                        if newValue {
                            appDelegate?.updateChecker?.startPeriodicChecking()
                        } else {
                            appDelegate?.updateChecker?.stopPeriodicChecking()
                        }
                    }

                Spacer()

                Button {
                    isCheckingForUpdates = true
                    Task {
                        // Clear the interval gate so manual check always runs
                        UserDefaults.standard.removeObject(forKey: AppConstants.UserDefaults.updateLastCheckDate)
                        let info = await appDelegate?.updateChecker?.checkForUpdates()
                        await MainActor.run {
                            isCheckingForUpdates = false
                            if let info {
                                latestVersion = info.latestVersion
                                updateAvailable = info.isUpdateAvailable && skippedVersion != info.latestVersion
                            }
                        }
                    }
                } label: {
                    if isCheckingForUpdates {
                        ProgressView()
                            .controlSize(.small)
                            .frame(width: 14, height: 14)
                    } else {
                        Text("Check Now")
                            .font(.system(size: 12, weight: .medium))
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(isCheckingForUpdates)
                .pointerCursor()
                .accessibilityLabel("Check for updates now")
            }
        }
        .cardStyle()
    }

    // MARK: - Helpers

    /// Opens the DMG download URL or falls back to the GitHub releases page.
    private func openDownloadURL() {
        let url = appDelegate?.updateChecker?.latestUpdateInfo?.downloadURL
            ?? appDelegate?.updateChecker?.latestUpdateInfo?.releaseURL
            ?? URL(string: AppConstants.URLs.githubReleases)

        if let url {
            NSWorkspace.shared.open(url)
        }
    }
}

// MARK: - Preview

#Preview {
    @Previewable @State var showingResetAlert = false
    AdvancedSettingsView(showingResetAlert: $showingResetAlert)
        .padding()
}
