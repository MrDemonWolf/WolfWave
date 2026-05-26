//
//  InfoRow.swift
//  WolfWave
//
//  Created by Nathanial Henniges on 2026-04-04.
//  Copyright © 2026 MrDemonWolf, Inc. All rights reserved.
//

import SwiftUI

/// A label + value row for displaying read-only information like URLs, versions, and addresses.
///
/// The value uses a monospaced font by default for technical content (ports, URLs).
/// Supports text selection on the value so users can copy it.
///
/// Usage:
/// ```swift
/// InfoRow(label: "Local Address", value: "ws://localhost:8765")
/// InfoRow(label: "Version", value: "1.2.0", isMonospaced: false)
/// ```
struct InfoRow: View {

    // MARK: - Properties

    let label: String
    let value: String
    var isMonospaced: Bool = true

    // MARK: - Body

    var body: some View {
        VStack(alignment: .leading, spacing: DSSpace.s0) {
            Text(label)
                .font(.system(size: DSFont.Size.sm, weight: .medium))
                .foregroundStyle(.secondary)

            Text(value)
                .font(.system(size: DSFont.Size.body, design: isMonospaced ? .monospaced : .default))
                .textSelection(.enabled)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(label): \(value)")
    }
}

// MARK: - Previews

#Preview("Monospaced URL") {
    InfoRow(label: "Local Address", value: "ws://localhost:8765")
        .padding()
        .frame(width: 360)
}

#Preview("Plain version") {
    InfoRow(label: "Version", value: "1.2.0", isMonospaced: false)
        .padding()
        .frame(width: 360)
}
