//
//  SuccessFeedbackRow.swift
//  WolfWave
//
//  Created by Nathanial Henniges on 2026-03-27.
//  Copyright © 2026 MrDemonWolf, Inc. All rights reserved.
//

import SwiftUI

/// A reusable green checkmark + success text row.
/// Used in onboarding and settings views to confirm an action was successful.
struct SuccessFeedbackRow: View {

    // MARK: - Properties

    let text: String
    var fontWeight: Font.Weight = .regular

    // MARK: - Body

    var body: some View {
        HStack(spacing: DSSpace.s2) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: DSFont.Size.md))
                .foregroundStyle(.green)
                .symbolEffect(.bounce, value: text)
            Text(text)
                .font(.system(size: DSFont.Size.base, weight: fontWeight))
                .foregroundStyle(.secondary)
                .contentTransition(.opacity)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Success: \(text)")
    }
}

// MARK: - Preview

#Preview {
    VStack(spacing: DSSpace.s4) {
        SuccessFeedbackRow(text: "Discord Status enabled!")
        SuccessFeedbackRow(text: "You're all set!", fontWeight: .medium)
    }
    .padding()
}
