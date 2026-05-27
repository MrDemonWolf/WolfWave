//
//  StreamerModeBadge.swift
//  WolfWave
//
//  Created by Nathanial Henniges on 2026-05-26.
//  Copyright © 2026 MrDemonWolf, Inc. All rights reserved.
//

import SwiftUI

/// Inline indicator that a value or control is hidden/locked because
/// **Streamer Mode** is on.
///
/// Render next to any row whose value is masked by `StreamerMode.mask(...)` or
/// whose button is `.disabled(streamerMode)`, so a viewer (on camera or off)
/// can tell the empty/locked state is intentional, not a bug. Caller is
/// responsible for the `if streamerMode { StreamerModeBadge() }` guard — the
/// badge does not read UserDefaults itself.
struct StreamerModeBadge: View {

    var body: some View {
        HStack(spacing: DSSpace.s1) {
            Image(systemName: "eye.slash.fill")
                .font(.system(size: DSFont.Size.xs))
            Text("Streamer Mode")
                .font(.system(size: DSFont.Size.xs, weight: .medium))
        }
        .foregroundStyle(.secondary)
        .padding(.horizontal, DSSpace.s2)
        .padding(.vertical, DSSpace.s0)
        .background(Color.secondary.opacity(0.12))
        .clipShape(Capsule())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Streamer Mode is on")
        .accessibilityIdentifier("streamerModeBadge")
    }
}

// MARK: - Previews

#Preview("Badge") {
    StreamerModeBadge()
        .padding()
        .frame(width: 240)
}

#Preview("In context") {
    HStack {
        Text("Auth Token")
            .font(.system(size: DSFont.Size.base, weight: .medium))
        StreamerModeBadge()
        Spacer()
    }
    .padding()
    .frame(width: 360)
}
