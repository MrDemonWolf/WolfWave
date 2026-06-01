//
//  Pasteboard.swift
//  WolfWave
//
//  Created by Nathanial Henniges on 2026-06-01.
//  Copyright © 2026 MrDemonWolf, Inc. All rights reserved.
//

import AppKit

/// Thin wrapper over `NSPasteboard.general` plain-text writes.
///
/// Collapses the repeated `clearContents()` + `setString(_:forType: .string)`
/// dance into one call so there is a single place that touches the system
/// pasteboard. `CopyButton` and the ad-hoc copy affordances in the Debug,
/// About, and Advanced panes route through here.
enum Pasteboard {

    /// Replaces the general pasteboard contents with `string` as plain text.
    ///
    /// - Parameter string: The text to place on the pasteboard.
    /// - Returns: `true` if the write succeeded.
    @discardableResult
    static func copy(_ string: String) -> Bool {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        return pasteboard.setString(string, forType: .string)
    }
}
