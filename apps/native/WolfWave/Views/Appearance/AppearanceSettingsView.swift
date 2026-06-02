//
//  AppearanceSettingsView.swift
//  WolfWave
//
//  Created by Nathanial Henniges on 2026-06-01.
//  Copyright © 2026 MrDemonWolf, Inc. All rights reserved.
//

import SwiftUI

/// Appearance settings: a Light / Dark / System segmented control that overrides
/// the app's `NSAppearance` via `AppearanceController`. Mirrors the segmented
/// appearance control in macOS System Settings.
struct AppearanceSettingsView: View {

    // MARK: - User Settings

    @AppStorage(AppConstants.UserDefaults.appearancePreference)
    private var appearance = AppConstants.Appearance.default

    // MARK: - Body

    var body: some View {
        VStack(alignment: .leading, spacing: DSSpace.s6) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Appearance")
                    .sectionSubHeader()

                Text("Pick a look, or follow your system setting.")
                    .font(.system(size: DSFont.Size.base))
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: DSSpace.s4) {
                Picker("Appearance", selection: Binding(
                    get: { appearance },
                    set: { newValue in
                        appearance = newValue
                        AppearanceController.apply(newValue)
                    }
                )) {
                    Text("System").tag(AppConstants.Appearance.system)
                    Text("Light").tag(AppConstants.Appearance.light)
                    Text("Dark").tag(AppConstants.Appearance.dark)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .accessibilityLabel("Appearance")
                .accessibilityIdentifier("appearancePicker")

                Text("System matches macOS automatically, including the light/dark schedule.")
                    .font(.system(size: DSFont.Size.sm))
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .cardStyle()
        }
    }
}

// MARK: - Preview

#Preview("Appearance") {
    AppearanceSettingsView()
        .padding()
        .frame(width: 600)
}
