//
//  AppDelegate+Windows.swift
//  WolfWave
//
//  Created by Nathanial Henniges on 2026-04-03.
//  Copyright © 2026 MrDemonWolf, Inc. All rights reserved.
//

import AppKit
import SwiftUI

// MARK: - Menu Actions (Window Entry Points)

extension AppDelegate {

    /// Opens or brings the Settings window to the front.
    ///
    /// Settings is a SwiftUI `Settings` scene (`WolfWaveApp.body`), so SwiftUI
    /// creates, reuses (single-instance), and tears down the window. Rather than
    /// construct an `NSWindow` ourselves (which would steal the `NSToolbar` and
    /// reintroduce the sidebar `>>` flash), we hand off to the hidden
    /// `SettingsSceneBridge` by posting `.openSettingsRequested`. The bridge runs
    /// the public `openSettings` environment action, which avoids the private
    /// `showSettingsWindow:` selector and its "Please use SettingsLink for opening
    /// the Settings scene" warning on macOS 14+.
    ///
    /// When switching from menu-only mode, the activation policy change is
    /// asynchronous, so the hand-off is deferred to the next run-loop tick. That
    /// gives macOS time to register the app as a regular (Dock-visible) process
    /// and avoids "layoutSubtreeIfNeeded on a view already being laid out"
    /// warnings from posting during status-item menu tracking.
    @objc func openSettings() {
        statusItem?.menu?.cancelTracking()

        if currentDockVisibilityMode == AppConstants.DockVisibility.menuOnly {
            NSApp.setActivationPolicy(.regular)
        }

        RunLoop.main.perform {
            MainActor.assumeIsolated {
                // Hand off to the live SwiftUI scene tree: `SettingsSceneBridge`
                // (hosted in the hidden helper window) reads
                // `@Environment(\.openSettings)`, activates the app, opens the
                // `Settings` scene via the public action, and fronts the window.
                NotificationCenter.default.postOpenSettingsRequested()
            }
        }
    }

    /// Shows the system standard About panel from the menu bar.
    ///
    /// About lives in two surfaces with intentionally different presentations:
    /// the menu bar opens the native, compact `NSApplication` panel here;
    /// the Settings sidebar shows the rich `AboutSettingsView` card layout.
    /// Both pull identity, version, and legal strings from `AboutCopy` so they
    /// stay in sync. Deferred past the menu-tracking pass to avoid AppKit
    /// "layoutSubtreeIfNeeded" warnings.
    @objc func showAbout() {
        statusItem?.menu?.cancelTracking()

        RunLoop.main.perform {
            MainActor.assumeIsolated {
                NSApp.activate()
                NSApp.orderFrontStandardAboutPanel(options: AboutCopy.standardAboutPanelOptions())
            }
        }
    }
}

// MARK: - Dock Visibility Management

extension AppDelegate {

    /// Applies the stored dock visibility mode on launch.
    func applyInitialDockVisibility() {
        applyDockVisibility(currentDockVisibilityMode)
    }

    /// Sets activation policy and status item visibility based on the given mode.
    func applyDockVisibility(_ mode: String) {
        switch mode {
        case AppConstants.DockVisibility.menuOnly:
            statusItem?.isVisible = true
            let hasVisibleWindows = NSApp.windows.contains { window in
                window.isVisible && window.canBecomeKey && window.level == .normal
            }
            NSApp.setActivationPolicy(hasVisibleWindows ? .regular : .accessory)
        case AppConstants.DockVisibility.dockOnly:
            NSApp.setActivationPolicy(.regular)
            statusItem?.isVisible = false
        case AppConstants.DockVisibility.both:
            NSApp.setActivationPolicy(.regular)
            statusItem?.isVisible = true
        default:
            NSApp.setActivationPolicy(.regular)
            statusItem?.isVisible = true
        }
    }

    /// Hides the dock icon if menu-only mode is active and no windows remain visible.
    func restoreMenuOnlyIfNeeded() {
        guard currentDockVisibilityMode == AppConstants.DockVisibility.menuOnly else { return }

        let hasVisibleWindows = NSApp.windows.contains { window in
            window.isVisible && window.canBecomeKey && window.level == .normal
        }

        if !hasVisibleWindows {
            // Defer past the current AppKit layout pass: calling
            // setActivationPolicy(.accessory) inline during a window-close
            // animation triggers "layoutSubtreeIfNeeded on a view already
            // being laid out" warnings. RunLoop.main.perform schedules this
            // on the next .common runloop tick, after layout settles.
            RunLoop.main.perform {
                MainActor.assumeIsolated {
                    _ = NSApp.setActivationPolicy(.accessory)
                }
            }
        }
    }
}

// MARK: - What's New

extension AppDelegate {

    /// Shows the What's New sheet once per version for returning users.
    func checkWhatsNew() {
        let currentVersion = AppConstants.AppInfo.shortVersion
        let lastSeen = Preferences.lastSeenWhatsNewVersion

        guard lastSeen != currentVersion else { return }

        // Don't show on first install (onboarding handles that)
        guard Preferences.hasCompletedOnboarding else { return }

        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(1))
            self?.showWhatsNew(version: currentVersion)
        }
    }

    /// Presents the What's New window and marks this version as seen.
    func showWhatsNew(version: String) {
        let whatsNewView = WhatsNewView()
        let hostingController = NSHostingController(rootView: whatsNewView)
        let window = NSWindow(contentViewController: hostingController)
        window.title = "What's New"
        window.styleMask = [.titled, .closable]
        window.setContentSize(NSSize(
            width: DSDimension.WhatsNew.windowWidth,
            height: DSDimension.WhatsNew.windowHeight
        ))
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate()
        whatsNewWindow = window
        Preferences.setLastSeenWhatsNewVersion(version)
    }
}

// MARK: - Onboarding Window

extension AppDelegate {

    /// Shows the first-launch onboarding wizard, or brings it forward if already visible.
    func showOnboarding() {
        if let existing = onboardingWindow, existing.isVisible {
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate()
            return
        }

        let onboardingView = OnboardingView(onComplete: { [weak self] in
            self?.dismissOnboarding()
        })

        let hosting = NSHostingController(rootView: onboardingView)
        let frame = CGRect(
            x: 0, y: 0,
            width: AppConstants.OnboardingUI.windowWidth,
            height: AppConstants.OnboardingUI.windowHeight
        )
        let style: NSWindow.StyleMask = [.titled, .closable, .fullSizeContentView]
        let window = NSWindow(
            contentRect: frame,
            styleMask: style,
            backing: .buffered,
            defer: false
        )
        // Assigning the hosting controller makes hosting.view the window's
        // contentView. Do NOT disable autoresizing or add identity constraints.
        // AppKit uses the autoresizing mask to keep the hosting view filling
        // the window. Disabling it left the view inset inside the window and
        // broke both the unified titlebar look and List hit-testing.
        window.contentViewController = hosting
        window.title = "Welcome to WolfWave"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.delegate = self
        window.isReleasedWhenClosed = false
        window.collectionBehavior = [.moveToActiveSpace]

        NSApp.setActivationPolicy(.regular)
        onboardingWindow = window

        if let screen = NSScreen.main {
            let screenFrame = screen.visibleFrame
            let x = screenFrame.midX - frame.width / 2
            let y = screenFrame.midY - frame.height / 2
            window.setFrameOrigin(NSPoint(x: x, y: y))
        } else {
            window.center()
        }

        window.alphaValue = 0
        showWindow(onboardingWindow)

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.3
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            window.animator().alphaValue = 1
        }
    }

    /// Dismisses the onboarding window with a fade-out animation.
    func dismissOnboarding() {
        Task { @MainActor [weak self] in
            guard let self, let window = self.onboardingWindow else { return }

            NSAnimationContext.runAnimationGroup({ context in
                context.duration = 0.3
                context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                window.animator().alphaValue = 0
            }, completionHandler: { [weak self] in
                MainActor.assumeIsolated {
                    window.close()

                    Task { [weak self] in
                        await self?.validateTwitchTokenOnBoot()
                    }

                    Log.info("AppDelegate: Onboarding dismissed, transitioning to normal app state", category: "App")
                }
            })
        }
    }
}

// MARK: - NSWindowDelegate

extension AppDelegate: NSWindowDelegate {

    /// Handles cleanup when an AppDelegate-owned window closes (onboarding or
    /// whatsNew). The Settings window is owned by SwiftUI's `Settings` scene, so
    /// its close is handled by the global `NSWindow.willCloseNotification`
    /// observer in `AppDelegate+Services`, not here.
    public func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }

        if window === onboardingWindow {
            if OnboardingViewModel.hasCompletedOnboarding == false {
                Log.info("AppDelegate: Onboarding window closed before completion, will show again on next launch", category: "App")
            }
            Task { @MainActor [weak self] in
                self?.onboardingWindow = nil
                self?.restoreMenuOnlyIfNeeded()
            }
        } else if window === whatsNewWindow {
            Task { @MainActor [weak self] in
                self?.whatsNewWindow = nil
                self?.restoreMenuOnlyIfNeeded()
            }
        }
    }
}

// MARK: - Window Helpers

extension AppDelegate {

    /// Activates the app and brings the window forward.
    ///
    /// - Important: Callers invoked from `NSStatusItem` menu tracking or any other
    ///   AppKit layout pass must defer to the next runloop tick (e.g. via
    ///   `RunLoop.main.perform`) before calling this, otherwise AppKit logs
    ///   "layoutSubtreeIfNeeded on a view already being laid out".
    func showWindow(_ window: NSWindow?) {
        window?.level = .normal
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }
}
