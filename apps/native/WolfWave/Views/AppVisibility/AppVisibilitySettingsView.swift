//
//  AppVisibilitySettingsView.swift
//  WolfWave
//
//  Created by Nathanial Henniges on 2026-01-13.
//  Copyright © 2026 MrDemonWolf, Inc. All rights reserved.
//

import SwiftUI

/// App visibility settings interface for controlling dock and menu bar presence.
///
/// One grouped card, stacked top-to-bottom: a Launch-at-Login checkbox and a
/// native macOS radio group for the display mode. The radio group uses
/// `.pickerStyle(.radioGroup)` — the AppKit-native control HIG recommends for a
/// persistent two-to-five-option choice (radios "display settings"; segmented
/// controls "initiate an action"). This replaced an earlier hand-rolled two
/// column card layout that cramped the radios.
struct AppVisibilitySettingsView: View {
    // MARK: - User Settings

    @AppStorage(AppConstants.UserDefaults.dockVisibility)
    private var dockVisibility = AppConstants.DockVisibility.default

    @AppStorage(AppConstants.UserDefaults.launchAtLogin)
    private var launchAtLogin = false

    // MARK: - Body

    var body: some View {
        VStack(alignment: .leading, spacing: DSSpace.s6) {
            // Section Header
            VStack(alignment: .leading, spacing: DSSpace.s1h) {
                Text("App Visibility")
                    .sectionSubHeader()

                Text("Control how WolfWave appears in your Dock and menu bar.")
                    .font(.system(size: DSFont.Size.base))
                    .foregroundStyle(.secondary)
            }

            // Startup + Display Mode, stacked in one grouped card
            VStack(alignment: .leading, spacing: DSSpace.s4) {
                startupGroup

                Divider()

                displayModeGroup
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .cardStyle()

            // Menu Bar Only Info Notice
            if dockVisibility == AppConstants.DockVisibility.menuOnly {
                CalloutBanner(
                    "The app will temporarily appear in the Dock while the settings window is open.",
                    style: .info
                )
            }
        }
        .onAppear {
            // Sync toggle with actual SMAppService state on appear
            let actual = LaunchAtLoginService.isEnabled
            if launchAtLogin != actual { launchAtLogin = actual }
            // If launch at login is on but dockOnly was persisted externally, correct it
            if launchAtLogin && dockVisibility == AppConstants.DockVisibility.dockOnly {
                dockVisibility = AppConstants.DockVisibility.default
                applyDockVisibility(AppConstants.DockVisibility.default)
            }
        }
    }

    // MARK: - Groups

    /// Launch-at-Login checkbox with a one-line explanation underneath.
    private var startupGroup: some View {
        VStack(alignment: .leading, spacing: DSSpace.s2) {
            Text("Startup")
                .sectionEyebrow()

            Toggle("Launch at Login", isOn: Binding(
                get: { launchAtLogin },
                set: { newValue in
                    // Revert toggle immediately if SMAppService fails
                    guard LaunchAtLoginService.setEnabled(newValue) else { return }
                    launchAtLogin = newValue
                    // Dock Only is incompatible with launch at login,
                    // switch to Menu Bar + Dock so the app is always reachable.
                    if newValue && dockVisibility == AppConstants.DockVisibility.dockOnly {
                        dockVisibility = AppConstants.DockVisibility.default
                        applyDockVisibility(AppConstants.DockVisibility.default)
                    }
                }
            ))
            .toggleStyle(.checkbox)
            .font(.system(size: DSFont.Size.base))
            .pointerCursor()
            .accessibilityLabel("Launch at Login")
            .accessibilityHint("Starts WolfWave automatically when you log in to your Mac")
            .accessibilityIdentifier("launchAtLoginToggle")

            Text("Automatically start WolfWave when you log in.")
                .font(.system(size: DSFont.Size.sm))
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// Native radio group for where WolfWave lives. "Dock Only" disables itself
    /// while Launch at Login is on so the app is always reachable.
    private var displayModeGroup: some View {
        VStack(alignment: .leading, spacing: DSSpace.s2) {
            Text("Display mode")
                .sectionEyebrow()

            Picker("Display Mode", selection: Binding(
                get: { dockVisibility },
                set: { newValue in
                    // Defensive: never land on Dock Only while Launch at Login is on.
                    if newValue == AppConstants.DockVisibility.dockOnly && launchAtLogin { return }
                    dockVisibility = newValue
                    applyDockVisibility(newValue)
                }
            )) {
                // `.tag()` stays the outermost modifier on each row. Modifiers
                // applied after a tag can swallow the tag preference, leaving the
                // Picker selection unbound (radios render but never reflect state).
                Text("Dock and Menu Bar")
                    .accessibilityIdentifier("dockVisibility_both")
                    .tag(AppConstants.DockVisibility.default)
                Text("Menu Bar Only")
                    .accessibilityIdentifier("dockVisibility_menuOnly")
                    .tag(AppConstants.DockVisibility.menuOnly)
                Text("Dock Only")
                    .accessibilityIdentifier("dockVisibility_dockOnly")
                    .disabled(launchAtLogin)
                    .tag(AppConstants.DockVisibility.dockOnly)
            }
            .pickerStyle(.radioGroup)
            .labelsHidden()
            .accessibilityLabel("Display Mode")
            .accessibilityIdentifier("dockVisibilityPicker")

            if launchAtLogin && dockVisibility != AppConstants.DockVisibility.dockOnly {
                CalloutBanner(
                    "\"Dock Only\" is unavailable while Launch at Login is on. "
                        + "The menu bar icon must always be reachable.",
                    style: .info
                )
            }
        }
    }

    // MARK: - Helpers

    /// Posts a `dockVisibilityChanged` notification so `AppDelegate` updates
    /// the `NSApp.activationPolicy` and menu-bar visibility.
    ///
    /// - Parameter mode: One of `AppConstants.DockVisibility.menuOnly`,
    ///   `.dockOnly`, or `.both`.
    private func applyDockVisibility(_ mode: String) {
        NotificationCenter.default.postDockVisibility(mode: mode)
    }
}

// MARK: - Preview

#Preview("Dock and Menu Bar") {
    @Previewable @AppStorage(AppConstants.UserDefaults.dockVisibility) var dockVisibility = "both"

    AppVisibilitySettingsView()
        .padding()
        .frame(width: 600)
}
#Preview("Menu Bar Only") {
    @Previewable @AppStorage(AppConstants.UserDefaults.dockVisibility) var dockVisibility = "menuOnly"

    AppVisibilitySettingsView()
        .padding()
        .frame(width: 600)
}

#Preview("Dock Only") {
    @Previewable @AppStorage(AppConstants.UserDefaults.dockVisibility) var dockVisibility = "dockOnly"

    AppVisibilitySettingsView()
        .padding()
        .frame(width: 600)
}
