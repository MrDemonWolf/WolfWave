//
//  AppConstants+URLs.swift
//  WolfWave
//
//  Created by Nathanial Henniges on 2026-07-15.
//  Copyright © 2026 MrDemonWolf, Inc. All rights reserved.
//

import Foundation

extension AppConstants {
    /// Application URLs for documentation, legal, and GitHub.
    nonisolated enum URLs {
        /// Documentation site URL. Override via `DOCS_URL` in `Config.xcconfig`.
        ///
        /// Guards against the xcconfig `//`-comment gotcha: if a misconfigured
        /// build truncates the value to something without a `://` scheme (e.g.
        /// `https:`), fall back to the upstream default so privacy/terms/
        /// acknowledgements links never ship broken.
        static let docs = validURL(
            infoPlistString("DOCS_URL", fallback: "https://mrdemonwolf.github.io/wolfwave"),
            fallback: "https://mrdemonwolf.github.io/wolfwave"
        )

        /// Privacy policy page URL (derived from `docs`).
        static let privacyPolicy = "\(docs)/docs/privacy-policy"

        /// Terms of service page URL (derived from `docs`).
        static let termsOfService = "\(docs)/docs/terms-of-service"

        /// Third-party acknowledgements + license notices page URL.
        static let acknowledgements = "\(docs)/docs/acknowledgements"

        /// Documentation changelog page URL (Fumadocs route).
        static let changelog = "\(docs)/docs/changelog"

        /// GitHub repository owner. Lookup: `GITHUB_REPO_OWNER` Info.plist key
        /// → env var → `"mrdemonwolf"`.
        static let repoOwner = infoPlistString(
            "GITHUB_REPO_OWNER",
            fallback: "mrdemonwolf"
        )

        /// GitHub repository name. Lookup: `GITHUB_REPO_NAME` Info.plist key
        /// → env var → `"wolfwave"`.
        static let repoName = infoPlistString(
            "GITHUB_REPO_NAME",
            fallback: "wolfwave"
        )

        /// GitHub repository URL (resolved from config)
        static let github = "https://github.com/\(repoOwner)/\(repoName)"

        /// GitHub Releases page URL (resolved from config)
        static let githubReleases = "https://github.com/\(repoOwner)/\(repoName)/releases"

        /// GitHub new-issue page URL (resolved from config)
        static let githubIssuesNew = "https://github.com/\(repoOwner)/\(repoName)/issues/new"

        /// GitHub Sponsors username.
        ///
        /// Auto-derived from `.github/FUNDING.yml` by `scripts/generate-sponsor-config.sh`
        /// and committed as `SponsorConfig.generated.swift`. Falls back to `repoOwner`
        /// if the generated value is empty.
        @MainActor
        static var sponsorUser: String {
            let generated = SponsorConfig.sponsorUser.trimmingCharacters(in: .whitespacesAndNewlines)
            return generated.isEmpty ? repoOwner : generated
        }

        /// GitHub Sponsors page URL (resolved from FUNDING.yml)
        @MainActor
        static var githubSponsors: String { "https://github.com/sponsors/\(sponsorUser)" }

        /// Community Discord invite: opened from the tray menu "Help ▸ Join Discord Community".
        /// Override via `COMMUNITY_DISCORD_URL` in `Config.xcconfig`.
        static let communityDiscord = validURL(
            infoPlistString("COMMUNITY_DISCORD_URL", fallback: "https://mrdwolf.net/discord"),
            fallback: "https://mrdwolf.net/discord"
        )

        /// System Settings deep link to Notifications (macOS 13+).
        /// Opened from onboarding and `NotificationService` so users can grant
        /// the notification permission outside the app.
        static let systemNotificationSettings =
            "x-apple.systempreferences:com.apple.Notifications-Settings.extension"

        /// System Settings deep link to Privacy & Security ▸ Automation (macOS 13+).
        /// Opened from the Apple Music permission flow.
        static let systemAutomationSettings =
            "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation"

        /// Returns `value` when it parses as an absolute URL with a scheme and
        /// host, otherwise `fallback`. Catches xcconfig `//`-truncated values
        /// like `https:` that would otherwise produce broken links.
        private static func validURL(_ value: String, fallback: String) -> String {
            guard let url = URL(string: value), url.scheme != nil, url.host != nil else {
                return fallback
            }
            return value
        }
    }
}
