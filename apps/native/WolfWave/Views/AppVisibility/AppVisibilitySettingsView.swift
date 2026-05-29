//
//  AppVisibilitySettingsView.swift
//  WolfWave
//
//  Created by Nathanial Henniges on 2026-01-13.
//  Copyright © 2026 MrDemonWolf, Inc. All rights reserved.
//

import SwiftUI

/// App visibility settings interface for controlling dock and menu bar presence.
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
            VStack(alignment: .leading, spacing: 6) {
                Text("App Visibility")
                    .sectionSubHeader()

                Text("Control how WolfWave appears in your Dock and menu bar.")
                    .font(.system(size: DSFont.Size.base))
                    .foregroundStyle(.secondary)
            }

            // Launch at Login Card
            VStack(alignment: .leading, spacing: DSSpace.s4) {
                VStack(alignment: .leading, spacing: DSSpace.s0) {
                    Text("Startup")
                        .font(.system(size: DSFont.Size.base, weight: .medium))
                    Text("Automatically start WolfWave when you log in")
                        .font(.system(size: DSFont.Size.sm))
                        .foregroundStyle(.tertiary)
                }

                Toggle("Launch at Login", isOn: Binding(
                    get: { launchAtLogin },
                    set: { newValue in
                        // Revert toggle immediately if SMAppService fails
                        guard LaunchAtLoginService.setEnabled(newValue) else { return }
                        launchAtLogin = newValue
                        // Dock Only is incompatible with launch at login —
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
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .cardStyle()

            // Picker Card
            VStack(alignment: .leading, spacing: DSSpace.s4) {
                VStack(alignment: .leading, spacing: DSSpace.s0) {
                    Text("Display Mode")
                        .font(.system(size: DSFont.Size.base, weight: .medium))
                    Text("Where should WolfWave live?")
                        .font(.system(size: DSFont.Size.sm))
                        .foregroundStyle(.tertiary)
                }

                VStack(alignment: .leading, spacing: 6) {
                    RadioOption(
                        label: "Dock and Menu Bar",
                        tag: AppConstants.DockVisibility.default,
                        selection: $dockVisibility,
                        onChange: applyDockVisibility,
                        accessibilityID: "dockVisibility_both"
                    )
                    RadioOption(
                        label: "Menu Bar Only",
                        tag: AppConstants.DockVisibility.menuOnly,
                        selection: $dockVisibility,
                        onChange: applyDockVisibility,
                        accessibilityID: "dockVisibility_menuOnly"
                    )
                    RadioOption(
                        label: "Dock Only",
                        tag: AppConstants.DockVisibility.dockOnly,
                        selection: $dockVisibility,
                        onChange: applyDockVisibility,
                        disabled: launchAtLogin,
                        accessibilityID: "dockVisibility_dockOnly"
                    )
                }
                .accessibilityLabel("Display Mode")
                .accessibilityIdentifier("dockVisibilityPicker")

                if launchAtLogin && dockVisibility != AppConstants.DockVisibility.dockOnly {
                    HStack(alignment: .top, spacing: DSSpace.s3) {
                        Image(systemName: "info.circle.fill")
                            .font(.system(size: DSFont.Size.body))
                            .foregroundStyle(DSColor.info)
                        Text("\"Dock Only\" is unavailable while Launch at Login is on — the menu bar icon must always be reachable.")
                            .font(.system(size: DSFont.Size.sm))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(DSSpace.s3)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(DSColor.info.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: DSRadius.sm))
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("Dock Only is unavailable while Launch at Login is enabled.")
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(AppConstants.SettingsUI.cardPadding)
            .background(Color(nsColor: .controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: AppConstants.SettingsUI.cardCornerRadius))

            // Menu Bar Only Info Notice
            if dockVisibility == AppConstants.DockVisibility.menuOnly {
                HStack(alignment: .top, spacing: DSSpace.s3) {
                    Image(systemName: "info.circle.fill")
                        .font(.system(size: DSFont.Size.base))
                        .foregroundStyle(DSColor.info)
                    Text("The app will temporarily appear in the Dock while the settings window is open.")
                        .font(.system(size: DSFont.Size.body))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(DSSpace.s4)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(DSColor.info.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: DSRadius.md))
                .accessibilityElement(children: .combine)
                .accessibilityLabel("The app will temporarily appear in the Dock while the settings window is open.")
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

// MARK: - Radio Option

/// A single radio-button row that can be disabled with a strikethrough hint.
private struct RadioOption: View {
    let label: String
    let tag: String
    @Binding var selection: String
    let onChange: (String) -> Void
    var disabled: Bool = false
    var accessibilityID: String = ""

    var body: some View {
        Button {
            guard !disabled else { return }
            selection = tag
            onChange(tag)
        } label: {
            HStack(spacing: DSSpace.s2) {
                Image(systemName: selection == tag ? "circle.inset.filled" : "circle")
                    .font(.system(size: DSFont.Size.base))
                    .foregroundStyle(disabled ? Color.secondary.opacity(0.4) : (selection == tag ? Color.accentColor : Color.secondary))
                Text(label)
                    .font(.system(size: DSFont.Size.base))
                    .foregroundStyle(disabled ? .tertiary : .primary)
                if disabled {
                    Text("unavailable")
                        .font(.system(size: DSFont.Size.xs, weight: .medium))
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, DSSpace.s2)
                        .padding(.vertical, DSSpace.s0)
                        .background(Color.secondary.opacity(0.12))
                        .clipShape(Capsule())
                }
            }
        }
        .buttonStyle(.plain)
        .pointerCursor()
        .disabled(disabled)
        .accessibilityLabel(label)
        .accessibilityAddTraits(selection == tag ? .isSelected : [])
        .accessibilityHint(disabled ? "Unavailable while Launch at Login is enabled" : "")
        .accessibilityIdentifier(accessibilityID)
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

