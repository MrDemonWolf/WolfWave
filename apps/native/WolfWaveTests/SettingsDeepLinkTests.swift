//
//  SettingsDeepLinkTests.swift
//  WolfWave
//
//  Created by Nathanial Henniges on 2026-09-01.
//  Copyright © 2026 MrDemonWolf, Inc. All rights reserved.
//

import Foundation
import Testing
@testable import WolfWave

@Suite("Settings deep links")
struct SettingsDeepLinkTests {
    private typealias Section = SettingsView.SettingsSection

    private func parse(_ string: String) -> SettingsDeepLink {
        guard let url = URL(string: string) else {
            Issue.record("not a URL: \(string)")
            return .general
        }
        return SettingsDeepLink.parse(url)
    }

    // MARK: - Slugs

    @Test("every pane slug is unique, kebab-case, and not its display title")
    func slugsAreStable() {
        let slugs = Section.allCases.map(\.slug)
        #expect(Set(slugs).count == slugs.count)
        for section in Section.allCases {
            #expect(SettingsDeepLink.isValidSectionSlug(section.slug), "\(section.slug)")
            #expect(section.slug != section.rawValue, "slug must not be the visible title")
            #expect(Section(slug: section.slug) == section)
            #expect(Section(slug: section.slug.uppercased()) == section)
        }
    }

    @Test("pinned pane slugs (docs link to these; changing one breaks the docs)")
    func pinnedSlugs() {
        #expect(Section.general.slug == "general")
        #expect(Section.songRequests.slug == "song-requests")
        #expect(Section.websocket.slug == "stream-widgets")
        #expect(Section.streamDeck.slug == "stream-deck")
        #expect(Section.historyStats.slug == "history-stats")
        #expect(Section.twitchIntegration.slug == "twitch")
        #expect(Section.discord.slug == "discord")
        #expect(Section.softwareUpdate.slug == "software-update")
        #expect(Section.advanced.slug == "advanced")
        #expect(Section.about.slug == "about")
    }

    // MARK: - Parse

    @Test("pane and section round-trip")
    func roundTrip() {
        for section in Section.allCases {
            let bare = SettingsDeepLink(pane: section)
            #expect(parse(bare.urlString) == bare)
            let deep = SettingsDeepLink(pane: section, section: "custom-commands")
            #expect(parse(deep.urlString) == deep)
        }
        #expect(SettingsDeepLink(pane: .twitchIntegration, section: "custom-commands").urlString
            == "wolfwave://settings/twitch/custom-commands")
    }

    @Test("tolerates case and trailing slash")
    func lenientSyntax() {
        #expect(parse("WOLFWAVE://Settings/Twitch/") == SettingsDeepLink(pane: .twitchIntegration))
        #expect(parse("wolfwave://settings/twitch/Custom-Commands")
            == SettingsDeepLink(pane: .twitchIntegration, section: "custom-commands"))
    }

    @Test("bare settings host opens General")
    func bareHost() {
        #expect(parse("wolfwave://settings") == .general)
        #expect(parse("wolfwave://settings/") == .general)
    }

    @Test("unknown pane, host, or scheme falls back to General")
    func fallbacks() {
        #expect(parse("wolfwave://settings/nope") == .general)
        #expect(parse("wolfwave://settings/nope/custom-commands") == .general)
        #expect(parse("wolfwave://now-playing") == .general)
        #expect(parse("https://settings/twitch") == .general)
        #expect(parse("wolfwave://settings/twitch/custom-commands/extra") == .general)
    }

    @Test("unknown or malformed section keeps the pane and drops the section")
    func badSection() {
        #expect(parse("wolfwave://settings/twitch/custom%20commands") == SettingsDeepLink(pane: .twitchIntegration))
        #expect(parse("wolfwave://settings/twitch/../advanced") == .general)
    }
}
