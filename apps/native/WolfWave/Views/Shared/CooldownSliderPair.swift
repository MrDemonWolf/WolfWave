//
//  CooldownSliderPair.swift
//  WolfWave
//
//  Created by Nathanial Henniges on 2026-06-08.
//  Copyright © 2026 MrDemonWolf, Inc. All rights reserved.
//

import SwiftUI

/// One cooldown slider's configuration: label, bound value, range, step, and an
/// optional accessibility id. Bundled so ``CooldownSliderPair`` can lay two of
/// them out without a long parameter list.
struct CooldownSliderField {
    let label: String
    let value: Binding<Double>
    var range: ClosedRange<Double> = 0...60
    var step: Double = 5
    var accessibilityIdentifier: String? = nil
}

/// The Everyone / Per-person cooldown sliders laid out side by side instead of
/// stacked, so the command rows that show them stay compact. Each is a
/// ``LabeledSlider`` formatting as whole seconds ("15s") and splitting the row
/// width evenly. Shared by ``CommandSettingRow`` (Twitch Bot Commands + Song
/// Request Commands) and History's `!stats` card.
struct CooldownSliderPair: View {

    // MARK: - Properties

    let everyone: CooldownSliderField
    let perPerson: CooldownSliderField

    // MARK: - Body

    var body: some View {
        HStack(alignment: .center, spacing: DSSpace.s7) {
            slider(everyone)
                .frame(maxWidth: .infinity)
            slider(perPerson)
                .frame(maxWidth: .infinity)
        }
    }

    // MARK: - Private Views

    @ViewBuilder
    private func slider(_ field: CooldownSliderField) -> some View {
        LabeledSlider(
            label: field.label,
            value: field.value,
            range: field.range,
            step: field.step,
            format: { "\(Int($0))s" },
            accessibilityIdentifier: field.accessibilityIdentifier
        )
    }
}

// MARK: - Preview

#Preview {
    struct Wrapper: View {
        @State var everyone: Double = 15
        @State var perUser: Double = 30
        var body: some View {
            CooldownSliderPair(
                everyone: .init(label: "Everyone", value: $everyone),
                perPerson: .init(label: "Per person", value: $perUser)
            )
            .padding()
            .frame(width: 480)
        }
    }
    return Wrapper()
}
