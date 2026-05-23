//
//  DebugUIPreviewsCard.swift
//  wolfwave
//
//  Created by MrDemonWolf, Inc. on 5/16/26.
//

#if DEBUG
import SwiftUI

/// DEBUG-only card for previewing in-app UI surfaces without normal triggers.
///
/// Includes shortcuts to the What's New popup, the onboarding wizard, and a
/// simulated update banner so designers can iterate without bumping versions.
struct DebugUIPreviewsCard: View {
    @State private var showingWhatsNewVersionPicker = false
    @State private var customVersion: String = "99.0.0"

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                Image(systemName: "eye.fill")
                    .foregroundStyle(.purple)
                Text("UI Previews")
                    .sectionSubHeader()
            }

            Text("Trigger popups, banners, and onboarding without the usual gating.")
                .font(.system(size: DSFont.Size.body))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Button {
                let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
                AppDelegate.shared?.showWhatsNew(version: version)
            } label: {
                Label("Preview What's New Popup", systemImage: "sparkles")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .pointerCursor()

            HStack(spacing: 8) {
                TextField("Version (e.g. 99.0.0)", text: $customVersion)
                    .textFieldStyle(.roundedBorder)
                Button("Show") {
                    AppDelegate.shared?.showWhatsNew(version: customVersion)
                }
                .buttonStyle(.bordered)
                .pointerCursor()
            }

            Button {
                UserDefaults.standard.removeObject(forKey: AppConstants.UserDefaults.lastSeenWhatsNewVersion)
                Log.info("Reset lastSeenWhatsNewVersion (dev)", category: "WhatsNew")
            } label: {
                Label("Reset 'Seen' Flag (next launch shows popup)", systemImage: "arrow.counterclockwise")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .pointerCursor()

            Divider().padding(.vertical, DSSpace.s1)

            Button {
                AppDelegate.shared?.showOnboarding()
            } label: {
                Label("Open Onboarding Wizard", systemImage: "wand.and.stars")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .pointerCursor()

            Button {
                UserDefaults.standard.removeObject(forKey: AppConstants.UserDefaults.hasCompletedOnboarding)
                Log.info("Reset hasCompletedOnboarding (dev)", category: "Onboarding")
            } label: {
                Label("Reset Onboarding Completion Flag", systemImage: "arrow.counterclockwise")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .pointerCursor()

            Divider().padding(.vertical, DSSpace.s1)

            Button {
                NotificationCenter.default.post(
                    name: .updateStateChanged,
                    object: nil,
                    userInfo: [
                        "isUpdateAvailable": true,
                        "latestVersion": "99.0.0",
                    ]
                )
            } label: {
                Label("Simulate Update Available", systemImage: "arrow.down.app")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .pointerCursor()
        }
        .cardStyle()
    }
}

#Preview {
    DebugUIPreviewsCard()
        .padding()
        .frame(width: 600)
}
#endif
