//
//  BugReportURL.swift
//  WolfWave
//
//  Created by Nathanial Henniges on 2026-05-15.
//  Copyright © 2026 MrDemonWolf, Inc. All rights reserved.
//

import Foundation

/// Builds a GitHub new-issue URL with a prefilled body containing system
/// information so users can file bug reports with minimal friction.
///
/// The generated URL targets the `bug_report.yml` issue form template at
/// the project repository and embeds:
/// - App version + build
/// - macOS version
/// - CPU architecture
/// - Install method (Homebrew vs DMG)
///
/// Kept as a pure value type to allow unit testing without UI dependencies.
enum BugReportURL {

    // MARK: - Install Method

    /// How WolfWave was installed on the user's machine.
    enum InstallMethod: String {
        case homebrew = "Homebrew"
        case dmg = "DMG"
    }

    // MARK: - Building

    /// Builds the GitHub issue URL.
    ///
    /// - Parameters:
    ///   - base: Base new-issue URL (e.g. `AppConstants.URLs.githubIssuesNew`).
    ///   - appVersion: Marketing version string (e.g. "1.2.0").
    ///   - build: Build number string.
    ///   - osVersion: Operating system version description.
    ///   - arch: CPU architecture identifier (e.g. "arm64").
    ///   - install: How the app was installed.
    /// - Returns: A URL pointing to the GitHub issue form with prefilled body,
    ///   or `nil` if the base URL is malformed.
    /// Builds the issue URL from a captured ``DiagnosticSnapshot``.
    ///
    /// Preferred over the field-by-field overload: the snapshot also carries the
    /// crash flag, log size, and diagnostics opt-in. "Report a Bug" is the
    /// primary button on the crash-recovery callout, and it used to open a form
    /// that said nothing about the crash at all.
    static func make(base: String, snapshot: DiagnosticSnapshot) -> URL? {
        make(base: base, environment: snapshot.markdownBullets)
    }

    static func make(
        base: String,
        appVersion: String,
        build: String,
        osVersion: String,
        arch: String,
        install: InstallMethod
    ) -> URL? {
        make(base: base, environment: """
            - **App version:** \(appVersion) (build \(build))
            - **macOS:** \(osVersion)
            - **Architecture:** \(arch)
            - **Install method:** \(install.rawValue)
            """)
    }

    private static func make(base: String, environment: String) -> URL? {
        guard var components = URLComponents(string: base) else { return nil }

        let body = """
        ## Description

        <!-- What went wrong? -->

        ## Steps to Reproduce

        1.
        2.
        3.

        ## Expected Behavior

        ## Actual Behavior

        ## Environment

        \(environment)

        ## Logs

        <!--
        Attach the exported diagnostics file, or paste the relevant part here.
        Settings → Advanced → Export Logs writes one file containing your
        environment, the last crash if there was one, and every rotated log.
        -->
        """

        components.queryItems = [
            URLQueryItem(name: "template", value: "bug_report.yml"),
            URLQueryItem(name: "labels", value: "bug"),
            URLQueryItem(name: "title", value: "[Bug] "),
            URLQueryItem(name: "body", value: body)
        ]

        return components.url
    }

    // MARK: - Actions

    /// Gathers the running app's environment (version, build, macOS version,
    /// architecture, install method) and opens the prefilled GitHub issue form
    /// in the default browser.
    ///
    /// Shared by the tray menu's "Report a Bug" and the About pane's
    /// "Send Feedback" so environment assembly lives in one place.
    @MainActor
    static func openPrefilledIssue() {
        // Snapshot form, so the report carries the crash flag, log size, and
        // diagnostics opt-in rather than four environment lines and no state.
        let url = make(
            base: AppConstants.URLs.githubIssuesNew,
            snapshot: DiagnosticSnapshot.capture(logSizeBytes: Log.logFileSize())
        )
        guard let url else {
            Log.error("BugReportURL: Failed to build bug report URL", category: .app)
            return
        }
        ExternalLink.open(url.absoluteString)
    }

    // MARK: - Helpers

    /// Returns the current process's CPU architecture identifier.
    static func currentArch() -> String {
        #if arch(arm64)
        return "arm64"
        #elseif arch(x86_64)
        return "x86_64"
        #else
        return "unknown"
        #endif
    }
}
