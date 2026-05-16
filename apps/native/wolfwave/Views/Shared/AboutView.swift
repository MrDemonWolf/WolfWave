//
//  AboutView.swift
//  wolfwave
//
//  Created by MrDemonWolf, Inc. on 5/15/26.
//

/// Custom About panel — branded hero, copyable version, primary actions, and legal links.
///
/// Replaces `NSApp.orderFrontStandardAboutPanel`. Presented as a fixed-size,
/// non-resizable `NSWindow` by `AppDelegate.showAbout()`. Mirrors the
/// presentation pattern of `WhatsNewView` for visual parity with the rest of
/// the macOS 26 Liquid Glass design language.

import AppKit
import SwiftUI

struct AboutView: View {

    // MARK: - State

    /// Whether the "copied" checkmark is currently shown on the version pill.
    @State private var versionCopied = false

    // MARK: - Bundle Info

    private var appName: String {
        Bundle.main.infoDictionary?["CFBundleDisplayName"] as? String
            ?? Bundle.main.infoDictionary?["CFBundleName"] as? String
            ?? AppConstants.AppInfo.displayName
    }

    private var version: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
    }

    private var build: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "—"
    }

    private var versionString: String {
        "Version \(version) (\(build))"
    }

    // MARK: - Body

    var body: some View {
        VStack(spacing: 18) {
            hero
            versionPill
            actionGrid
            legalLinksRow
            footer
        }
        .padding(24)
        .frame(width: 360, height: 480)
        .accessibilityIdentifier("about.root")
    }

    // MARK: - Hero

    private var hero: some View {
        VStack(spacing: 10) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 96, height: 96)
                .accessibilityHidden(true)

            Text(appName)
                .font(.system(size: 22, weight: .semibold))
                .accessibilityAddTraits(.isHeader)
        }
    }

    // MARK: - Version Pill

    private var versionPill: some View {
        Button(action: copyVersion) {
            HStack(spacing: 6) {
                Text(versionString)
                    .font(.system(size: 12, weight: .medium))
                Image(systemName: versionCopied ? "checkmark" : "doc.on.doc")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(versionCopied ? .green : .secondary)
            }
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .pointerCursor()
        .help("Copy version info to clipboard")
        .accessibilityLabel("\(versionString). Click to copy.")
        .accessibilityIdentifier("about.versionPill")
    }

    // MARK: - Action Grid

    private var actionGrid: some View {
        Grid(horizontalSpacing: 8, verticalSpacing: 8) {
            GridRow {
                actionButton("Check for Updates", systemImage: "arrow.down.circle", action: checkForUpdates)
                actionButton("Release Notes", systemImage: "list.bullet.rectangle", action: openReleaseNotes)
            }
            GridRow {
                actionButton("Website", systemImage: "globe", action: openWebsite)
                actionButton("Send Feedback", systemImage: "envelope", action: sendFeedback)
            }
        }
    }

    /// Builds a single bordered grid button for the action grid (Open Logs,
    /// Website, Send Feedback, Check for Updates).
    ///
    /// - Parameters:
    ///   - title: Visible label.
    ///   - systemImage: SF Symbol name displayed beside the title.
    ///   - action: Closure invoked on press.
    /// - Returns: A grid-friendly bordered button.
    private func actionButton(_ title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.system(size: 12, weight: .medium))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 2)
        }
        .buttonStyle(.bordered)
        .controlSize(.regular)
        .pointerCursor()
        .accessibilityIdentifier("about.action.\(title)")
    }

    // MARK: - Legal Links

    private var legalLinksRow: some View {
        HStack(spacing: 10) {
            Link("Documentation", destination: URL(string: AppConstants.URLs.docs)!)
            Text("·").foregroundStyle(.tertiary)
            Link("Privacy", destination: URL(string: AppConstants.URLs.privacyPolicy)!)
            Text("·").foregroundStyle(.tertiary)
            Link("Terms", destination: URL(string: AppConstants.URLs.termsOfService)!)
        }
        .font(.system(size: 11))
        .accessibilityElement(children: .contain)
    }

    // MARK: - Footer

    private var footer: some View {
        VStack(spacing: 6) {
            Text("Twitch, Discord, OBS, and Apple Music are trademarks of their respective owners. WolfWave is not affiliated with or endorsed by any of them.")
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            Text("© 2026 MrDemonWolf, Inc. All rights reserved.")
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
        }
    }

    // MARK: - Actions

    /// Copies a support-friendly version string to the system pasteboard.
    private func copyVersion() {
        let payload = "\(appName) \(version) (build \(build))"
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(payload, forType: .string)

        withAnimation(.easeInOut(duration: 0.15)) { versionCopied = true }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(1500))
            withAnimation(.easeInOut(duration: 0.2)) { versionCopied = false }
        }
    }

    /// Triggers a manual Sparkle update check. No-op for Homebrew installs
    /// (Sparkle itself logs a warning in that case).
    private func checkForUpdates() {
        AppDelegate.shared?.sparkleUpdater?.checkForUpdates()
    }

    /// Opens the GitHub Releases page in the user's default browser.
    private func openReleaseNotes() {
        guard let url = URL(string: AppConstants.URLs.githubReleases) else { return }
        NSWorkspace.shared.open(url)
    }

    /// Opens the WolfWave documentation site in the user's default browser.
    private func openWebsite() {
        guard let url = URL(string: AppConstants.URLs.docs) else { return }
        NSWorkspace.shared.open(url)
    }

    /// Opens a pre-filled GitHub bug report — same flow as
    /// Settings → Advanced → Send Feedback.
    private func sendFeedback() {
        let path = Bundle.main.bundlePath
        let homebrewPaths = ["/opt/homebrew/", "/usr/local/Cellar/", "/Homebrew/"]
        let isHomebrew = homebrewPaths.contains { path.contains($0) }

        guard let url = BugReportURL.make(
            base: AppConstants.URLs.githubIssuesNew,
            appVersion: version,
            build: build,
            osVersion: ProcessInfo.processInfo.operatingSystemVersionString,
            arch: BugReportURL.currentArch(),
            install: isHomebrew ? .homebrew : .dmg
        ) else {
            Log.error("AboutView: Failed to build bug report URL", category: "App")
            return
        }
        NSWorkspace.shared.open(url)
    }
}

// MARK: - Preview

#Preview {
    AboutView()
}
