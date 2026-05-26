//
//  AppConstantsConfigOverrideTests.swift
//  WolfWave
//
//  Created by Nathanial Henniges on 2026-05-26.
//  Copyright © 2026 MrDemonWolf, Inc. All rights reserved.
//

import Testing
import Foundation
@testable import WolfWave

/// Covers `AppConstants.infoPlistString` — the shared helper that backs every
/// fork-overridable constant (docs URL, community Discord, copyright holder,
/// repo owner/name, display name).
@MainActor
@Suite("AppConstants Config Override")
struct AppConstantsConfigOverrideTests {

    // MARK: - Helper Behavior

    @Test("Falls back when Info.plist key is missing")
    func testFallbackWhenMissing() {
        let result = AppConstants.infoPlistString(
            "DOCS_URL",
            fallback: "https://example.com",
            plistLookup: { _ in nil },
            envLookup: { _ in nil }
        )
        #expect(result == "https://example.com")
    }

    @Test("Falls back when Info.plist holds the literal $(KEY) placeholder")
    func testFallbackOnUnexpandedPlaceholder() {
        let result = AppConstants.infoPlistString(
            "DOCS_URL",
            fallback: "https://example.com",
            plistLookup: { "$(\($0))" },
            envLookup: { _ in nil }
        )
        #expect(result == "https://example.com")
    }

    @Test("Falls back when Info.plist value is whitespace-only")
    func testFallbackOnWhitespace() {
        let result = AppConstants.infoPlistString(
            "DOCS_URL",
            fallback: "https://example.com",
            plistLookup: { _ in "   \n  " },
            envLookup: { _ in nil }
        )
        #expect(result == "https://example.com")
    }

    @Test("Uses Info.plist value when populated")
    func testUsesPlistValue() {
        let result = AppConstants.infoPlistString(
            "DOCS_URL",
            fallback: "https://example.com",
            plistLookup: { _ in "https://forkwave.dev" },
            envLookup: { _ in "https://wrong.example.com" }
        )
        #expect(result == "https://forkwave.dev")
    }

    @Test("Trims whitespace from Info.plist value")
    func testTrimsPlistValue() {
        let result = AppConstants.infoPlistString(
            "DOCS_URL",
            fallback: "https://example.com",
            plistLookup: { _ in "  https://forkwave.dev  \n" },
            envLookup: { _ in nil }
        )
        #expect(result == "https://forkwave.dev")
    }

    @Test("Falls through to env var when Info.plist is missing")
    func testEnvFallthrough() {
        let result = AppConstants.infoPlistString(
            "DOCS_URL",
            fallback: "https://example.com",
            plistLookup: { _ in nil },
            envLookup: { _ in "https://env-override.dev" }
        )
        #expect(result == "https://env-override.dev")
    }

    @Test("Falls through to env var when Info.plist holds the placeholder")
    func testEnvFallthroughOnPlaceholder() {
        let result = AppConstants.infoPlistString(
            "DOCS_URL",
            fallback: "https://example.com",
            plistLookup: { "$(\($0))" },
            envLookup: { _ in "https://env-override.dev" }
        )
        #expect(result == "https://env-override.dev")
    }

    @Test("Trims whitespace from env value")
    func testTrimsEnvValue() {
        let result = AppConstants.infoPlistString(
            "DOCS_URL",
            fallback: "https://example.com",
            plistLookup: { _ in nil },
            envLookup: { _ in "  https://env-override.dev  " }
        )
        #expect(result == "https://env-override.dev")
    }

    @Test("Falls back when env var is whitespace-only")
    func testFallbackOnWhitespaceEnv() {
        let result = AppConstants.infoPlistString(
            "DOCS_URL",
            fallback: "https://example.com",
            plistLookup: { _ in nil },
            envLookup: { _ in "   " }
        )
        #expect(result == "https://example.com")
    }

    // MARK: - Production-Bundle Fallbacks

    /// In the unit-test host (WolfWave.app), Info.plist values are present at
    /// build time — but if a fork builds without Config.xcconfig, every
    /// override-backed constant should still resolve to the upstream default.
    @Test("All override-backed constants have non-empty production values")
    func testProductionConstantsResolve() {
        #expect(!AppConstants.AppInfo.displayName.isEmpty)
        #expect(!AppConstants.AppInfo.copyrightHolder.isEmpty)
        #expect(!AppConstants.URLs.docs.isEmpty)
        #expect(!AppConstants.URLs.communityDiscord.isEmpty)
        #expect(!AppConstants.URLs.repoOwner.isEmpty)
        #expect(!AppConstants.URLs.repoName.isEmpty)
    }

    @Test("repoOwner + repoName regression after helper refactor")
    func testRepoConstantsAfterRefactor() {
        // These read from the hosted Info.plist; values come from
        // Config.xcconfig in dev or fallback in a clean fork build.
        #expect(AppConstants.URLs.repoOwner == "MrDemonWolf"
                || AppConstants.URLs.repoOwner == "mrdemonwolf")
        #expect(AppConstants.URLs.repoName == "wolfwave")
    }

    @Test("Derived URLs follow the docs root")
    func testDerivedURLsTrackDocs() {
        #expect(AppConstants.URLs.privacyPolicy.hasPrefix(AppConstants.URLs.docs))
        #expect(AppConstants.URLs.termsOfService.hasPrefix(AppConstants.URLs.docs))
        #expect(AppConstants.URLs.changelog.hasPrefix(AppConstants.URLs.docs))
    }
}
