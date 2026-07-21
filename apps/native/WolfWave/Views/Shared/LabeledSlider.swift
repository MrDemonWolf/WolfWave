//
//  LabeledSlider.swift
//  WolfWave
//
//  Created by Nathanial Henniges on 2026-05-27.
//  Copyright © 2026 MrDemonWolf, Inc. All rights reserved.
//

import SwiftUI

/// Slider row with a leading label and a trailing live value readout. Used
/// by the Twitch cooldown rows so the user can see "15s" change as they
/// drag, instead of a bare slider with no numeric feedback.
struct LabeledSlider<V: BinaryFloatingPoint>: View where V.Stride: BinaryFloatingPoint {

    // MARK: - Properties

    let label: String
    @Binding var value: V
    let range: ClosedRange<V>
    var step: V.Stride = 1
    var format: (V) -> String = { String(Int($0)) }
    var accessibilityIdentifier: String? = nil

    // MARK: - Body

    var body: some View {
        HStack(spacing: DSSpace.s3) {
            Text(label)
                .font(.system(size: DSFont.Size.sm))
                .foregroundStyle(.secondary)
                .frame(minWidth: 80, alignment: .leading)

            Slider(value: $value, in: range, step: step)
                .controlSize(.small)

            Text(format(value))
                .font(.system(size: DSFont.Size.sm, weight: .medium))
                .monospacedDigit()
                .foregroundStyle(.primary)
                .frame(minWidth: 36, alignment: .trailing)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(label)
        .accessibilityValue(format(value))
        .accessibilityIdentifier(accessibilityIdentifier ?? "labeledSlider.\(label)")
    }
}

// MARK: - Preview

#Preview {
    struct Wrapper: View {
        @State var everyone: Double = 15
        @State var perUser: Double = 30
        var body: some View {
            VStack(spacing: DSSpace.s4) {
                LabeledSlider(
                    label: "Everyone",
                    value: $everyone,
                    range: 5...120,
                    format: { "\(Int($0))s" }
                )
                LabeledSlider(
                    label: "Per person",
                    value: $perUser,
                    range: 5...300,
                    format: { "\(Int($0))s" }
                )
            }
            .padding()
            .frame(width: 420)
        }
    }
    return Wrapper()
}
