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
    @objc func openSettings() {
        statusItem?.menu?.cancelTracking()

        if currentDockVisibilityMode == AppConstants.DockVisibility.menuOnly {
            NSApp.setActivationPolicy(.regular)
        }

        if let window = settingsWindow {
            if window.isVisible {
                window.level = .normal
                window.makeKeyAndOrderFront(nil)
                NSApp.activate(ignoringOtherApps: true)
            } else if window.isMiniaturized {
                window.deminiaturize(nil)
                window.makeKeyAndOrderFront(nil)
                NSApp.activate(ignoringOtherApps: true)
            } else {
                Log.debug("AppDelegate: Settings window exists but is not visible - waiting for close to complete", category: "App")
            }
        } else {
            settingsWindow = createSettingsWindow()
            showWindow(settingsWindow)
        }
    }

    /// Shows the About panel with documentation and legal links.
    @objc func showAbout() {
        statusItem?.menu?.cancelTracking()

        if currentDockVisibilityMode == AppConstants.DockVisibility.menuOnly {
            NSApp.setActivationPolicy(.regular)
        }

        let credits = buildAboutCredits()
        NSApp.orderFrontStandardAboutPanel(options: [
            .applicationName: appName,
            .credits: credits,
        ])
        NSApp.activate(ignoringOtherApps: true)
    }

    /// Builds the About panel credits with linked documentation and legal pages.
    private func buildAboutCredits() -> NSAttributedString {
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = .center
        paragraphStyle.lineSpacing = 4

        let baseAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 11),
            .foregroundColor: NSColor.secondaryLabelColor,
            .paragraphStyle: paragraphStyle,
        ]

        let linkAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 11),
            .paragraphStyle: paragraphStyle,
        ]

        let credits = NSMutableAttributedString()

        let docsLink = NSMutableAttributedString(string: "Documentation", attributes: linkAttributes)
        docsLink.addAttribute(.link, value: AppConstants.URLs.docs, range: NSRange(location: 0, length: docsLink.length))
        credits.append(docsLink)

        credits.append(NSAttributedString(string: "  ·  ", attributes: baseAttributes))

        let ppLink = NSMutableAttributedString(string: "Privacy Policy", attributes: linkAttributes)
        ppLink.addAttribute(.link, value: AppConstants.URLs.privacyPolicy, range: NSRange(location: 0, length: ppLink.length))
        credits.append(ppLink)

        credits.append(NSAttributedString(string: "  ·  ", attributes: baseAttributes))

        let tosLink = NSMutableAttributedString(string: "Terms", attributes: linkAttributes)
        tosLink.addAttribute(.link, value: AppConstants.URLs.termsOfService, range: NSRange(location: 0, length: tosLink.length))
        credits.append(tosLink)

        credits.append(NSAttributedString(string: "\n\n", attributes: baseAttributes))
        credits.append(NSAttributedString(
            string: "Twitch, Discord, OBS, and Apple Music are trademarks of their respective owners. WolfWave is not affiliated with or endorsed by any of them.",
            attributes: baseAttributes
        ))

        return credits
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
            guard window.isVisible, window.canBecomeKey, window.level == .normal else { return false }
            // Exclude the system About panel — it is owned by AppKit and closes asynchronously
            guard window.className != "NSAboutPanel" else { return false }
            return true
        }

        if !hasVisibleWindows {
            NSApp.setActivationPolicy(.accessory)
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

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            self?.showWhatsNew(version: currentVersion)
        }
    }

    /// Presents the What's New window and marks this version as seen.
    private func showWhatsNew(version: String) {
        let whatsNewView = WhatsNewView()
        let hostingController = NSHostingController(rootView: whatsNewView)
        let window = NSWindow(contentViewController: hostingController)
        window.title = "What's New"
        window.styleMask = [.titled, .closable]
        window.setContentSize(NSSize(width: 420, height: 500))
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
        window.contentViewController = hosting
        hosting.view.translatesAutoresizingMaskIntoConstraints = false
        if let contentView = window.contentView {
            NSLayoutConstraint.activate([
                hosting.view.topAnchor.constraint(equalTo: contentView.topAnchor),
                hosting.view.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
                hosting.view.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
                hosting.view.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            ])
        }
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
        DispatchQueue.main.async { [weak self] in
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
            DispatchQueue.main.async { [weak self] in
                self?.onboardingWindow = nil
                self?.restoreMenuOnlyIfNeeded()
            }
        } else if window === settingsWindow {
            DispatchQueue.main.async { [weak self] in
                self?.settingsWindow = nil
                self?.restoreMenuOnlyIfNeeded()
            }
        } else if window === whatsNewWindow {
            DispatchQueue.main.async { [weak self] in
                self?.whatsNewWindow = nil
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
        let frame = CGRect(x: 0, y: 0, width: AppConstants.UI.settingsWidth, height: AppConstants.UI.settingsHeight)
        let style: NSWindow.StyleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
        let window = NSWindow(contentRect: frame, styleMask: style, backing: .buffered, defer: false)
        window.contentViewController = hosting
        hosting.view.translatesAutoresizingMaskIntoConstraints = false
        if let contentView = window.contentView {
            NSLayoutConstraint.activate([
                hosting.view.topAnchor.constraint(equalTo: contentView.topAnchor),
                hosting.view.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
                hosting.view.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
                hosting.view.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            ])
        }

        window.title = ""
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.collectionBehavior = [.moveToActiveSpace]
        window.canHide = true
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.center()
        return window
    }

    func showWindow(_ window: NSWindow?) {
        window?.level = .normal
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
