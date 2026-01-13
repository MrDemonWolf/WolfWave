//
//  AdvancedSettingsView.swift
//  wolfwave
//
//  Created by MrDemonWolf, Inc. on 1/13/26.
//

import SwiftUI

/// Advanced settings interface for resetting app configuration.
struct AdvancedSettingsView: View {
    // MARK: - State
    
    @Binding var showingResetAlert: Bool
    
    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Image(systemName: "gearshape")
                        .font(.title3)
                    Text("Advanced")
                        .font(.title2)
                        .fontWeight(.semibold)
                }
                
                Text("Reset all settings and clear stored credentials.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            
            Divider()
            
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
            }
        }
    }
}
