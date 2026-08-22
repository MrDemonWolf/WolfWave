//
//  DebugUIPreviewsCard.swift
//  WolfWave
//
//  Created by Nathanial Henniges on 2026-05-16.
//  Copyright © 2026 MrDemonWolf, Inc. All rights reserved.
//

#if DEBUG
import SwiftUI

/// DEBUG-only card for previewing in-app UI surfaces without normal triggers.
///
/// Includes shortcuts to the What's New popup, the onboarding wizard, and a
/// simulated update banner so designers can iterate without bumping versions.
struct DebugUIPreviewsCard: View {

    var body: some View {
        VStack(alignment: .leading, spacing: DSSpace.s4) {
            Text("Trigger popups, banners, and onboarding without the usual gating.")
                .font(.system(size: DSFont.Size.body))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Button {
                AppDelegate.shared?.showWhatsNew()
            } label: {
                Label("Preview What's New Popup", systemImage: "sparkles")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .pointerCursor()

            Button {
                DefaultsStore.store.removeObject(forKey: AppConstants.UserDefaults.lastSeenWhatsNewVersion)
                Log.info("Reset lastSeenWhatsNewVersion (dev)", category: .whatsNew)
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
                DefaultsStore.store.removeObject(forKey: AppConstants.UserDefaults.hasCompletedOnboarding)
                Log.info("Reset hasCompletedOnboarding (dev)", category: .onboarding)
            } label: {
                Label("Reset Onboarding Completion Flag", systemImage: "arrow.counterclockwise")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .pointerCursor()

            Divider().padding(.vertical, DSSpace.s1)

            Button {
                NotificationCenter.default.postUpdateState(
                    isUpdateAvailable: true,
                    latestVersion: "99.0.0"
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
