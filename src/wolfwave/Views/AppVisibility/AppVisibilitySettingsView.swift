//
//  AppVisibilitySettingsView.swift
//  wolfwave
//
//  Created by MrDemonWolf, Inc. on 1/13/26.
//

import SwiftUI

/// App visibility settings interface for controlling dock and menu bar presence.
struct AppVisibilitySettingsView: View {
    // MARK: - User Settings
    
    @AppStorage("dockVisibility")
    private var dockVisibility = "both"
    
    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Image(systemName: "eye")
                        .font(.title3)
                    Text("App Visibility")
                        .font(.title2)
                        .fontWeight(.semibold)
                }
                
                Text("Choose where WolfWave appears on your Mac.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            
            Divider()
            
            VStack(alignment: .leading, spacing: 12) {
                Text("Show app in:")
                    .font(.body)
                    .fontWeight(.medium)
                
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
            }
        }
    }
    
    // MARK: - Helpers
    
    private func applyDockVisibility(_ mode: String) {
        NotificationCenter.default.post(
            name: NSNotification.Name("DockVisibilityChanged"),
            object: nil,
            userInfo: ["mode": mode]
        )
    }
}
