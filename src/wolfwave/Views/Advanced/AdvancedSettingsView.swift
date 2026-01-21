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
/// - Resetting all application settings to defaults
/// - Clearing stored authentication tokens from Keychain
/// - Disconnecting from Twitch
/// - Clearing track history
///
/// This view emphasizes the destructive nature of the actions
/// through visual design (red colors, warning icon) and confirmation dialogs.
///
/// State:
/// - Uses @Binding for showingResetAlert (passed from parent SettingsView)
/// - Shares context with AppDelegate via NSApplication.shared.delegate
///
/// Actions:
/// - Reset button shows confirmation dialog before proceeding
/// - Actual reset is performed by SettingsView.resetSettings()
struct AdvancedSettingsView: View {
    // MARK: - State
    
    /// Whether the reset confirmation alert is currently shown.
    ///
    /// Passed as binding from parent to control alert visibility.
    @Binding var showingResetAlert: Bool
    
    var body: some View {
        VStack(spacing: 20) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Advanced")
                    .font(.system(size: 17, weight: .semibold))
                
                Text("Reset all settings and clear stored credentials.")
                    .font(.system(size: 13, weight: .regular))
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.title3)
                            .foregroundStyle(.red)
                        Text("Danger Zone")
                            .font(.headline)
                            .foregroundStyle(.red)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("Danger Zone")
                    
                    Text("Resetting will permanently delete all your settings, clear stored credentials from Keychain, and disconnect any active services. This action cannot be undone.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
                .background(Color.red.opacity(0.1))
                .cornerRadius(8)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.red.opacity(0.3), lineWidth: 1)
                )
                
                Button(role: .destructive, action: { showingResetAlert = true }) {
                    Label("Reset All Settings to Defaults", systemImage: "trash.fill")
                        .font(.body)
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .tint(.red)
                .accessibilityLabel("Reset all settings to defaults")
                .accessibilityHint("Permanently delete all settings and stored credentials")
                .accessibilityIdentifier("resetAllSettingsButton")
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
    }
}

// MARK: - Preview

#Preview {
    @Previewable @State var showingResetAlert = false
    AdvancedSettingsView(showingResetAlert: $showingResetAlert)
        .padding()
}
