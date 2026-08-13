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

    /// The value as rendered: clamped into `range`, with a non-finite value
    /// falling back to `range.lowerBound`.
    ///
    /// Every caller binds an `@AppStorage` double, so the stored value can be
    /// anything a hand-edited plist or `defaults write` put there. That matters
    /// twice over: `Slider` misbehaves outside its bounds, and the default
    /// `format` below is `Int($0)`, which traps outright on NaN or a value past
    /// `Int.max`. Clamping here covers every call site, including the ones that
    /// pass their own `"\(Int($0))s"` closure.
    static func displayValue(_ value: V, in range: ClosedRange<V>) -> V {
        guard value.isFinite else { return range.lowerBound }
        return min(max(value, range.lowerBound), range.upperBound)
    }

    var body: some View {
        let display = Self.displayValue(value, in: range)
        return HStack(spacing: DSSpace.s3) {
            Text(label)
                .font(.system(size: DSFont.Size.sm))
                .foregroundStyle(.secondary)
                .frame(minWidth: 80, alignment: .leading)

            Slider(
                value: Binding(
                    get: { Self.displayValue(value, in: range) },
                    set: { value = $0 }
                ),
                in: range,
                step: step
            )
            .controlSize(.small)

            Text(format(display))
                .font(.system(size: DSFont.Size.sm, weight: .medium))
                .monospacedDigit()
                .foregroundStyle(.primary)
                .frame(minWidth: 36, alignment: .trailing)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(label)
        .accessibilityValue(format(display))
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
