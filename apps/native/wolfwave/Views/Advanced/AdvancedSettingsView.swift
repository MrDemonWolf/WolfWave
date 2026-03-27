//
//  AdvancedSettingsView.swift
//  wolfwave
//
//  Created by MrDemonWolf, Inc. on 1/17/26.
//

import SwiftUI
import UniformTypeIdentifiers

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

    /// Whether a software update is available.
    @State private var updateAvailable = false

    /// The latest version string from GitHub Releases.
    @State private var latestVersion: String?

    /// Version the user chose to skip.
    @AppStorage(AppConstants.UserDefaults.updateSkippedVersion)
    private var skippedVersion: String = ""

    /// Reference to AppDelegate for Sparkle updater access.
    private var appDelegate: AppDelegate? { AppDelegate.shared }

    /// Whether automatic update checking is enabled.
    @AppStorage(AppConstants.UserDefaults.updateCheckEnabled)
    private var updateCheckEnabled = true

    /// Whether a manual update check is in progress.
    @State private var isCheckingForUpdates = false

    /// Whether the last update check was triggered manually (vs automatic/scheduled).
    @State private var isManualCheck = false

    /// Whether the "up to date" alert is shown after a manual check.
    @State private var showingUpToDateAlert = false

    /// Whether the app was installed via Homebrew (Sparkle is disabled in this case)
    @State private var isHomebrewInstall = false

    /// Current app version from the bundle.
    private var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown"
    }

    /// Opens a save panel to export the application log file.
    private func exportLogs() {
        guard let logURL = Log.exportLogFile() else {
            Log.warn("No log file available for export", category: "App")
            return
        }

        let panel = NSSavePanel()
        panel.nameFieldStringValue = "wolfwave-logs.log"
        panel.allowedContentTypes = [.plainText]
        panel.canCreateDirectories = true

        panel.begin { response in
            guard response == .OK, let destination = panel.url else { return }
            do {
                if FileManager.default.fileExists(atPath: destination.path) {
                    try FileManager.default.removeItem(at: destination)
                }
                try FileManager.default.copyItem(at: logURL, to: destination)
                Log.info("Logs exported to \(destination.lastPathComponent)", category: "App")
            } catch {
                Log.error("Failed to export logs: \(error.localizedDescription)", category: "App")
            }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Section Header
            VStack(alignment: .leading, spacing: 6) {
                Text("Advanced")
                    .sectionHeader()

                Text("Updates, diagnostics, and reset options.")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }

            // Software Update
            softwareUpdateCard

            Divider()
                .padding(.vertical, 4)

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

            // Log Export Card
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Diagnostics")
                        .font(.system(size: 13, weight: .semibold))

                    Text("Export application logs for debugging and support.")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Button(action: exportLogs) {
                    Label("Export Logs", systemImage: "square.and.arrow.up")
                        .font(.system(size: 13, weight: .medium))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.regular)
                .pointerCursor()
                .accessibilityLabel("Export application logs")
                .accessibilityHint("Save logs to a file for debugging")
            }
            .padding(AppConstants.SettingsUI.cardPadding)
            .background(Color(nsColor: .controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: AppConstants.SettingsUI.cardCornerRadius))

            Divider()
                .padding(.vertical, 4)

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

                    Text("Permanently erases all settings and saved accounts. This can't be undone.")
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
        .onAppear {
            // Detect if installed via Homebrew
            let path = Bundle.main.bundlePath
            let homebrewPaths = ["/opt/homebrew/", "/usr/local/Cellar/", "/Homebrew/"]
            isHomebrewInstall = homebrewPaths.contains { path.contains($0) }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name(AppConstants.Notifications.updateStateChanged))) { notification in
            isCheckingForUpdates = false
            if let version = notification.userInfo?["latestVersion"] as? String,
               let available = notification.userInfo?["isUpdateAvailable"] as? Bool {
                latestVersion = version
                updateAvailable = available && skippedVersion != version

                if !available && isManualCheck {
                    showingUpToDateAlert = true
                }
                isManualCheck = false
            }
        }
    }

    // MARK: - Software Update Card

    @ViewBuilder
    private var softwareUpdateCard: some View {
        if isHomebrewInstall {
            homebrewUpdateCard
        } else {
            sparkleUpdateCard
        }
    }

    /// Update card shown for Homebrew installations (Sparkle disabled)
    @ViewBuilder
    private var homebrewUpdateCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Software Update")
                    .font(.system(size: 13, weight: .semibold))

                Text("Current version: \(currentVersion)")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 10) {
                Image(systemName: "info.circle.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(.blue)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Homebrew Installation Detected")
                        .font(.system(size: 12, weight: .semibold))
                    Text("Use Homebrew to check for and install updates.")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(10)
            .background(Color.blue.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 6))

            HStack(spacing: 8) {
                Text("$ brew upgrade wolfwave")
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(.primary)

                Spacer()

                CopyButton(
                    text: "brew upgrade wolfwave",
                    buttonStyle: .borderless,
                    accessibilityLabel: "Copy brew command"
                )
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(Color(nsColor: .textBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .cardStyle()
    }

    /// Update card shown for DMG installations (uses Sparkle)
    @ViewBuilder
    private var sparkleUpdateCard: some View {
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

            #if DEBUG
            // Development build indicator
            HStack(spacing: 10) {
                Image(systemName: "hammer.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(.orange)

                Text("Development Build — update checks use dev-appcast.xml")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(10)
            .background(Color.orange.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 6))
            #endif

            // Info banner reflecting actual toggle state
            if updateCheckEnabled && !updateAvailable {
                HStack(spacing: 10) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(.green)

                    Text("Automatic updates enabled — you'll be notified when new versions are available.")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
                .background(Color.green.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 6))
            } else if !updateCheckEnabled && !updateAvailable {
                HStack(spacing: 10) {
                    Image(systemName: "info.circle.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)

                    Text("Automatic updates are off. Use Check Now to look for updates.")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
                .background(Color.gray.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 6))
            }

            Divider()

            // Bottom row: auto-check toggle + Check Now button
            HStack {
                Toggle("Check automatically", isOn: Binding(
                    get: { appDelegate?.sparkleUpdater?.automaticCheckEnabled ?? true },
                    set: { newValue in
                        appDelegate?.sparkleUpdater?.automaticCheckEnabled = newValue
                    }
                ))
                .toggleStyle(.checkbox)
                .font(.system(size: 12))

                Spacer()

                Button {
                    isCheckingForUpdates = true
                    isManualCheck = true
                    appDelegate?.sparkleUpdater?.checkForUpdates()
                    // Reset after a delay — Sparkle's delegate callbacks
                    // will update the UI with actual results.
                    DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
                        isCheckingForUpdates = false
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
        .alert("You're up to date!", isPresented: $showingUpToDateAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("WolfWave v\(currentVersion) is the latest version.")
        }
    }
}

// MARK: - Preview

#Preview("Default State") {
    @Previewable @State var showingResetAlert = false
    AdvancedSettingsView(showingResetAlert: $showingResetAlert)
        .padding()
        .frame(width: 700)
}
#Preview("With Update Available") {
    @Previewable @State var showingResetAlert = false
    @Previewable @AppStorage(AppConstants.UserDefaults.updateCheckEnabled) var updateCheckEnabled = true
    
    let view = AdvancedSettingsView(showingResetAlert: $showingResetAlert)
    return view
        .padding()
        .frame(width: 700)
        .onAppear {
            NotificationCenter.default.post(
                name: NSNotification.Name(AppConstants.Notifications.updateStateChanged),
                object: nil,
                userInfo: [
                    "latestVersion": "1.2.0",
                    "isUpdateAvailable": true
                ]
            )
        }
}

#Preview("Checking for Updates") {
    @Previewable @State var showingResetAlert = false
    
    struct CheckingView: View {
        var body: some View {
            VStack(alignment: .leading, spacing: 16) {
                Text("Advanced")
                    .sectionHeader()

                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Software Update")
                                .font(.system(size: 13, weight: .semibold))
                            
                            Text("Current version: 1.1.0")
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                    
                    Divider()
                    
                    HStack {
                        Toggle("Check automatically", isOn: .constant(true))
                            .toggleStyle(.checkbox)
                            .font(.system(size: 12))
                        
                        Spacer()
                        
                        ProgressView()
                            .controlSize(.small)
                            .frame(width: 14, height: 14)
                    }
                }
                .cardStyle()
            }
        }
    }
    
    return CheckingView()
        .padding()
        .frame(width: 700)
}

