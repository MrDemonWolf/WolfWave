//
//  InfoRow.swift
//  wolfwave
//
//  Created by MrDemonWolf, Inc. on 4/4/26.
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
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)

            Text(value)
                .font(.system(size: 12, design: isMonospaced ? .monospaced : .default))
                .textSelection(.enabled)
        }
    }
}
