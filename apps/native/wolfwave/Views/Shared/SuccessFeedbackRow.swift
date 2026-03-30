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
        HStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 14))
                .foregroundStyle(.green)
            Text(text)
                .font(.system(size: 13, weight: fontWeight))
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Preview

#Preview {
    VStack(spacing: 12) {
        SuccessFeedbackRow(text: "Discord Status enabled!")
        SuccessFeedbackRow(text: "You're all set!", fontWeight: .medium)
    }
    .padding()
}
