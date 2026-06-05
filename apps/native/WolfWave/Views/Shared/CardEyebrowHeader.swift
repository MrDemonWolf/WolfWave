//
//  CardEyebrowHeader.swift
//  WolfWave
//
//  Created by Nathanial Henniges on 2026-06-04.
//  Copyright © 2026 MrDemonWolf, Inc. All rights reserved.
//

import SwiftUI

/// Small in-card eyebrow header: an SF Symbol followed by a sentence-case
/// `.sectionEyebrow()` label, tagged as an accessibility header.
///
/// One source of truth for the "icon + eyebrow" header that had drifted into
/// private `cardHeader` / `chartCardHeader` copies across the History & Stats
/// pane and inline stacks in the Music Monitor pane.
///
/// ```swift
/// CardEyebrowHeader("Top artists", systemImage: "music.mic")
/// ```
struct CardEyebrowHeader: View {

    // MARK: - Properties

    let title: String
    let systemImage: String

    // MARK: - Init

    init(_ title: String, systemImage: String) {
        self.title = title
        self.systemImage = systemImage
    }

    // MARK: - Body

    var body: some View {
        HStack(spacing: DSSpace.s1h) {
            Image(systemName: systemImage)
                .font(.system(size: DSFont.Size.sm, weight: .semibold))
                .foregroundStyle(.secondary)
            Text(title)
                .sectionEyebrow()
        }
        .accessibilityAddTraits(.isHeader)
    }
}

// MARK: - Preview

#Preview {
    VStack(alignment: .leading, spacing: DSSpace.s4) {
        CardEyebrowHeader("Top artists", systemImage: "music.mic")
        CardEyebrowHeader("Listening time", systemImage: "clock")
    }
    .padding()
    .frame(width: 320)
}
