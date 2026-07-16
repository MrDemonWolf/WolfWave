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
    static func make(
        base: String,
        appVersion: String,
        build: String,
        osVersion: String,
        arch: String,
        install: InstallMethod
    ) -> URL? {
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

        - **App version:** \(appVersion) (build \(build))
        - **macOS:** \(osVersion)
        - **Architecture:** \(arch)
        - **Install method:** \(install.rawValue)

        ## Logs

        <!--
        Paste relevant log output here, or attach the exported log file.
        You can export logs from Settings → Advanced → Export Logs.
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
        let url = make(
            base: AppConstants.URLs.githubIssuesNew,
            appVersion: AppConstants.AppInfo.shortVersion,
            build: AppConstants.AppInfo.buildNumber,
            osVersion: ProcessInfo.processInfo.operatingSystemVersionString,
            arch: currentArch(),
            install: Bundle.main.isHomebrewInstall ? .homebrew : .dmg
        )
        guard let url else {
            Log.error("BugReportURL: Failed to build bug report URL", category: "App")
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
