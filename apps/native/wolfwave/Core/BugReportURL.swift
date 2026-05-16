//
//  BugReportURL.swift
//  wolfwave
//
//  Created by MrDemonWolf, Inc. on 5/15/26.
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

    /// How WolfWave was installed on the user's machine.
    enum InstallMethod: String {
        case homebrew = "Homebrew"
        case dmg = "DMG"
    }

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
