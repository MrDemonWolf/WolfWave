//
//  OpenInBrowserButton.swift
//  WolfWave
//
//  Created by Nathanial Henniges on 2026-06-02.
//  Copyright © 2026 MrDemonWolf, Inc. All rights reserved.
//

import SwiftUI

/// Small bordered "Open" button that launches a URL string in the default browser.
///
/// Replaces the hand-rolled open buttons in Stream Widgets settings so the `safari`
/// glyph, sizing, disabled handling, and `URL(string:)` guard live in one place.
struct OpenInBrowserButton: View {

    let urlString: String
    var title: String = "Open"
    var isDisabled: Bool = false
    let accessibilityLabel: String
    var accessibilityHint: String = ""
    var accessibilityIdentifier: String = ""

    var body: some View {
        Button {
            ExternalLink.open(urlString)
        } label: {
            HStack(spacing: DSSpace.s1) {
                Image(systemName: "safari").font(.system(size: DSFont.Size.sm))
                Text(title).font(.system(size: DSFont.Size.sm))
            }
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .disabled(isDisabled)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint(accessibilityHint)
        .accessibilityIdentifier(accessibilityIdentifier)
    }
}
