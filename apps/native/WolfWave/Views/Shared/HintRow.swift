//
//  HintRow.swift
//  WolfWave
//
//  Created by Nathanial Henniges on 2026-06-01.
//  Copyright © 2026 MrDemonWolf, Inc. All rights reserved.
//

import SwiftUI

/// A compact footnote hint: a small secondary SF Symbol followed by secondary
/// text, with no background or tint.
///
/// Use for an inline tip under a control, e.g. "Cooldowns don't apply to you
/// or your mods." For a note that needs a colored wash (info / warning /
/// success), reach for ``CalloutBanner`` instead. `text` is parsed as Markdown
/// so inline `**bold**` renders.
struct HintRow: View {

    // MARK: - Properties

    let text: String
    var systemImage: String = "info.circle.fill"

    // MARK: - Init

    init(_ text: String, systemImage: String = "info.circle.fill") {
        self.text = text
        self.systemImage = systemImage
    }

    // MARK: - Body

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: DSSpace.s1) {
            Image(systemName: systemImage)
                .font(.system(size: DSFont.Size.sm))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text(InlineMarkdown.attributed(text))
                .font(.system(size: DSFont.Size.sm))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Preview

#Preview {
    VStack(alignment: .leading, spacing: DSSpace.s3) {
        HintRow("Cooldowns don't apply to you or your mods.")
        HintRow("Nothing is uploaded. Everything stays on this Mac.", systemImage: "lock.fill")
    }
    .padding()
    .frame(width: 420)
}
