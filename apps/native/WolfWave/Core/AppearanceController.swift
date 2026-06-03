//
//  AppearanceController.swift
//  WolfWave
//
//  Created by Nathanial Henniges on 2026-06-01.
//  Copyright © 2026 MrDemonWolf, Inc. All rights reserved.
//

import AppKit

/// Applies the user's appearance preference app-wide via `NSApplication.appearance`.
///
/// SwiftUI's `.preferredColorScheme` only scopes a single window hierarchy, so it
/// can't recolor the menu bar menu, the status item, or AppKit-hosted panels.
/// Setting `NSApp.appearance` overrides every window and menu at once; assigning
/// `nil` removes the override and falls back to the macOS system setting.
enum AppearanceController {

    /// Maps a stored preference raw value to an `NSAppearance`, or `nil` for "system".
    static func appearance(for mode: String) -> NSAppearance? {
        switch mode {
        case AppConstants.Appearance.light:
            return NSAppearance(named: .aqua)
        case AppConstants.Appearance.dark:
            return NSAppearance(named: .darkAqua)
        default:
            return nil // system, no override
        }
    }

    /// Applies the given appearance mode to the running application.
    @MainActor
    static func apply(_ mode: String) {
        NSApp.appearance = appearance(for: mode)
    }

    /// Reads the persisted preference and applies it. Call once on launch.
    @MainActor
    static func applyStored() {
        let mode = UserDefaults.standard.string(forKey: AppConstants.UserDefaults.appearancePreference)
            ?? AppConstants.Appearance.default
        apply(mode)
    }
}
