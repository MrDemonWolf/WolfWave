//
//  MusicPermissionBanner.swift
//  WolfWave
//
//  Created by Nathanial Henniges on 2026-05-24.
//  Copyright © 2026 MrDemonWolf, Inc. All rights reserved.
//

import SwiftUI

/// Reusable orange warning card shown when Apple Music access is missing.
///
/// Currently covers Apple Events automation permission (`MusicPermissionChecker`),
/// which is what `AppleMusicSource` relies on to read the currently-playing
/// track. The MusicKit `MusicAuthorization` flow used by Song Requests is
/// rendered by a separate fileprivate card in `SongRequestSettingsView` —
/// migrating that to this banner is tracked as future cleanup.
///
/// Render conditionally: the banner does not self-gate, so callers should
/// only place it when `state == .denied`.
struct MusicPermissionBanner: View {

    // MARK: - Properties

    /// User-facing copy describing what the missing permission blocks.
    let message: String

    /// Triggered when the user taps "Open System Settings".
    var onOpenSettings: @MainActor () -> Void = { MusicPermissionChecker.openAutomationSettings() }

    // MARK: - Body

    var body: some View {
        VStack(alignment: .leading, spacing: DSSpace.s4) {
            WarningBanner(text: message)

            Button {
                onOpenSettings()
            } label: {
                Text("Open System Settings")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .tint(.orange)
            .accessibilityIdentifier("musicPermissionOpenSettings")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Apple Music permission required. \(message)")
    }
}

#Preview {
    MusicPermissionBanner(
        message: "WolfWave can't read the currently playing track. Enable Apple Music automation in System Settings → Privacy & Security → Automation.",
        onOpenSettings: {}
    )
    .padding()
    .frame(width: 520)
}
