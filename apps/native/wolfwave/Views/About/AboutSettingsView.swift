//
//  AboutSettingsView.swift
//  wolfwave
//
//  Created by MrDemonWolf, Inc. on 5/25/26.
//

import AppKit
import SwiftUI

/// About pane shown in the Settings sidebar. Single source of truth for app
/// identity, quick actions, and legal links — replaces the legacy standalone
/// About window. Uses the same section-header + `.cardStyle()` rhythm as
/// `AdvancedSettingsView` / `GeneralSettingsView`.
struct AboutSettingsView: View {

    // MARK: - State

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
        VStack(alignment: .leading, spacing: DSSpace.s6) {
            SectionHeaderWithStatus(
                title: "About",
                subtitle: "App info, links, and legal."
            )

            identityCard
            actionsCard
            linksCard
        }
        .accessibilityIdentifier("about-settings.root")
    }

    // MARK: - Identity Card

    private var identityCard: some View {
        VStack(alignment: .leading, spacing: DSSpace.s4) {
            VStack(alignment: .leading, spacing: DSSpace.s1) {
                Text("Identity")
                    .font(.system(size: DSFont.Size.base, weight: .semibold))
                Text("App name, version, and quick-copy build info.")
                    .font(.system(size: DSFont.Size.sm))
                    .foregroundStyle(.secondary)
            }

            VStack(spacing: DSSpace.s3) {
                hero
                versionPill
            }
            .frame(maxWidth: .infinity)
        }
        .cardStyle()
    }

    private var hero: some View {
        VStack(spacing: DSSpace.s3) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 96, height: 96)
                .accessibilityHidden(true)

            Text(appName)
                .font(.system(size: DSFont.Size.x2xl, weight: .semibold))
                .accessibilityAddTraits(.isHeader)
        }
    }

    private var versionPill: some View {
        Button(action: copyVersion) {
            HStack(spacing: 6) {
                Text(versionString)
                    .font(.system(size: DSFont.Size.body, weight: .medium))
                Image(systemName: versionCopied ? "checkmark" : "doc.on.doc")
                    .font(.system(size: DSFont.Size.xs, weight: .semibold))
                    .foregroundStyle(versionCopied ? .green : .secondary)
            }
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .pointerCursor()
        .help("Copy version info to clipboard")
        .accessibilityLabel("\(versionString). Click to copy.")
        .accessibilityIdentifier("about-settings.versionPill")
    }

    // MARK: - Actions Card

    private var actionsCard: some View {
        VStack(alignment: .leading, spacing: DSSpace.s4) {
            VStack(alignment: .leading, spacing: DSSpace.s1) {
                Text("Quick actions")
                    .font(.system(size: DSFont.Size.base, weight: .semibold))
                Text("Updates, release notes, feedback, and sponsorship.")
                    .font(.system(size: DSFont.Size.sm))
                    .foregroundStyle(.secondary)
            }

            actionGrid
        }
        .cardStyle()
    }

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
            GridRow {
                actionButton("Sponsor on GitHub", systemImage: "heart.fill", action: openSponsor)
                    .gridCellColumns(2)
            }
        }
    }

    private func actionButton(_ title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.system(size: DSFont.Size.body, weight: .medium))
                .frame(maxWidth: .infinity)
                .padding(.vertical, DSSpace.s0)
        }
        .buttonStyle(.bordered)
        .controlSize(.regular)
        .pointerCursor()
        .accessibilityLabel(title)
        .accessibilityIdentifier("about-settings.action.\(title)")
    }

    // MARK: - Links & Legal Card

    private var linksCard: some View {
        VStack(alignment: .leading, spacing: DSSpace.s4) {
            VStack(alignment: .leading, spacing: DSSpace.s1) {
                Text("Links & legal")
                    .font(.system(size: DSFont.Size.base, weight: .semibold))
                Text("Documentation, policies, and attributions.")
                    .font(.system(size: DSFont.Size.sm))
                    .foregroundStyle(.secondary)
            }

            VStack(spacing: DSSpace.s3) {
                legalLinksRow
                footer
            }
            .frame(maxWidth: .infinity)
        }
        .cardStyle()
    }

    private var legalLinksRow: some View {
        HStack(spacing: DSSpace.s3) {
            if let url = URL(string: AppConstants.URLs.docs) {
                Link("Documentation", destination: url)
                    .accessibilityLabel("Open WolfWave documentation")
                    .accessibilityIdentifier("about-settings.link.docs")
            }
            Text("·").foregroundStyle(.tertiary)
            if let url = URL(string: AppConstants.URLs.privacyPolicy) {
                Link("Privacy", destination: url)
                    .accessibilityLabel("Open privacy policy")
                    .accessibilityIdentifier("about-settings.link.privacy")
            }
            Text("·").foregroundStyle(.tertiary)
            if let url = URL(string: AppConstants.URLs.termsOfService) {
                Link("Terms", destination: url)
                    .accessibilityLabel("Open terms of service")
                    .accessibilityIdentifier("about-settings.link.terms")
            }
        }
        .font(.system(size: DSFont.Size.sm))
        .accessibilityElement(children: .contain)
    }

    private var footer: some View {
        VStack(spacing: 6) {
            Text("Twitch, Discord, OBS, and Apple Music are trademarks of their respective owners. WolfWave is not affiliated with or endorsed by any of them.")
                .font(.system(size: DSFont.Size.xs))
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            Text("© 2026 \(AppConstants.AppInfo.copyrightHolder) All rights reserved.")
                .font(.system(size: DSFont.Size.xs))
                .foregroundStyle(.tertiary)
        }
    }

    // MARK: - Actions

    private func copyVersion() {
        let payload = "\(appName) \(version) (build \(build))"
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(payload, forType: .string)

        withAnimation(.easeInOut(duration: DSMotion.Duration.fast)) { versionCopied = true }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(1500))
            withAnimation(.easeInOut(duration: DSMotion.Duration.base)) { versionCopied = false }
        }
    }

    private func checkForUpdates() {
        if AppDelegate.shared?.sparkleUpdater?.checkForUpdates() != true {
            if let url = URL(string: AppConstants.URLs.githubReleases) {
                NSWorkspace.shared.open(url)
            }
        }
    }

    private func openReleaseNotes() {
        guard let url = URL(string: AppConstants.URLs.changelog) else { return }
        NSWorkspace.shared.open(url)
    }

    private func openSponsor() {
        guard let url = URL(string: AppConstants.URLs.githubSponsors) else { return }
        NSWorkspace.shared.open(url)
    }

    private func openWebsite() {
        guard let url = URL(string: AppConstants.URLs.docs) else { return }
        NSWorkspace.shared.open(url)
    }

    private func sendFeedback() {
        let isHomebrew = Bundle.main.isHomebrewInstall

        guard let url = BugReportURL.make(
            base: AppConstants.URLs.githubIssuesNew,
            appVersion: version,
            build: build,
            osVersion: ProcessInfo.processInfo.operatingSystemVersionString,
            arch: BugReportURL.currentArch(),
            install: isHomebrew ? .homebrew : .dmg
        ) else {
            Log.error("AboutSettingsView: Failed to build bug report URL", category: "App")
            return
        }
        NSWorkspace.shared.open(url)
    }
}

// MARK: - Preview

#Preview {
    AboutSettingsView()
        .padding()
        .frame(width: 700)
}
