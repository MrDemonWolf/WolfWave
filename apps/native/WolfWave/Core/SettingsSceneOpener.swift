//
//  SettingsSceneOpener.swift
//  WolfWave
//
//  Copyright © 2026 MrDemonWolf, Inc. All rights reserved.
//

import AppKit
import SwiftUI

/// Opens the SwiftUI `Settings` scene from AppKit entry points (the status-bar
/// menu and Dock reopen) through `SettingsLink`'s public action path instead of
/// the private `showSettingsWindow:` selector.
///
/// macOS 14+ logs "Please use SettingsLink for opening the Settings scene" when
/// the private selector is used. `SettingsLink` is a SwiftUI view and an `NSMenu`
/// cannot host one, so this keeps a tiny offscreen window whose content view is a
/// `SettingsLink` and clicks its realized control to run SwiftUI's own scene-open
/// action.
///
/// If SwiftUI does not expose a clickable control in the hosting view (its
/// internals vary by OS release), it falls back to the selector so Settings still
/// opens. The fallback is the only path that can still log the warning.
@MainActor
enum SettingsSceneOpener {

    /// Cached offscreen host so the `SettingsLink` control is built once and reused.
    private static var host: NSWindow?

    /// Opens the Settings scene. Safe to call repeatedly.
    static func open() {
        let window = host ?? makeHost()
        host = window
        window.contentView?.layoutSubtreeIfNeeded()

        if let control = window.contentView?.firstClickableControl() {
            control.performClick(nil)
        } else {
            openViaSelector()
        }
    }

    /// Builds the invisible, offscreen window that hosts the `SettingsLink`.
    private static func makeHost() -> NSWindow {
        let hosting = NSHostingView(rootView: SettingsLink { Color.clear })
        hosting.frame = NSRect(x: 0, y: 0, width: 2, height: 2)

        let window = NSWindow(
            contentRect: hosting.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.contentView = hosting
        window.alphaValue = 0
        window.ignoresMouseEvents = true
        window.isExcludedFromWindowsMenu = true
        window.setFrameOrigin(NSPoint(x: -10_000, y: -10_000))
        window.orderBack(nil)
        window.contentView?.layoutSubtreeIfNeeded()
        return window
    }

    /// Last-resort path. Still opens Settings, but logs the SettingsLink warning.
    private static func openViaSelector() {
        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
    }
}

// MARK: - View search

private extension NSView {

    /// Depth-first search for the first clickable `NSControl` in the subtree.
    func firstClickableControl() -> NSControl? {
        if let control = self as? NSControl { return control }
        for subview in subviews {
            if let found = subview.firstClickableControl() { return found }
        }
        return nil
    }
}
