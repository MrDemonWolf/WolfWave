//
//  DestructiveButton.swift
//  WolfWave
//
//  Created by Nathanial Henniges on 2026-05-26.
//  Copyright © 2026 MrDemonWolf, Inc. All rights reserved.
//

import SwiftUI

/// Bordered destructive action button. HIG: filled-red is reserved for the
/// primary action inside a confirm dialog; surfaces that *trigger* the
/// confirm dialog stay quiet: a neutral bordered pill with a red label, not
/// a red-filled bar. The red reads as a warning on the text, not a final
/// commit on the whole control.
///
/// We deliberately do *not* `.tint(DSColor.error)` here: on macOS a tinted
/// `.bordered` button fills red, turning a full-width trigger into a loud
/// red bar. The destructive cue lives on the label + icon (`DSColor.error`)
/// instead; the confirm dialog keeps the filled-red `Button(role:
/// .destructive)` default for the actual commit.
///
/// Use for "Reset All Settings", "Clear Logs", "Clear History", and any
/// other settings-row destructive trigger.
struct DestructiveButton: View {

    // MARK: - Properties

    let title: String
    var systemImage: String? = nil
    var accessibilityIdentifier: String? = nil
    let action: () -> Void

    // MARK: - Body

    var body: some View {
        Button(role: .destructive, action: action) {
            label
                .font(.system(size: DSFont.Size.base, weight: .medium))
                .frame(maxWidth: .infinity)
                .foregroundStyle(DSColor.error)
        }
        .buttonStyle(.bordered)
        .controlSize(.regular)
        .pointerCursor()
        .accessibilityLabel(title)
        .accessibilityIdentifier(accessibilityIdentifier ?? "destructiveButton.\(title)")
    }

    @ViewBuilder
    private var label: some View {
        if let systemImage {
            Label(title, systemImage: systemImage)
        } else {
            Text(title)
        }
    }
}

// MARK: - Preview

#Preview {
    VStack(spacing: DSSpace.s4) {
        DestructiveButton(title: "Reset All Settings to Defaults", systemImage: "trash") {}
        DestructiveButton(title: "Clear Logs", systemImage: "trash") {}
        DestructiveButton(title: "Delete Account") {}
    }
    .padding()
    .frame(width: 360)
}
