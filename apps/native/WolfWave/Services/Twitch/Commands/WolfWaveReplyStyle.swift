//
//  WolfWaveReplyStyle.swift
//  WolfWave
//
//  Created by Nathanial Henniges on 2026-06-03.
//  Copyright © 2026 MrDemonWolf, Inc. All rights reserved.
//

import Foundation

/// The selectable reply styles for the `!wolfwave` chat command.
///
/// Each case maps to a ready-made chat reply that introduces WolfWave, credits
/// the maker (MrDemonWolf), and links to the site. The streamer picks one from a
/// dropdown in **Settings → Twitch → Bot Commands**; the raw value is stored in
/// `AppConstants.UserDefaults.wolfwaveCommandReplyStyle` and resolved at send
/// time via `current(_:)`, so switching the dropdown takes effect on the next
/// `!wolfwave`.
///
/// Declared `nonisolated` so the chat-dispatch path and the SwiftUI settings
/// view can both read it without crossing actor isolation. The cases are a pure
/// value type, so the enum is `Sendable` automatically.
nonisolated enum WolfWaveReplyStyle: String, CaseIterable, Identifiable, Sendable {

    /// Identity + maker credit. The default: friendly to viewers and streamers,
    /// and names who built it.
    case credit

    /// Lists the viewer-facing commands (`!song`, `!last`, `!sr`).
    case howto

    /// Leads with the free + open-source angle to convert other streamers.
    case pitch

    /// One-line summary plus the link.
    case short

    /// The style applied when nothing has been chosen yet.
    static let `default`: WolfWaveReplyStyle = .credit

    // MARK: - Identifiable

    var id: String { rawValue }

    // MARK: - Settings Picker

    /// Short label shown in the settings dropdown.
    var label: String {
        switch self {
        case .credit: return "Credit + maker"
        case .howto: return "Viewer how-to"
        case .pitch: return "Open-source pitch"
        case .short: return "Short & friendly"
        }
    }

    // MARK: - Chat Reply

    /// The chat reply text sent when a viewer runs `!wolfwave`.
    ///
    /// Links to `AppConstants.URLs.docs` (the WolfWave site) so the URL stays in
    /// sync with the rest of the app. Kept well under Twitch's 500-character
    /// limit; the dispatcher truncates as a final guard.
    var message: String {
        let site = AppConstants.URLs.docs
        switch self {
        case .credit:
            return "🐺 Now playing comes from WolfWave, a free macOS app by MrDemonWolf. It links Apple Music to Twitch chat, Discord, and the stream overlay. \(site)"
        case .howto:
            return "🐺 This stream runs on WolfWave by MrDemonWolf. Try !song, !last, or !sr <song> to request a track. Free for macOS: \(site)"
        case .pitch:
            return "🐺 WolfWave by MrDemonWolf. Free and open source. Apple Music in your chat, Discord presence, and OBS overlay. No account, no paywall. \(site)"
        case .short:
            return "🐺 WolfWave by MrDemonWolf keeps chat, Discord, and the overlay in sync with my Apple Music. Free for macOS. \(site)"
        }
    }

    // MARK: - Resolution

    /// Resolves the streamer's selected style from UserDefaults.
    ///
    /// - Parameter defaults: Store to read from (injectable for tests).
    /// - Returns: The stored style, or ``default`` when unset or unrecognized.
    static func current(_ defaults: Foundation.UserDefaults = .standard) -> WolfWaveReplyStyle {
        guard
            let raw = defaults.string(forKey: AppConstants.UserDefaults.wolfwaveCommandReplyStyle),
            let style = WolfWaveReplyStyle(rawValue: raw)
        else {
            return .default
        }
        return style
    }
}
