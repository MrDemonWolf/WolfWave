//
//  LoadingRow.swift
//  WolfWave
//
//  Created by Nathanial Henniges on 2026-05-26.
//  Copyright © 2026 MrDemonWolf, Inc. All rights reserved.
//

import SwiftUI

/// Inline row pairing a small circular `ProgressView` with a secondary label.
///
/// For short-lived async waits inside settings panes: connection tests,
/// onboarding handshake, "waiting for service" lines. Not a replacement for
/// `.skeleton(_:)` (first-paint redaction) or in-button spinners that swap for
/// the button label.
struct LoadingRow: View {

    // MARK: - Properties

    let text: String

    // MARK: - Body

    var body: some View {
        HStack(spacing: DSSpace.s2) {
            ProgressView()
                .progressViewStyle(.circular)
                .controlSize(.small)
            Text(text)
                .font(.system(size: DSFont.Size.body))
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(text)
    }
}

// MARK: - Preview

#Preview {
    VStack(spacing: DSSpace.s4) {
        LoadingRow(text: "Waiting for Twitch…")
        LoadingRow(text: "Testing…")
    }
    .padding()
    .frame(width: 320)
}
