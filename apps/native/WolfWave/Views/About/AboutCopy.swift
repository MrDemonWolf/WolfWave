//
//  AboutCopy.swift
//  WolfWave
//
//  Created by Nathanial Henniges on 2026-05-28.
//  Copyright © 2026 MrDemonWolf, Inc. All rights reserved.
//

import AppKit
import Foundation

/// Shared identity, version, and legal copy used by every surface that shows
/// "About" — the system standard About panel (opened from the menu bar) and
/// the rich `AboutSettingsView` (Settings sidebar tab). Keeps both entry
/// points in sync so trademark + copyright strings don't drift.
enum AboutCopy {

    // MARK: - Bundle Info

    static var appName: String {
        Bundle.main.infoDictionary?["CFBundleDisplayName"] as? String
            ?? Bundle.main.infoDictionary?["CFBundleName"] as? String
            ?? AppConstants.AppInfo.displayName
    }

    static var version: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
    }

    static var build: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "—"
    }

    /// User-facing version label, e.g. `Version 1.2.3 (45)`.
    static var versionString: String {
        "Version \(version) (\(build))"
    }

    /// Clipboard payload for the version pill in `AboutSettingsView`.
    static var versionClipboardPayload: String {
        "\(appName) \(version) (build \(build))"
    }

    // MARK: - Legal Copy

    static let trademarkNotice =
        "Twitch, Discord, OBS, and Apple Music are trademarks of their respective owners. WolfWave is not affiliated with or endorsed by any of them."

    static var copyrightLine: String {
        "© 2026 \(AppConstants.AppInfo.copyrightHolder) All rights reserved."
    }

    // MARK: - Standard About Panel

    /// Options dictionary for `NSApplication.orderFrontStandardAboutPanel(options:)`.
    /// Supplies a centered trademark notice as credits; the copyright line comes
    /// from `Info.plist`'s `NSHumanReadableCopyright`, which the panel renders
    /// automatically alongside the icon, name, and version.
    static func standardAboutPanelOptions() -> [NSApplication.AboutPanelOptionKey: Any] {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center

        let credits = NSAttributedString(
            string: trademarkNotice,
            attributes: [
                .font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize),
                .foregroundColor: NSColor.secondaryLabelColor,
                .paragraphStyle: paragraph
            ]
        )

        return [
            .credits: credits,
            .applicationVersion: version,
            .version: build
        ]
    }
}
