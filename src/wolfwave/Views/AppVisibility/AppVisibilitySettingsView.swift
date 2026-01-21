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
    
    @AppStorage("dockVisibility")
    private var dockVisibility = "both"
    
    var body: some View {
        VStack(spacing: 20) {
            VStack(alignment: .leading, spacing: 6) {
                Text("App Visibility")
                    .font(.system(size: 17, weight: .semibold))
                
                Text("Choose where WolfWave appears on your Mac.")
                    .font(.system(size: 13, weight: .regular))
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            
            VStack(alignment: .leading, spacing: 12) {
                Text("Show app in:")
                    .font(.body)
                    .fontWeight(.medium)
                    .accessibilityHidden(true)
                
                Picker("", selection: $dockVisibility) {
                    Text("Dock and Menu Bar").tag("both")
                    Text("Menu Bar Only").tag("menuOnly")
                    Text("Dock Only").tag("dockOnly")
                }
                .pickerStyle(.radioGroup)
                .frame(maxWidth: .infinity, alignment: .leading)
                .onChange(of: dockVisibility) { _, newValue in
                    applyDockVisibility(newValue)
                }
                .accessibilityLabel("Show app in")
                .accessibilityIdentifier("dockVisibilityPicker")
            }
            .padding(12)
            .background(Color(nsColor: .controlBackgroundColor))
            .cornerRadius(8)
            
            if dockVisibility == "menuOnly" {
                HStack(spacing: 8) {
                    Image(systemName: "info.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.blue)
                    Text("When menu bar only is enabled, the app will appear in the dock when settings are open.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(12)
                .background(Color.blue.opacity(0.1))
                .cornerRadius(8)
                .accessibilityElement(children: .combine)
                .accessibilityLabel("When menu bar only is enabled, the app will appear in the dock when settings are open.")
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
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
