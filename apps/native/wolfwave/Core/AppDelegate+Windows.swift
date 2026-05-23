//
//  AppDelegate+Windows.swift
//  wolfwave
//
//  Created by MrDemonWolf, Inc. on 4/2/26.
//

import AppKit
import SwiftUI

// MARK: - Menu Actions (Window Entry Points)

extension AppDelegate {

    /// Opens or brings the Settings window to the front.
    ///
    /// When switching from menu-only mode, the activation policy change is
    /// asynchronous — the window show is deferred to the next run-loop tick
    /// so macOS has time to register the app as a regular (Dock-visible) process.
    @objc func openSettings() {
        statusItem?.menu?.cancelTracking()

        if currentDockVisibilityMode == AppConstants.DockVisibility.menuOnly {
            NSApp.setActivationPolicy(.regular)
        }

        // Defer past the current AppKit layout / menu-tracking pass to avoid
        // "layoutSubtreeIfNeeded on a view already being laid out" warnings.
        RunLoop.main.perform { [weak self] in
            guard let self else { return }
            if let window = self.settingsWindow {
                if window.isMiniaturized {
                    window.deminiaturize(nil)
                }
                self.showWindow(window)
            } else {
                self.settingsWindow = self.createSettingsWindow()
                self.showWindow(self.settingsWindow)
            }
        }
    }

    /// Shows the custom About window. Brings the existing window forward
    /// if already open, otherwise creates and centers a new one.
    @objc func showAbout() {
        statusItem?.menu?.cancelTracking()

        if currentDockVisibilityMode == AppConstants.DockVisibility.menuOnly {
            NSApp.setActivationPolicy(.regular)
        }

        // Defer past the current AppKit layout / menu-tracking pass to avoid
        // "layoutSubtreeIfNeeded on a view already being laid out" warnings.
        RunLoop.main.perform { [weak self] in
            guard let self else { return }

            if let existing = self.aboutWindow {
                if existing.isMiniaturized { existing.deminiaturize(nil) }
                self.showWindow(existing)
                return
            }

            self.aboutWindow = self.createAboutWindow()
            self.showWindow(self.aboutWindow)
        }
    }

    /// Builds the About window. Mirrors `createSettingsWindow()` so that
    /// `NSWindowDelegate` conformance is established inside MainActor-isolated
    /// context (avoids actor-isolation warnings when the caller is a
    /// nonisolated closure such as `RunLoop.main.perform`).
    private func createAboutWindow() -> NSWindow {
        let hosting = NSHostingController(rootView: AboutView())
        let window = NSWindow(contentViewController: hosting)
        window.title = "About \(appName)"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.styleMask = [.titled, .closable, .fullSizeContentView]
        window.setContentSize(NSSize(width: 360, height: 480))
        window.isReleasedWhenClosed = false
        window.collectionBehavior = [.moveToActiveSpace]
        window.delegate = self
        window.center()
        return window
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
            // Defer past the current AppKit layout pass — calling
            // setActivationPolicy(.accessory) inline during a window-close
            // animation triggers "layoutSubtreeIfNeeded on a view already
            // being laid out" warnings. RunLoop.main.perform schedules this
            // on the next .common runloop tick, after layout settles.
            RunLoop.main.perform {
                NSApp.setActivationPolicy(.accessory)
            }
        }
    }
}

// MARK: - What's New

extension AppDelegate {

    /// Shows the What's New sheet once per version for returning users.
    func checkWhatsNew() {
        let currentVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
        let lastSeen = UserDefaults.standard.string(forKey: AppConstants.UserDefaults.lastSeenWhatsNewVersion) ?? ""

        guard lastSeen != currentVersion else { return }

        // Don't show on first install (onboarding handles that)
        let hasCompletedOnboarding = UserDefaults.standard.bool(forKey: AppConstants.UserDefaults.hasCompletedOnboarding)
        guard hasCompletedOnboarding else { return }

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
        window.setContentSize(NSSize(width: 420, height: 540))
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        whatsNewWindow = window
        UserDefaults.standard.set(version, forKey: AppConstants.UserDefaults.lastSeenWhatsNewVersion)
    }
}

// MARK: - Onboarding Window

extension AppDelegate {

    /// Shows the first-launch onboarding wizard, or brings it forward if already visible.
    func showOnboarding() {
        if let existing = onboardingWindow, existing.isVisible {
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
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
        // contentView. Do NOT disable autoresizing or add identity constraints
        // — AppKit uses the autoresizing mask to keep the hosting view filling
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
                window.close()

                Task { [weak self] in
                    await self?.validateTwitchTokenOnBoot()
                }

                Log.info("AppDelegate: Onboarding dismissed, transitioning to normal app state", category: "App")
            })
        }
    }
}

// MARK: - NSWindowDelegate

extension AppDelegate: NSWindowDelegate {

    /// Handles cleanup when any owned window closes (onboarding, settings, or whatsNew).
    public func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }

        if window === onboardingWindow {
            if OnboardingViewModel.hasCompletedOnboarding == false {
                Log.info("AppDelegate: Onboarding window closed before completion — will show again on next launch", category: "App")
            }
            Task { @MainActor [weak self] in
                self?.onboardingWindow = nil
                self?.restoreMenuOnlyIfNeeded()
            }
        } else if window === settingsWindow {
            Task { @MainActor [weak self] in
                self?.settingsWindow = nil
                self?.restoreMenuOnlyIfNeeded()
            }
        } else if window === whatsNewWindow {
            Task { @MainActor [weak self] in
                self?.whatsNewWindow = nil
                self?.restoreMenuOnlyIfNeeded()
            }
        } else if window === aboutWindow {
            Task { @MainActor [weak self] in
                self?.aboutWindow = nil
                self?.restoreMenuOnlyIfNeeded()
            }
        }
    }
}

// MARK: - Settings Window

extension AppDelegate {

    /// Creates the Settings window with a transparent title bar and sidebar toolbar.
    private func createSettingsWindow() -> NSWindow {
        let hosting = NSHostingController(rootView: SettingsView())

        // Initial size: ideal for comfortable use, clamped to the visible screen so
        // the window never opens larger than e.g. a 720p display with Dock visible.
        let ideal = CGSize(
            width: AppConstants.SettingsUI.idealWidth,
            height: AppConstants.SettingsUI.idealHeight
        )
        let visible = NSScreen.main?.visibleFrame.size ?? ideal
        let initial = CGSize(
            width: min(ideal.width, visible.width),
            height: min(ideal.height, visible.height)
        )
        let frame = CGRect(origin: .zero, size: initial)

        let style: NSWindow.StyleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
        let window = NSWindow(contentRect: frame, styleMask: style, backing: .buffered, defer: false)
        window.contentMinSize = NSSize(
            width: AppConstants.SettingsUI.minWidth,
            height: AppConstants.SettingsUI.minHeight
        )
        // Assigning the hosting controller makes hosting.view the window's
        // contentView. Do NOT disable autoresizing or add identity constraints
        // — AppKit uses the autoresizing mask to keep the hosting view filling
        // the window. Disabling it left the view inset inside the window and
        // broke both the unified titlebar look and List hit-testing.
        window.contentViewController = hosting

        window.title = ""
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.collectionBehavior = [.moveToActiveSpace]
        window.canHide = true
        window.isReleasedWhenClosed = false
        window.delegate = self
        // Explicit NSToolbar gives SwiftUI's NavigationSplitView a guaranteed
        // titlebar host for its automatic sidebar toggle. Paired with
        // `.toolbar { }` in SettingsView so SwiftUI's toolbar host binds to
        // this NSToolbar instead of falling back to a floating reveal chevron.
        let toolbar = NSToolbar()
        toolbar.displayMode = .iconOnly
        window.toolbar = toolbar
        window.toolbarStyle = .unified
        window.center()
        return window
    }

    /// Activates the app and brings the window forward.
    ///
    /// - Important: Callers invoked from `NSStatusItem` menu tracking or any other
    ///   AppKit layout pass must defer to the next runloop tick (e.g. via
    ///   `RunLoop.main.perform`) before calling this — otherwise AppKit logs
    ///   "layoutSubtreeIfNeeded on a view already being laid out".
    func showWindow(_ window: NSWindow?) {
        window?.level = .normal
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}
