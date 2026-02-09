//
//  AdvancedSettingsView.swift
//  wolfwave
//
//  Created by MrDemonWolf, Inc. on 1/17/26.
//

import SwiftUI

/// Advanced settings interface for dangerous operations.
///
/// Provides controls for:
/// - Resetting the onboarding wizard so it shows again on next launch
/// - Resetting all application settings to defaults
/// - Clearing stored authentication tokens from Keychain
/// - Disconnecting from Twitch
///
/// This view emphasizes the destructive nature of certain actions
/// through visual design (red colors, warning icon) and confirmation dialogs.
///
/// State:
/// - Uses @Binding for showingResetAlert (passed from parent SettingsView)
/// - Shares context with AppDelegate via NSApplication.shared.delegate
///
/// Actions:
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

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Section Header
            VStack(alignment: .leading, spacing: 6) {
                Text("Advanced")
                    .font(.system(size: 17, weight: .semibold))

                Text("Manage your setup wizard and reset WolfWave to its default state.")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }

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
    }
}

// MARK: - Preview

#Preview {
    @Previewable @State var showingResetAlert = false
    AdvancedSettingsView(showingResetAlert: $showingResetAlert)
        .padding()
}
