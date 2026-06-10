//
//  SettingsSceneBridge.swift
//  WolfWave
//
//  Copyright © 2026 MrDemonWolf, Inc. All rights reserved.
//

import AppKit
import SwiftUI

/// Invisible bridge that lets AppKit entry points (the status-bar menu, Dock
/// context menu, Dock reopen, and Twitch re-auth) open the dedicated Settings
/// `Window` scene through the public `@Environment(\.openWindow)` action,
/// calling `openWindow(id: WolfWaveApp.settingsWindowID)`, instead of the
/// private `showSettingsWindow:` selector.
///
/// `openWindow` only resolves to the real scene-open action when read inside a
/// *live* SwiftUI render tree connected to the App scene graph. A detached
/// `NSHostingView` does not qualify on macOS 26, so the action must be read from
/// a view that is part of a real scene.
///
/// So this view is hosted in a real (but hidden) `Window` scene declared in
/// `WolfWaveApp.body` *before* the Settings `Window` scene, and is driven by
/// `AppDelegate.openSettings()` via the `.openSettingsRequested` notification.
/// `BridgeWindowNeutralizer` keeps that host window offscreen and invisible so it
/// never appears and never trips `applyDockVisibility`'s visible-normal-key probe.
struct SettingsSceneBridge: View {

    /// Identifier for the hidden helper `Window` scene. Shared with
    /// `WolfWaveApp.body` and used to exclude the helper window from the
    /// Settings-window front search.
    static let windowID = "settings-bridge"

    @Environment(\.openWindow) private var openWindow

    var body: some View {
        BridgeWindowNeutralizer()
            .frame(width: 0, height: 0)
            .onReceive(NotificationCenter.default.publisher(for: .openSettingsRequested)) { _ in
                handleOpenRequest()
            }
    }

    // MARK: - Private Helpers

    /// Opens (or fronts) the Settings window from the live SwiftUI environment.
    ///
    /// The activation-policy switch (`.accessory` → `.regular`) is owned by
    /// `AppDelegate.openSettings()`, which runs before posting the notification;
    /// here we activate, invoke the public `openWindow(id:)` action for the
    /// Settings `Window` scene (single-instance, so this fronts the existing
    /// window if it is already open), then front the realized window.
    @MainActor
    private func handleOpenRequest() {
        NSApp.activate()
        openWindow(id: WolfWaveApp.settingsWindowID)

        // SwiftUI creates/reuses the Settings window during `openSettings()`, so
        // it exists by the time this fires. Fronting it is a best-effort polish
        // step; `openSettings()` + `NSApp.activate` already surface it.
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(50))
            Self.settingsWindow()?.makeKeyAndOrderFront(nil)
        }
    }

    /// Best-effort lookup of SwiftUI's realized Settings window.
    ///
    /// SwiftUI exposes no stable identifier for the `Settings` scene window, so we
    /// take the frontmost normal, key-capable, titled window that is neither the
    /// hidden bridge window nor an AppDelegate-owned window (onboarding uses
    /// `.fullSizeContentView`; What's New is excluded by reference).
    @MainActor
    static func settingsWindow() -> NSWindow? {
        let delegate = NSApp.delegate as? AppDelegate
        // `orderedWindows` is front-to-back z-order (first = foremost), so the
        // match is the topmost eligible window rather than an arbitrary one from
        // the unordered `windows`. The ordered-out bridge window isn't on screen,
        // so it's absent here anyway; the `windowID` guard is belt-and-braces.
        return NSApp.orderedWindows.first { window in
            window.identifier?.rawValue != windowID
                && window !== delegate?.onboardingWindow
                && window !== delegate?.whatsNewWindow
                && window.canBecomeKey
                && window.level == .normal
                && window.styleMask.contains(.titled)
                && !window.styleMask.contains(.fullSizeContentView)
        }
    }
}

// MARK: - Host Window Neutralizer

/// Reaches the bridge view's host `NSWindow` via `view.window` and neutralizes it
/// so the helper `Window` scene never appears, never steals focus, and never
/// satisfies `applyDockVisibility`'s `isVisible && canBecomeKey && level == .normal`
/// probe (so menu-only mode still hides the Dock after Settings closes).
///
/// The window's `styleMask` is deliberately left untouched; SwiftUI owns it.
/// Dropping the level below `.normal`, plus `orderOut` and `alphaValue = 0`, is
/// enough to keep it off the dock-visibility probe and out of sight.
private struct BridgeWindowNeutralizer: NSViewRepresentable {

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        // The window isn't attached during `makeNSView`; defer one runloop tick
        // until `view.window` is populated. `Task { @MainActor … }` keeps the
        // deferred call inside MainActor isolation (a bare main-queue dispatch
        // closure carries no isolation, so `neutralize` couldn't be called).
        Task { @MainActor in neutralize(view.window) }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        // Re-assert in case SwiftUI re-realizes the window.
        neutralize(nsView.window)
    }

    @MainActor
    private func neutralize(_ window: NSWindow?) {
        guard let window else { return }
        window.identifier = NSUserInterfaceItemIdentifier(SettingsSceneBridge.windowID)
        window.level = NSWindow.Level(rawValue: NSWindow.Level.normal.rawValue - 1)
        window.alphaValue = 0
        window.ignoresMouseEvents = true
        window.isExcludedFromWindowsMenu = true
        window.collectionBehavior = [.stationary, .ignoresCycle, .fullScreenNone]
        // The bridge is a degenerate 1×1 offscreen host. Opt it out of window
        // state restoration so macOS never persists/restores its frame. A saved
        // degenerate frame restores as garbage and logs "window frame from string
        // '… 0 1 …' failed" on the next launch.
        window.isRestorable = false
        window.setFrame(NSRect(x: -10_000, y: -10_000, width: 1, height: 1), display: false)
        window.orderOut(nil)
    }
}
