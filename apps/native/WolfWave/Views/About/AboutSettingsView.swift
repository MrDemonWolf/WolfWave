//
//  AboutSettingsView.swift
//  WolfWave
//
//  Created by Nathanial Henniges on 2026-05-15.
//  Copyright © 2026 MrDemonWolf, Inc. All rights reserved.
//

import AppKit
import SwiftUI

/// About pane shown in the Settings sidebar. Single source of truth for app
/// identity, quick actions, and legal links. Replaces the legacy standalone
/// About window. Uses the same section-header + `.cardStyle()` rhythm as
/// `AdvancedSettingsView` / `GeneralSettingsView`.
struct AboutSettingsView: View {

    // MARK: - State

    @State private var versionCopied = false

    // MARK: - Bundle Info (shared with the menu bar's standard About panel)

    private var appName: String { AboutCopy.appName }
    private var version: String { AboutCopy.version }
    private var build: String { AboutCopy.build }
    private var versionString: String { AboutCopy.versionString }

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
            acknowledgementsCard
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

            hero
        }
        .cardStyle()
    }

    /// Identity hero: app icon on the leading edge, name + version pill stacked
    /// on the trailing side. Mirrors the system standard About panel's
    /// icon-left / text-right layout.
    private var hero: some View {
        HStack(alignment: .center, spacing: DSSpace.s5) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 72, height: 72)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: DSSpace.s2) {
                Text(appName)
                    .font(.system(size: DSFont.Size.x2xl, weight: .semibold))
                    .accessibilityAddTraits(.isHeader)
                versionPill
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var versionPill: some View {
        Button(action: copyVersion) {
            HStack(spacing: DSSpace.s1h) {
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
                Text("Release notes, website, feedback, and sponsorship.")
                    .font(.system(size: DSFont.Size.sm))
                    .foregroundStyle(.secondary)
            }

            actionGrid
        }
        .cardStyle()
    }

    private var actionGrid: some View {
        ActionGrid(columns: 2) {
            GridRow {
                ActionGridButton(title: "Release Notes", systemImage: "list.bullet.rectangle", action: openReleaseNotes,
                                 accessibilityIdentifier: "about-settings.action.Release Notes")
                ActionGridButton(title: "Website", systemImage: "globe", action: openWebsite,
                                 accessibilityIdentifier: "about-settings.action.Website")
            }
            GridRow {
                ActionGridButton(title: "Send Feedback", systemImage: "envelope", action: sendFeedback,
                                 accessibilityIdentifier: "about-settings.action.Send Feedback")
                ActionGridButton(title: "Sponsor on GitHub", systemImage: "heart.fill", action: openSponsor,
                                 accessibilityIdentifier: "about-settings.action.Sponsor on GitHub")
            }
        }
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

            VStack(alignment: .leading, spacing: DSSpace.s3) {
                legalLinksRow
                footer
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .cardStyle()
    }

    // MARK: - Legal Links

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
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: DSSpace.s1h) {
            Text(AboutCopy.independenceNotice)
                .font(.system(size: DSFont.Size.xs))
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)

            Text(AboutCopy.trademarkNotice)
                .font(.system(size: DSFont.Size.xs))
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)

            Text(AboutCopy.copyrightLine)
                .font(.system(size: DSFont.Size.xs))
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Acknowledgements Card

    private var acknowledgementsCard: some View {
        VStack(alignment: .leading, spacing: DSSpace.s4) {
            VStack(alignment: .leading, spacing: DSSpace.s1) {
                Text("Acknowledgements")
                    .font(.system(size: DSFont.Size.base, weight: .semibold))
                Text("Third-party services and open-source software WolfWave depends on.")
                    .font(.system(size: DSFont.Size.sm))
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: DSSpace.s4) {
                acknowledgementsSection(
                    title: "Third-party services",
                    rows: [
                        "Twitch: EventSub WebSocket + Helix API",
                        "Discord: local IPC Rich Presence",
                        "Apple Music: ScriptingBridge and MusicKit",
                        "Odesli (song.link): cross-platform track link API",
                        "iTunes Search API: album artwork and Apple Music URLs"
                    ]
                )

                acknowledgementsSection(
                    title: "Open source",
                    rows: [
                        "Sparkle: auto-update framework (MIT license)"
                    ]
                )

                if let url = URL(string: AppConstants.URLs.acknowledgements) {
                    Link("View full licenses and notices", destination: url)
                        .font(.system(size: DSFont.Size.sm))
                        .accessibilityLabel("Open acknowledgements and license notices")
                        .accessibilityIdentifier("about-settings.link.acknowledgements")
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .cardStyle()
    }

    private func acknowledgementsSection(title: String, rows: [String]) -> some View {
        VStack(alignment: .leading, spacing: DSSpace.s2) {
            Text(title)
                .font(.system(size: DSFont.Size.sm, weight: .semibold))
                .foregroundStyle(.secondary)
            ForEach(rows, id: \.self) { row in
                Text("• \(row)")
                    .font(.system(size: DSFont.Size.sm))
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: - Actions

    private func copyVersion() {
        let payload = AboutCopy.versionClipboardPayload
        Pasteboard.copy(payload)

        withAnimation(.easeInOut(duration: DSMotion.Duration.fast)) { versionCopied = true }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(1500))
            withAnimation(.easeInOut(duration: DSMotion.Duration.base)) { versionCopied = false }
        }
    }

    private func openReleaseNotes() {
        ExternalLink.open(AppConstants.URLs.changelog)
    }

    private func openSponsor() {
        ExternalLink.open(AppConstants.URLs.githubSponsors)
    }

    private func openWebsite() {
        ExternalLink.open(AppConstants.URLs.docs)
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
