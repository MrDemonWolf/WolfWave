//
//  CommandAliasField.swift
//  WolfWave
//
//  Created by Nathanial Henniges on 2026-06-04.
//  Copyright © 2026 MrDemonWolf, Inc. All rights reserved.
//

import SwiftUI

/// A compact "Custom aliases:" label paired with a rounded text field.
///
/// Every chat-command settings row offers extra trigger names (comma-separated,
/// without the leading `!`). This view is the one shared layout for that field,
/// extracted from the per-pane copies that previously lived in the Twitch, Song
/// Request, and History settings so they share a single look and accessibility
/// contract.
struct CommandAliasField: View {

    // MARK: - Properties

    @Binding var aliases: String
    var label: String = "Custom aliases:"
    var placeholder: String = "e.g. np, track"
    var accessibilityLabel: String = "Custom aliases"
    /// Optional UI-test identifier. Applied only when non-nil so call sites that
    /// never set one (and don't need unique targeting) emit no identifier.
    var accessibilityIdentifier: String? = nil

    // MARK: - Body

    var body: some View {
        HStack(spacing: DSSpace.s2) {
            Text(label)
                .font(.system(size: DSFont.Size.sm))
                .foregroundStyle(.tertiary)

            field
        }
    }

    // MARK: - Private Views

    @ViewBuilder
    private var field: some View {
        let base = TextField(placeholder, text: $aliases)
            .textFieldStyle(.roundedBorder)
            .font(.system(size: DSFont.Size.sm))
            .frame(maxWidth: AppConstants.SettingsUI.inlineFieldMaxWidth)
            .accessibilityLabel(accessibilityLabel)

        if let accessibilityIdentifier {
            base.accessibilityIdentifier(accessibilityIdentifier)
        } else {
            base
        }
    }
}

// MARK: - Preview

#Preview {
    struct Wrapper: View {
        @State private var aliases = "np, track"
        var body: some View {
            CommandAliasField(aliases: $aliases, accessibilityIdentifier: "preview.aliases")
                .padding()
                .frame(width: 420)
        }
    }
    return Wrapper()
}
