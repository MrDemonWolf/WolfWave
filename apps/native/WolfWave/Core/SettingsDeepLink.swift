//
//  SettingsDeepLink.swift
//  WolfWave
//
//  Created by Nathanial Henniges on 2026-09-01.
//  Copyright © 2026 MrDemonWolf, Inc. All rights reserved.
//

import Foundation

/// A parsed `wolfwave://settings/<pane>[/<section>]` URL.
///
/// Parsing never fails: anything that is not a well-formed settings link
/// resolves to the General pane, which is the safe landing spot the ticket
/// asks for. An unknown section on a known pane keeps the pane and drops
/// the section, so a stale docs anchor still opens the right place.
nonisolated struct SettingsDeepLink: Equatable, Sendable {
    /// Custom URL scheme registered in `Info.plist` (`CFBundleURLTypes`).
    static let scheme = "wolfwave"
    /// The only host this parser understands.
    static let host = "settings"

    var pane: SettingsView.SettingsSection
    /// Kebab-case anchor declared at a `.deepLinkSection(_:)` call site.
    var section: String?

    init(pane: SettingsView.SettingsSection, section: String? = nil) {
        self.pane = pane
        self.section = section
    }

    static let general = SettingsDeepLink(pane: .general)

    // MARK: - Parse

    /// Resolves a URL to a destination. Falls back to `.general` on any
    /// scheme, host, or pane mismatch.
    static func parse(_ url: URL) -> SettingsDeepLink {
        guard url.scheme?.lowercased() == scheme,
              url.host()?.lowercased() == host
        else { return .general }

        let parts = url.pathComponents.filter { $0 != "/" && !$0.isEmpty }
        guard !parts.isEmpty else { return .general }
        guard parts.count <= 2 else { return .general }
        guard let pane = SettingsView.SettingsSection(slug: parts[0]) else { return .general }

        var section: String?
        if parts.count == 2 {
            let candidate = parts[1].lowercased()
            // ponytail: section existence is not validated here; an unknown
            // anchor simply has nothing to scroll to and lands on the pane.
            section = isValidSectionSlug(candidate) ? candidate : nil
        }
        return SettingsDeepLink(pane: pane, section: section)
    }

    /// Inverse of `parse` for the cases `parse` accepts, as a string so a
    /// caller never has to handle an impossible `nil`.
    var urlString: String {
        "\(Self.scheme)://\(Self.host)/" + pane.slug + (section.map { "/" + $0 } ?? "")
    }

    /// Section slugs are `[a-z0-9-]+`; anything else is refused so a URL can
    /// never smuggle odd characters into an anchor id.
    static func isValidSectionSlug(_ slug: String) -> Bool {
        !slug.isEmpty && slug.unicodeScalars.allSatisfy {
            ($0 >= "a" && $0 <= "z") || ($0 >= "0" && $0 <= "9") || $0 == "-"
        }
    }
}
