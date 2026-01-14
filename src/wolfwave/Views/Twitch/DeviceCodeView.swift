//
//  DeviceCodeView.swift
//  wolfwave
//
//  Created by MrDemonWolf, Inc. on 1/13/26.
//

import AppKit
import SwiftUI

/// View displaying the OAuth Device Code authorization UI during Twitch Device Code flow.
///
/// Presents the device code for manual entry and provides quick links to open Twitch
/// or visit twitch.tv/activate for authorization.
struct DeviceCodeView: View {
    let userCode: String
    let verificationURI: String
    let onCopy: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack(spacing: 8) {
                Image(systemName: "number")
                    .font(.title3)
                    .foregroundStyle(Color(nsColor: .controlAccentColor))
                Text("Authorize on Twitch")
                    .font(.body)
                    .fontWeight(.medium)
            }
            
            Text(
                "Open Twitch to authorize, or go to twitch.tv/activate on any device and enter this code."
            )
            .font(.caption)
            .foregroundColor(.secondary)

            // Device Code Display
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Device Code")
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(.secondary)
                    Text(userCode)
                        .font(.title3)
                        .monospaced()
                        .fontWeight(.bold)
                        .tracking(1)
                }
                Spacer()
                Button(action: copyToClipboard) {
                    Label("Copy", systemImage: "doc.on.doc")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            .padding(12)
            .background(Color(nsColor: .controlBackgroundColor))
            .cornerRadius(8)

            // Action Buttons
            VStack(spacing: 10) {
                Button(action: openTwitchAuthorization) {
                    Label("Open Twitch to authorize", systemImage: "link.circle.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)

                Link(
                    "Or visit twitch.tv/activate and enter the code",
                    destination: URL(string: "https://twitch.tv/activate")!
                )
                .font(.caption)
                .foregroundColor(.blue)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color(nsColor: .controlAccentColor).opacity(0.1))
        )
    }

    // MARK: - Private Methods

    private func copyToClipboard() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(userCode, forType: .string)
        onCopy()
    }

    private func openTwitchAuthorization() {
        if let url = URL(string: verificationURI) {
            NSWorkspace.shared.open(url)
        }
    }
}

#Preview {
    DeviceCodeView(
        userCode: "ABCD1234",
        verificationURI: "https://twitch.tv/activate",
        onCopy: { }
    )
}
