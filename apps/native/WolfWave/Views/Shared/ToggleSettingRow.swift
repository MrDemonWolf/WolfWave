//
//  ToggleSettingRow.swift
//  WolfWave
//
//  Created by Nathanial Henniges on 2026-03-27.
//  Copyright © 2026 MrDemonWolf, Inc. All rights reserved.
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

    @Environment(\.isEnabled) private var isEnabled

    // MARK: - Body

    var body: some View {
        HStack(spacing: DSSpace.s4) {
            VStack(alignment: .leading, spacing: DSSpace.s0) {
                Text(title)
                    .font(.system(size: DSFont.Size.base, weight: .medium))
                Text(subtitle)
                    .font(.system(size: DSFont.Size.sm))
                    .foregroundStyle(.tertiary)
            }
            Spacer()
            toggle
        }
        .opacity(!isEnabled || isDisabled ? 0.5 : 1.0)
    }

    // MARK: - Private Views

    @ViewBuilder
    private var toggle: some View {
        let base = Toggle("", isOn: $isOn)
            .labelsHidden()
            .toggleStyle(.switch)
            .controlSize(controlSize)
            .pointerCursor()
            .disabled(isDisabled)
            .accessibilityLabel(accessibilityLabel)
            .accessibilityIdentifier(accessibilityIdentifier)
            .accessibilityValue(isOn ? "Enabled" : "Disabled")
            .onChange(of: isOn) { _, newValue in
                onChange?(newValue)
            }

        if let accessibilityHint {
            base.accessibilityHint(accessibilityHint)
        } else {
            base
        }
    }
}

// MARK: - Preview

#Preview {
    VStack(spacing: DSSpace.s6) {
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
