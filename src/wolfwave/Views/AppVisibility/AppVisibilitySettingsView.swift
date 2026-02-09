//
//  AppVisibilitySettingsView.swift
//  wolfwave
//
//  Created by MrDemonWolf, Inc. on 1/17/26.
//

import SwiftUI

/// App visibility settings interface for controlling dock and menu bar presence.
struct AppVisibilitySettingsView: View {
    // MARK: - User Settings
    
    @AppStorage(AppConstants.UserDefaults.dockVisibility)
    private var dockVisibility = AppConstants.DockVisibility.default
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Section Header
            VStack(alignment: .leading, spacing: 6) {
                Text("App Visibility")
                    .font(.system(size: 17, weight: .semibold))

                Text("Control how WolfWave appears in your Dock and menu bar.")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }

            // Picker Card
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Display Mode")
                        .font(.system(size: 13, weight: .medium))
                    Text("Choose where you want WolfWave to appear")
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                }

                Picker("", selection: $dockVisibility) {
                    Text("Dock and Menu Bar").tag("both")
                    Text("Menu Bar Only").tag("menuOnly")
                    Text("Dock Only").tag("dockOnly")
                }
                .pickerStyle(.radioGroup)
                .pointerCursor()
                .onChange(of: dockVisibility) { _, newValue in
                    applyDockVisibility(newValue)
                }
                .accessibilityLabel("Display mode")
                .accessibilityIdentifier("dockVisibilityPicker")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .cardStyle()

            // Info Notice
            if dockVisibility == "menuOnly" {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "info.circle.fill")
                        .font(.system(size: 13))
                        .foregroundStyle(.blue)
                    Text("The app will temporarily appear in the Dock while the settings window is open.")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.blue.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .accessibilityElement(children: .combine)
                .accessibilityLabel("The app will temporarily appear in the Dock while the settings window is open.")
                .transition(.opacity.combined(with: .move(edge: .top)))
                .animation(.easeInOut(duration: 0.2), value: dockVisibility)
            }
        }
    }
    
    // MARK: - Helpers
    
    private func applyDockVisibility(_ mode: String) {
        NotificationCenter.default.post(
            name: NSNotification.Name(AppConstants.Notifications.dockVisibilityChanged),
            object: nil,
            userInfo: ["mode": mode]
        )
    }
}

// MARK: - Preview

#Preview {
    AppVisibilitySettingsView()
        .padding()
}
