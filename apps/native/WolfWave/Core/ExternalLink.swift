//
//  ExternalLink.swift
//  WolfWave
//
//  Copyright © 2026 MrDemonWolf, Inc. All rights reserved.
//

import AppKit

/// Opens external URLs in the user's default browser.
enum ExternalLink {

    /// Opens a URL string in the default browser. Returns `false` (without throwing) when
    /// the string is not a valid URL.
    ///
    /// Centralizes the `URL(string:)` guard plus `NSWorkspace.shared.open` that was
    /// duplicated across settings, onboarding, and menu-bar code, removing the silent
    /// per-site failure paths.
    @discardableResult
    @MainActor
    static func open(_ urlString: String) -> Bool {
        guard let url = URL(string: urlString) else { return false }
        return NSWorkspace.shared.open(url)
    }
}
