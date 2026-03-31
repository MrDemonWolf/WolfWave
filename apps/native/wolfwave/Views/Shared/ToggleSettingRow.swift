//
//  ToggleSettingRow.swift
//  wolfwave
//
//  Created by MrDemonWolf, Inc. on 3/22/26.
//

import SwiftUI

/// A reusable toggle row with a title, subtitle, and switch control.
/// Used across settings views and onboarding for consistent toggle presentation.
struct ToggleSettingRow: View {

    // MARK: - Properties

    let title: String
    let subtitle: String
    @Binding var isOn: Bool
    var controlSize: ControlSize = .small
    var isDisabled: Bool = false
    var accessibilityLabel: String
    var accessibilityIdentifier: String
    var accessibilityHint: String? = nil
    var onChange: ((Bool) -> Void)? = nil

    // MARK: - Body

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
            }
            Spacer()
            toggle
        }
    }

    // MARK: - Private Views

    @ViewBuilder
    private var toggle: some View {
        Toggle("", isOn: $isOn)
            .labelsHidden()
            .toggleStyle(.switch)
            .controlSize(controlSize)
            .pointerCursor()
            .disabled(isDisabled)
            .accessibilityLabel(accessibilityLabel)
            .accessibilityIdentifier(accessibilityIdentifier)
            .accessibilityHint(accessibilityHint ?? "")
            .accessibilityValue(isOn ? "Enabled" : "Disabled")
            .onChange(of: isOn) { _, newValue in
                onChange?(newValue)
            }
    }
}

// MARK: - Preview

#Preview {
    VStack(spacing: 16) {
        ToggleSettingRow(
            title: "Enable Feature",
            subtitle: "A short description of what this does",
            isOn: .constant(true),
            accessibilityLabel: "Enable Feature",
            accessibilityIdentifier: "featureToggle"
        )
        .cardStyle()

        ToggleSettingRow(
            title: "Disabled Feature",
            subtitle: "This one is disabled",
            isOn: .constant(false),
            isDisabled: true,
            accessibilityLabel: "Disabled Feature",
            accessibilityIdentifier: "disabledToggle"
        )
        .cardStyle()
    }
    .padding()
    .frame(width: 400)
}
