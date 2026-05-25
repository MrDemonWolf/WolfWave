//
//  SuccessFeedbackRow.swift
//  wolfwave
//
//  Created by MrDemonWolf, Inc. on 3/22/26.
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
            Text(text)
                .font(.system(size: DSFont.Size.base, weight: fontWeight))
                .foregroundStyle(.secondary)
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
